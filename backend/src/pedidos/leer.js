// Leer pedidos con sus lineas, en la forma que devuelve la API.
//
// Una sola funcion para todas las rutas: la respuesta al crear, la lista de activos y el
// detalle de uno. Asi un pedido se ve igual venga de donde venga.
//
// El celular del cliente solo lo recibe quien lo va a usar: recepcion, para avisarle que
// su pedido esta listo. A cocina no le hace falta, y un dato personal que no se necesita no
// se entrega (D-31).

const SQL_PEDIDOS = `
  SELECT p.id, p.estado, p.para_llevar, p.observacion, p.total, p.creado_en,
         p.creado_por_nombre, c.nombre AS cliente_nombre, c.celular AS cliente_celular
    FROM pedido p
    JOIN cliente c ON c.id = p.cliente_id
   WHERE p.id = ANY($1::int[])
   ORDER BY p.creado_en, p.id`;

// Los extras son lineas colgadas de la linea de su pizza (linea_de_id, D-28). Se leen
// todas juntas y se agrupan aqui: una consulta por pedido seria una por cada tarjeta de
// la cola de cocina.
const SQL_LINEAS = `
  SELECT d.id, d.pedido_id, d.linea_de_id, d.cantidad, d.precio_unitario, d.subtotal,
         pr.id AS producto_id, pr.nombre AS producto_nombre, pr.categoria AS producto_categoria,
         m.id AS mitad_id, m.nombre AS mitad_nombre
    FROM detalle_pedido d
    JOIN producto pr ON pr.id = d.producto_id
    LEFT JOIN producto m ON m.id = d.producto_mitad_id
   WHERE d.pedido_id = ANY($1::int[])
   ORDER BY d.pedido_id, d.id`;

// pg entrega los numeric como texto para no perder precision. Con dos decimales caben
// exactos en un numero de JSON.
function aLinea(fila) {
  return {
    id: fila.id,
    producto: { id: fila.producto_id, nombre: fila.producto_nombre, categoria: fila.producto_categoria },
    mitad: fila.mitad_id === null ? null : { id: fila.mitad_id, nombre: fila.mitad_nombre },
    cantidad: fila.cantidad,
    precioUnitario: Number(fila.precio_unitario),
    subtotal: Number(fila.subtotal),
    extras: [],
  };
}

function aPedido(fila, lineas, verCelular) {
  const cliente = { nombre: fila.cliente_nombre };
  if (verCelular) cliente.celular = fila.cliente_celular;
  return {
    id: fila.id,
    estado: fila.estado,
    paraLlevar: fila.para_llevar,
    cliente,
    observacion: fila.observacion,
    total: Number(fila.total),
    creadoEn: fila.creado_en,
    creadoPor: fila.creado_por_nombre,
    lineas,
  };
}

// "db" puede ser el pool o el cliente de una transaccion: los dos tienen query().
async function leerPedidos(db, ids, { verCelular }) {
  if (ids.length === 0) return [];
  const { rows: pedidos } = await db.query(SQL_PEDIDOS, [ids]);
  const { rows: filas } = await db.query(SQL_LINEAS, [ids]);

  const lineasDe = new Map(pedidos.map((p) => [p.id, []]));
  const porId = new Map();
  for (const fila of filas) {
    const linea = aLinea(fila);
    porId.set(fila.id, linea);
    if (fila.linea_de_id === null) {
      const delPedido = lineasDe.get(fila.pedido_id);
      if (delPedido) delPedido.push(linea);
    } else {
      // Las lineas vienen ordenadas por id, y un extra siempre se guarda despues de su
      // pizza: cuando llega el extra, su pizza ya esta en el mapa.
      const pizza = porId.get(fila.linea_de_id);
      const { extras, mitad, ...extra } = linea;
      if (pizza) pizza.extras.push(extra);
    }
  }

  return pedidos.map((p) => aPedido(p, lineasDe.get(p.id), verCelular));
}

// La cola: los pedidos en esos estados, en orden de llegada. El tope solo importa si alguien
// pide los entregados o cancelados, que se acumulan; los activos de un local son pocos.
const SQL_IDS_POR_ESTADO = `
  SELECT id
    FROM pedido
   WHERE estado = ANY($1::estado_pedido[])
   ORDER BY creado_en, id
   LIMIT 200`;

async function idsPorEstados(db, estados) {
  const { rows } = await db.query(SQL_IDS_POR_ESTADO, [estados]);
  return rows.map((r) => r.id);
}

// La trazabilidad de un pedido: cada cambio con quien lo hizo, cuando y, si fue una
// cancelacion, por que.
const SQL_HISTORIAL = `
  SELECT estado, usuario_nombre, fecha_hora, motivo
    FROM historial_estado
   WHERE pedido_id = $1
   ORDER BY fecha_hora, id`;

async function leerHistorial(db, id) {
  const { rows } = await db.query(SQL_HISTORIAL, [id]);
  return rows.map((f) => ({
    estado: f.estado, usuario: f.usuario_nombre, fechaHora: f.fecha_hora, motivo: f.motivo,
  }));
}

// Quien puede ver el celular del cliente.
function puedeVerCelular(usuario) {
  return Boolean(usuario && usuario.roles && usuario.roles.includes('recepcion'));
}

module.exports = { leerPedidos, idsPorEstados, leerHistorial, puedeVerCelular };
