// Agregar productos a un pedido ya enviado (D-37): la soda que el cliente pide despues de
// la pizza, sin hacer otro pedido.
//
// Que se puede agregar depende del estado del pedido:
//
//   pendiente, en preparacion   bebidas y pizzas (cocina recibe el aviso)
//   listo                       solo bebidas: una pizza nueva obligaria a devolverlo a cocina
//   entregado, cancelado        nada: esta cerrado
//
// Solo se AGREGA: nada de lo enviado se quita ni se cambia. Por eso la cantidad de lineas
// de un pedido sirve de version (ver estados.js).
const { ErrorApi } = require('../errores');
const { idsDeProductos, calcularLineas, aBolivianos } = require('../precio');
const { guardarLineas, aNumeric, nombreDe, SQL_PRODUCTOS } = require('./crear');

const SE_PUEDE_AGREGAR = {
  pendiente: { pizzas: true },
  en_preparacion: { pizzas: true },
  listo: { pizzas: false },
};

// El mismo bloqueo que un cambio de estado: si cocina marca "listo" justo cuando recepcion
// agrega una pizza, la segunda operacion espera a la primera y ve el estado que dejo.
const SQL_PEDIDO = 'SELECT estado FROM pedido WHERE id = $1 FOR UPDATE';
const SQL_SUMAR_AL_TOTAL = 'UPDATE pedido SET total = total + $2 WHERE id = $1';

function comoSeDice(estado) {
  return estado.replace('_', ' ');
}

async function agregarAlPedido(pool, id, agregado, usuario) {
  const db = await pool.connect();
  let conexionRota = false;
  try {
    await db.query('BEGIN');

    const { rows: [pedido] } = await db.query(SQL_PEDIDO, [id]);
    if (!pedido) {
      throw new ErrorApi(404, 'PEDIDO_NO_ENCONTRADO', `No existe el pedido #${id}.`);
    }
    const permitido = SE_PUEDE_AGREGAR[pedido.estado];
    if (!permitido) {
      throw new ErrorApi(409, 'AGREGADO_NO_PERMITIDO',
        `El pedido #${id} esta ${comoSeDice(pedido.estado)}: ya no se le puede agregar nada. Haz una venta nueva.`,
        { estadoActual: pedido.estado });
    }

    const { rows } = await db.query(SQL_PRODUCTOS, [idsDeProductos(agregado)]);
    const calculo = calcularLineas(agregado, new Map(rows.map((p) => [p.id, p])));

    if (calculo.hayPizzas && !permitido.pizzas) {
      throw new ErrorApi(409, 'AGREGADO_NO_PERMITIDO',
        `El pedido #${id} ya esta listo: las pizzas nuevas van en otro pedido. Las bebidas si se pueden agregar.`,
        { estadoActual: pedido.estado });
    }
    if (calculo.total !== agregado.totalEsperadoCentavos) {
      throw new ErrorApi(409, 'PRECIO_CAMBIADO',
        `La carta cambio mientras se armaba la venta. Lo agregado suma Bs ${aBolivianos(calculo.total)}.`,
        { totalCorrecto: aBolivianos(calculo.total) });
    }

    await guardarLineas(db, id, calculo.lineas, { sub: usuario.sub, nombre: nombreDe(usuario) });
    await db.query(SQL_SUMAR_AL_TOTAL, [id, aNumeric(calculo.total)]);

    await db.query('COMMIT');
    return { hayPizzas: calculo.hayPizzas };
  } catch (err) {
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

module.exports = { agregarAlPedido, SE_PUEDE_AGREGAR };
