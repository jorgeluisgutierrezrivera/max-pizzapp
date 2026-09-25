// Los cambios de estado de un pedido: quien puede hacer cada uno y desde donde.
//
//   pendiente -> en_preparacion -> listo -> entregado
//        \___> cancelado (solo mientras esta pendiente, con motivo)
//
// Cuando cocina lo empieza, ya no se cancela (D-41): la preparacion es corta y lo que entra
// al horno ya se gasto. Recepcion puede seguir agregandole cosas (D-37).
//
// La app oculta los botones que no corresponden, pero quien decide es el servidor: una
// peticion armada a mano recibe el mismo 403 o 409 que un boton que no deberia estar.
const { ErrorApi } = require('../errores');

// Una fila por destino. "desde" son los estados en los que el cambio es valido; "rol", quien
// lo hace. Ningun destino tiene dos duenos.
const TRANSICIONES = {
  en_preparacion: { desde: ['pendiente'], rol: 'cocina' },
  listo: { desde: ['en_preparacion'], rol: 'cocina' },
  entregado: { desde: ['listo'], rol: 'recepcion' },
  cancelado: { desde: ['pendiente'], rol: 'recepcion' },
};

const QUIEN = { cocina: 'cocina', recepcion: 'recepcion' };

// FOR UPDATE: la fila queda tomada hasta el COMMIT. Si dos personas tocan el mismo pedido a
// la vez, la segunda espera, lee el estado que dejo la primera y recibe un 409.
const SQL_ESTADO_ACTUAL = 'SELECT estado FROM pedido WHERE id = $1 FOR UPDATE';
const SQL_CAMBIAR = 'UPDATE pedido SET estado = $2::estado_pedido WHERE id = $1';

// La version del pedido (D-37): cuantas lineas tiene. Las lineas solo se agregan, nunca se
// quitan, asi que si el numero cambio, alguien agrego algo. Se cuenta en una consulta
// APARTE, despues de tomar la fila: en READ COMMITTED cada consulta ve lo ultimo
// confirmado, y asi incluye lo que agrego quien tenia la fila tomada hasta recien.
const SQL_VERSION = 'SELECT count(*)::int AS version FROM detalle_pedido WHERE pedido_id = $1';
const SQL_HISTORIAL = `
  INSERT INTO historial_estado (pedido_id, estado, usuario_id, usuario_nombre, motivo)
  VALUES ($1, $2::estado_pedido, $3, $4, $5)`;

function nombreDe(usuario) {
  return (usuario.nombre || usuario.usuario || 'sin nombre').slice(0, 120);
}

// Antes de tocar la base: el rol tiene que ser el dueno de ese cambio.
function comprobarRol(hacia, usuario) {
  const { rol } = TRANSICIONES[hacia];
  if (!usuario.roles.includes(rol)) {
    throw new ErrorApi(403, 'ROL_SIN_PERMISO',
      `Solo ${QUIEN[rol]} puede marcar un pedido como ${hacia.replace('_', ' ')}.`);
  }
}

// Cambia el estado en una transaccion y deja su fila en el historial. Devuelve el estado
// anterior, que el aviso en vivo necesita.
//
// "versionVista" es la version del pedido que tenia a la vista quien toco el boton. Si
// despues se le agrego algo, el cambio se rechaza: nadie marca listo, ni entrega, un pedido
// sin haber visto lo ultimo que se le agrego.
async function cambiarEstado(pool, id, hacia, usuario, motivo = null, versionVista = null) {
  comprobarRol(hacia, usuario);
  const db = await pool.connect();
  let conexionRota = false;
  try {
    await db.query('BEGIN');
    const { rows } = await db.query(SQL_ESTADO_ACTUAL, [id]);
    if (rows.length === 0) {
      throw new ErrorApi(404, 'PEDIDO_NO_ENCONTRADO', `No existe el pedido #${id}.`);
    }
    const anterior = rows[0].estado;
    if (!TRANSICIONES[hacia].desde.includes(anterior)) {
      throw new ErrorApi(409, 'TRANSICION_NO_PERMITIDA',
        `El pedido #${id} esta ${anterior.replace('_', ' ')}: no puede pasar a ${hacia.replace('_', ' ')}.`,
        { estadoActual: anterior });
    }
    if (versionVista !== null) {
      const { rows: [{ version }] } = await db.query(SQL_VERSION, [id]);
      if (version !== versionVista) {
        throw new ErrorApi(409, 'PEDIDO_CAMBIADO',
          `Al pedido #${id} se le agrego algo. Revisalo antes de marcarlo ${hacia.replace('_', ' ')}.`,
          { version });
      }
    }
    await db.query(SQL_CAMBIAR, [id, hacia]);
    await db.query(SQL_HISTORIAL, [id, hacia, usuario.sub, nombreDe(usuario), motivo]);
    await db.query('COMMIT');
    return { anterior };
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

module.exports = { TRANSICIONES, cambiarEstado };
