// El canal en vivo: Socket.IO sobre el mismo servidor HTTP que la API (D-04, D-21).
//
// Cocina ve el pedido nuevo en menos de 2 segundos sin recargar, y las dos pantallas se
// enteran de cada cambio de estado.
//
// Cuatro reglas:
//   1. Sin token valido no hay conexion. Se valida con el MISMO verificador que la API.
//   2. Cada conexion entra a la sala de su rol, y cada evento va solo a quien le sirve.
//   3. El canal AVISA; la fuente es la API. Si una pantalla se pierde un aviso, recarga la
//      lista y queda al dia.
//   4. Una conexion no dura mas que su token (D-47): se corta cuando vence, y la app se
//      reconecta con el token que ya renovo.
const { Server } = require('socket.io');

// El latido (D-44). El servidor manda un ping cada pingInterval, y el cliente da la conexion
// por perdida si pasa pingInterval + pingTimeout sin recibir ninguno: con estos valores, 7 s.
// Los de fabrica (25 s + 20 s) tardaban hasta 45 s en notar una red colgada, y RNF-05 pide
// avisar en menos de 10. Cuesta un paquete de pocos bytes cada 4 s por pantalla.
const LATIDO = { pingInterval: 4000, pingTimeout: 3000 };
const TAMANO_MAXIMO_DE_MENSAJE = 16 * 1024;

// setTimeout no acepta plazos de mas de ~24,8 dias: uno mayor dispararia en el acto.
const PLAZO_MAXIMO_MS = 2 ** 31 - 1;

const SALA = { recepcion: 'rol:recepcion', cocina: 'rol:cocina' };

// Lo que cocina recibe de un pedido: todo menos el celular del cliente (D-31).
function paraCocina(pedido) {
  return { ...pedido, cliente: pedido.cliente && { nombre: pedido.cliente.nombre } };
}

// Los estados que cocina tiene en su cola.
const EN_COCINA = ['pendiente', 'en_preparacion'];

// El reloj se puede reemplazar en las pruebas, para comprobar que el corte programado se
// cancela cuando la conexion se cierra antes.
function crearCanal(servidorHttp, { usuarioDelToken, reloj = { setTimeout, clearTimeout } }) {
  // Mismo origen que la app: Caddy sirve las dos cosas desde el mismo dominio, asi que no
  // hace falta abrir CORS. La ruta es la de siempre, /socket.io/, que Caddy ya reenvia.
  // El canal solo emite: los clientes no le mandan mensajes, salvo el saludo con el token.
  // Por eso el mensaje mas grande que acepta baja de 1 MB, el de fabrica, a 16 KB (D-52).
  const io = new Server(servidorHttp, { serveClient: false, maxHttpBufferSize: TAMANO_MAXIMO_DE_MENSAJE, ...LATIDO });

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
    const { usuario } = socket.data;
    for (const rol of usuario.roles) socket.join(SALA[rol]);

    // D-47: el token se comprueba al conectarse, y sin esto la conexion seguiria recibiendo
    // pedidos despues de que venciera. Se corta a esa hora; la app, que renueva el token a
    // los 48 minutos, se reconecta en el acto con el nuevo.
    if (Number.isFinite(usuario.venceEn)) {
      const restante = Math.min(Math.max(usuario.venceEn - Date.now(), 0), PLAZO_MAXIMO_MS);
      const corte = reloj.setTimeout(() => socket.disconnect(true), restante);
      socket.on('disconnect', () => reloj.clearTimeout(corte));
    }
  });

  return {
    // Un pedido recien guardado. A recepcion, completo; a cocina, sin el celular. La venta
    // directa de bebidas no se avisa: nace entregada y no entra en ninguna lista (D-38).
    pedidoNuevo(pedido) {
      if (pedido.cliente === null) return;
      io.to(SALA.recepcion).emit('pedido:nuevo', pedido);
      if (EN_COCINA.includes(pedido.estado)) io.to(SALA.cocina).emit('pedido:nuevo', paraCocina(pedido));
    },

    // Se le agrego algo a un pedido (D-37). Va completo, para que cada pantalla reemplace su
    // tarjeta: a recepcion siempre; a cocina, si el pedido esta en su cola.
    pedidoActualizado(pedido) {
      io.to(SALA.recepcion).emit('pedido:actualizado', pedido);
      if (EN_COCINA.includes(pedido.estado)) io.to(SALA.cocina).emit('pedido:actualizado', paraCocina(pedido));
    },

    // Un cambio de estado, a los dos roles: cual pedido, desde donde, hacia donde y cuando.
    estadoCambiado({ id, anterior, nuevo }) {
      const aviso = { id, anterior, nuevo, fechaHora: new Date().toISOString() };
      io.to(SALA.recepcion).to(SALA.cocina).emit('pedido:estado', aviso);
    },

    // Un producto se marco agotado o disponible (RF-13, D-67). A las dos salas: a las dos les
    // cambia la carta. "por" es el rol que lo marco, no la persona.
    disponibilidadCambiada({ id, nombre, categoria, disponible, por }) {
      const aviso = { id, nombre, categoria, disponible, por, fechaHora: new Date().toISOString() };
      io.to(SALA.recepcion).to(SALA.cocina).emit('producto:disponibilidad', aviso);
    },

    // Una categoria entera se agoto o se repuso (D-70): un solo aviso, con los que cambiaron.
    categoriaCambiada({ categoria, disponible, ids, por }) {
      const aviso = { categoria, disponible, ids, por, fechaHora: new Date().toISOString() };
      io.to(SALA.recepcion).to(SALA.cocina).emit('categoria:disponibilidad', aviso);
    },

    // Cierra el canal Y el servidor HTTP que comparte con la API: corta las conexiones en
    // vivo, deja de aceptar peticiones y llama a "listo" cuando terminaron las que estaban.
    cerrar: (listo) => io.close(listo),
  };
}

// Para las pruebas y para arrancar sin canal: avisos que no hacen nada.
const SIN_AVISOS = {
  pedidoNuevo() {}, pedidoActualizado() {}, estadoCambiado() {}, disponibilidadCambiada() {}, categoriaCambiada() {},
};

// Un aviso que falla no deshace nada: la operacion ya se guardo y se respondio. Se anota y
// la pantalla se pone al dia la proxima vez que lea la lista.
function avisar(accion) {
  try {
    accion();
  } catch (err) {
    console.error('[canal] no se pudo avisar:', err.message);
  }
}

module.exports = { crearCanal, SIN_AVISOS, avisar, TAMANO_MAXIMO_DE_MENSAJE };
