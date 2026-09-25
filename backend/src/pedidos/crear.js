// Guardar una venta como pedido, en UNA transaccion.
//
// El cliente, el pedido, sus lineas, los extras colgados de cada pizza y el primer registro
// del historial se guardan juntos o no se guarda nada. Todas las consultas van con
// parametros: ningun dato de la venta se pega al texto SQL.
const { ErrorApi } = require('../errores');
const { idsDeProductos, calcularVenta, aBolivianos } = require('../precio');

// FOR SHARE: mientras dura la transaccion, nadie puede cambiar el precio ni la
// disponibilidad de estos productos. El precio que se calcula es el que se guarda.
const SQL_PRODUCTOS = `
  SELECT id, nombre, categoria, precio, disponible
    FROM producto
   WHERE id = ANY($1::int[])
     FOR SHARE`;

// El celular identifica al cliente (D-31): si ya esta registrado, se usa ese cliente y se
// actualiza el nombre con el que se anuncia ahora. Sin celular, es un cliente nuevo.
const SQL_CLIENTE_CON_CELULAR = `
  INSERT INTO cliente (nombre, celular) VALUES ($1, $2)
  ON CONFLICT (celular) WHERE celular IS NOT NULL
  DO UPDATE SET nombre = EXCLUDED.nombre
  RETURNING id`;
const SQL_CLIENTE_SIN_CELULAR = 'INSERT INTO cliente (nombre) VALUES ($1) RETURNING id';

// El numero del dia (D-35): empieza en 1 cada dia y no tiene huecos. Dos ventas a la vez
// tomarian el mismo maximo, asi que antes se pide un bloqueo de TRANSACCION: la segunda
// espera a que la primera termine (COMMIT o ROLLBACK) y recien entonces lee el maximo. Si
// la venta falla, el bloqueo se suelta con el ROLLBACK y el numero no se gasta. La base
// respalda la regla con la restriccion unica (dia, numero_del_dia).
//
// La hora del pedido se toma DESPUES del bloqueo (clock_timestamp, no now(), que es la del
// inicio de la transaccion): asi el orden de los numeros es el orden de llegada que sigue
// la cola de cocina, y el dia del numero es el mismo que la base calcula en pedido.dia.
const SQL_BLOQUEO_DEL_NUMERO = "SELECT pg_advisory_xact_lock(hashtext('pedido.numero_del_dia'))";
const SQL_SIGUIENTE_NUMERO = `
  WITH ahora AS (SELECT clock_timestamp() AS en)
  SELECT ahora.en AS creado_en,
         coalesce((SELECT max(numero_del_dia)
                     FROM pedido
                    WHERE dia = (ahora.en AT TIME ZONE 'America/La_Paz')::date), 0) + 1 AS numero
    FROM ahora`;

// El estado va con su tipo explicito: un texto sin tipo contra una columna enumerada es el
// error E-002 del proyecto anterior.
const SQL_PEDIDO = `
  INSERT INTO pedido
    (cliente_id, creado_por, creado_por_nombre, estado, observacion, total, para_llevar,
     numero_del_dia, creado_en)
  VALUES ($1, $2, $3, $4::estado_pedido, $5, $6, $7, $8, coalesce($9::timestamptz, now()))
  RETURNING id`;

const SQL_LINEA = `
  INSERT INTO detalle_pedido
    (pedido_id, producto_id, producto_mitad_id, linea_de_id, cantidad, precio_unitario, subtotal)
  VALUES ($1, $2, $3, $4, $5, $6, $7)
  RETURNING id`;

// La misma linea, agregada a un pedido ya enviado: con la hora y quien (D-37).
const SQL_LINEA_AGREGADA = `
  INSERT INTO detalle_pedido
    (pedido_id, producto_id, producto_mitad_id, linea_de_id, cantidad, precio_unitario, subtotal,
     agregado_en, agregado_por, agregado_por_nombre)
  VALUES ($1, $2, $3, $4, $5, $6, $7, now(), $8, $9)
  RETURNING id`;

const SQL_HISTORIAL = `
  INSERT INTO historial_estado (pedido_id, estado, usuario_id, usuario_nombre)
  VALUES ($1, $2::estado_pedido, $3, $4)`;

// Centavos enteros a numeric: 4750 -> '47.50', sin pasar por la coma flotante.
function aNumeric(centavos) {
  return (centavos / 100).toFixed(2);
}

function nombreDe(usuario) {
  return (usuario.nombre || usuario.usuario || 'sin nombre').slice(0, 120);
}

// Cada pizza, y sus extras colgados de ella (linea_de_id, D-28). "agregadoPor" es quien las
// agrega, cuando llegan despues de enviar el pedido (D-37); al crearlo, no hay nadie.
async function guardarLineas(db, pedidoId, lineas, agregadoPor = null) {
  const sql = agregadoPor ? SQL_LINEA_AGREGADA : SQL_LINEA;
  const quien = agregadoPor ? [agregadoPor.sub, agregadoPor.nombre] : [];
  for (const linea of lineas) {
    const { rows: [guardada] } = await db.query(sql, [
      pedidoId, linea.productoId, linea.mitadId, null,
      linea.cantidad, aNumeric(linea.unitario), aNumeric(linea.subtotal), ...quien,
    ]);
    for (const extra of linea.extras) {
      await db.query(sql, [
        pedidoId, extra.productoId, null, guardada.id,
        extra.cantidad, aNumeric(extra.unitario), aNumeric(extra.subtotal), ...quien,
      ]);
    }
  }
}

async function crearPedido(pool, venta, usuario) {
  const db = await pool.connect();
  let conexionRota = false;
  try {
    await db.query('BEGIN');

    const { rows } = await db.query(SQL_PRODUCTOS, [idsDeProductos(venta)]);
    const calculo = calcularVenta(venta, new Map(rows.map((p) => [p.id, p])));

    // La app muestra una vista previa del total; el que vale es este. Si no coinciden, la
    // carta cambio en medio de la venta y la vendedora estaria cobrando otro precio.
    if (calculo.total !== venta.totalEsperadoCentavos) {
      throw new ErrorApi(409, 'PRECIO_CAMBIADO',
        `La carta cambio mientras se armaba la venta. El total correcto es Bs ${aBolivianos(calculo.total)}.`,
        { totalCorrecto: aBolivianos(calculo.total) });
    }

    // La venta directa de bebidas no lleva cliente ni numero: nadie la canta (D-38).
    let clienteId = null;
    let numero = null;
    let creadoEn = null;
    if (!venta.ventaDirecta) {
      const { nombre, celular } = venta.cliente;
      const { rows: [cliente] } = celular
        ? await db.query(SQL_CLIENTE_CON_CELULAR, [nombre, celular])
        : await db.query(SQL_CLIENTE_SIN_CELULAR, [nombre]);
      clienteId = cliente.id;

      await db.query(SQL_BLOQUEO_DEL_NUMERO);
      ({ rows: [{ numero, creado_en: creadoEn }] } = await db.query(SQL_SIGUIENTE_NUMERO));
    }

    const quien = nombreDe(usuario);
    const { rows: [pedido] } = await db.query(SQL_PEDIDO, [
      clienteId, usuario.sub, quien, calculo.estadoInicial,
      venta.observacion, aNumeric(calculo.total), venta.paraLlevar, numero, creadoEn,
    ]);

    await guardarLineas(db, pedido.id, calculo.lineas);

    // El primer registro de la trazabilidad: quien creo el pedido, cuando y en que estado.
    // En la venta directa, quien la vendio: nace entregada.
    await db.query(SQL_HISTORIAL, [pedido.id, calculo.estadoInicial, usuario.sub, quien]);

    await db.query('COMMIT');
    return pedido.id;
  } catch (err) {
    // Si el ROLLBACK tambien falla, la conexion esta rota: se informa el error original y
    // la conexion se descarta en vez de devolverla al pool.
    try {
      await db.query('ROLLBACK');
    } catch {
      conexionRota = true;
    }
    throw err;
  } finally {
    db.release(conexionRota);
  }
}

module.exports = { crearPedido, guardarLineas, aNumeric, nombreDe, SQL_PRODUCTOS };
