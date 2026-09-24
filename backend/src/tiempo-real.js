// El canal en vivo: Socket.IO sobre el mismo servidor HTTP que la API (D-04, D-21).
//
// Lo minimo que exige el E2: cocina ve el pedido nuevo en menos de 2 segundos sin recargar,
// y las dos pantallas se enteran de cada cambio de estado. La robustez (reconectar sola,
// avisar cuando el canal se cae, renovar el token de una conexion abierta) es la tarjeta 07.
//
// Tres reglas:
//   1. Sin token valido no hay conexion. Se valida con el MISMO verificador que la API.
//   2. Cada conexion entra a la sala de su rol, y cada evento va solo a quien le sirve.
//   3. El canal AVISA; la fuente es la API. Si una pantalla se pierde un aviso, recarga la
//      lista y queda al dia.
const { Server } = require('socket.io');

const SALA = { recepcion: 'rol:recepcion', cocina: 'rol:cocina' };

// Lo que cocina recibe de un pedido: todo menos el celular del cliente (D-31).
function paraCocina(pedido) {
  return { ...pedido, cliente: { nombre: pedido.cliente.nombre } };
}

function crearCanal(servidorHttp, { usuarioDelToken }) {
  // Mismo origen que la app: Caddy sirve las dos cosas desde el mismo dominio, asi que no
  // hace falta abrir CORS. La ruta es la de siempre, /socket.io/, que Caddy ya reenvia.
  const io = new Server(servidorHttp, { serveClient: false });

  // El token viaja en el saludo (handshake.auth), no en la direccion: una direccion con el
  // token quedaria escrita en los registros de cualquier proxy.
  io.use(async (socket, next) => {
    try {
      const usuario = await usuarioDelToken(socket.handshake.auth && socket.handshake.auth.token);
      if (usuario.roles.length === 0) {
        const err = new Error('Tu rol no permite esta operacion.');
        err.data = { codigo: 'ROL_SIN_PERMISO' };
        return next(err);
      }
      socket.data.usuario = usuario;
      return next();
    } catch (fallo) {
      const err = new Error(fallo.message);
      err.data = { codigo: fallo.codigo || 'TOKEN_INVALIDO' };
      return next(err);
    }
  });

  io.on('connection', (socket) => {
    for (const rol of socket.data.usuario.roles) socket.join(SALA[rol]);
  });

  return {
    // Un pedido recien guardado. A recepcion, completo; a cocina, sin el celular, y solo si
    // tiene algo que preparar: un pedido de solo bebidas nace listo y no le llega (D-32).
    pedidoNuevo(pedido) {
      io.to(SALA.recepcion).emit('pedido:nuevo', pedido);
      if (pedido.estado !== 'listo') io.to(SALA.cocina).emit('pedido:nuevo', paraCocina(pedido));
    },

    // Un cambio de estado, a los dos roles: cual pedido, desde donde, hacia donde y cuando.
    estadoCambiado({ id, anterior, nuevo }) {
      const aviso = { id, anterior, nuevo, fechaHora: new Date().toISOString() };
      io.to(SALA.recepcion).to(SALA.cocina).emit('pedido:estado', aviso);
    },

    // Cierra el canal Y el servidor HTTP que comparte con la API: corta las conexiones en
    // vivo, deja de aceptar peticiones y llama a "listo" cuando terminaron las que estaban.
    cerrar: (listo) => io.close(listo),
  };
}

// Para las pruebas y para arrancar sin canal: avisos que no hacen nada.
const SIN_AVISOS = { pedidoNuevo() {}, estadoCambiado() {} };

module.exports = { crearCanal, SIN_AVISOS };
