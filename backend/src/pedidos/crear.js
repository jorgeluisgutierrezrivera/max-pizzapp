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

// El estado va con su tipo explicito: un texto sin tipo contra una columna enumerada es el
// error E-002 del proyecto anterior.
const SQL_PEDIDO = `
  INSERT INTO pedido (cliente_id, creado_por, creado_por_nombre, estado, observacion, total, para_llevar)
  VALUES ($1, $2, $3, $4::estado_pedido, $5, $6, $7)
  RETURNING id`;

const SQL_LINEA = `
  INSERT INTO detalle_pedido
    (pedido_id, producto_id, producto_mitad_id, linea_de_id, cantidad, precio_unitario, subtotal)
  VALUES ($1, $2, $3, $4, $5, $6, $7)
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

    const { nombre, celular } = venta.cliente;
    const { rows: [cliente] } = celular
      ? await db.query(SQL_CLIENTE_CON_CELULAR, [nombre, celular])
      : await db.query(SQL_CLIENTE_SIN_CELULAR, [nombre]);

    const quien = nombreDe(usuario);
    const { rows: [pedido] } = await db.query(SQL_PEDIDO, [
      cliente.id, usuario.sub, quien, calculo.estadoInicial,
      venta.observacion, aNumeric(calculo.total), venta.paraLlevar,
    ]);

    for (const linea of calculo.lineas) {
      const { rows: [guardada] } = await db.query(SQL_LINEA, [
        pedido.id, linea.productoId, linea.mitadId, null,
        linea.cantidad, aNumeric(linea.unitario), aNumeric(linea.subtotal),
      ]);
      for (const extra of linea.extras) {
        await db.query(SQL_LINEA, [
          pedido.id, extra.productoId, null, guardada.id,
          extra.cantidad, aNumeric(extra.unitario), aNumeric(extra.subtotal),
        ]);
      }
    }

    // El primer registro de la trazabilidad: quien creo el pedido, cuando y en que estado.
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

module.exports = { crearPedido };
