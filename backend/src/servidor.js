const http = require('node:http');
const { crearApp } = require('./app');
const { crearCanal } = require('./tiempo-real');

// La API y el canal en vivo comparten el servidor HTTP y el puerto: Caddy reenvia /api/ y
// /socket.io/ al mismo proceso, y el aviso sale en la misma operacion que guarda el cambio.
//
// EL ORDEN IMPORTA. Socket.IO toma las peticiones de /socket.io/ envolviendo los
// manejadores que el servidor YA tiene al conectarse. Por eso Express va primero, al crear
// el servidor, y el canal despues. Al reves, Express tambien respondia /socket.io/ con un
// 404, Socket.IO intentaba responder encima y el proceso se caia (lo encontro la prueba
// contra la API real, tarjeta 06, fase D).
//
// Como la app se crea antes que el canal, recibe unos avisos que llaman al canal cuando ya
// existe. Los avisos siempre salen despues de que el servidor esta escuchando.
function crearServidor({ pool, autenticar }) {
  let canal = null;
  const avisos = {
    pedidoNuevo: (pedido) => canal.pedidoNuevo(pedido),
    estadoCambiado: (aviso) => canal.estadoCambiado(aviso),
  };
  const servidor = http.createServer(crearApp({ pool, autenticar, avisos }));
  canal = crearCanal(servidor, { usuarioDelToken: autenticar.usuarioDelToken });
  return { servidor, canal };
}

module.exports = { crearServidor };
