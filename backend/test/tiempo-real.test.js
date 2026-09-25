// Pruebas del canal en vivo con el cliente real de Socket.IO, el mismo protocolo que usa la
// app. Tokens del emisor local: validos, sin rol, vencidos, de otra clave y de otra audiencia.
// Se comprueba quien puede conectarse y a quien le llega cada aviso.
// El servidor se arma con crearServidor, IGUAL que en produccion: la API y el canal juntos.
// Una primera version montaba el canal solo, sin Express, y no vio que los dos respondian
// /socket.io/ a la vez y el proceso se caia.
// Que el aviso salga despues del COMMIT, y nunca si la operacion falla, lo comprueban
// pedidos.test.js y estados.test.js; la latencia real, pruebas/tiempo-real/.
const test = require('node:test');
const assert = require('node:assert/strict');
const { io: conectar } = require('socket.io-client');
const { crearServidor } = require('../src/servidor');
const { firmar, ajena, deRecepcion, deCocina, sinRol, levantarEmisor } = require('./soporte/emisor');

let emisor;
let servidor;
let canal;
let url;
const abiertos = [];

test.before(async () => {
  emisor = await levantarEmisor();
  const pool = { query: async () => ({ rows: [] }) };
  ({ servidor, canal } = crearServidor({ pool, autenticar: emisor.autenticar }));
  await new Promise((listo) => servidor.listen(0, '127.0.0.1', listo));
  url = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  abiertos.forEach((s) => s.close());
  await new Promise((listo) => canal.cerrar(listo));
  emisor.cerrar();
});

// Conecta con ese token y resuelve cuando el servidor acepta o rechaza la conexion.
function entrar(token) {
  const socket = conectar(url, {
    auth: token === undefined ? {} : { token }, transports: ['websocket'], reconnection: false,
  });
  abiertos.push(socket);
  return new Promise((resolver) => {
    socket.on('connect', () => resolver({ socket, conectado: true }));
    socket.on('connect_error', (err) => resolver({ socket, conectado: false, codigo: err.data && err.data.codigo }));
  });
}

// Espera un evento; si no llega en ese tiempo, resuelve null.
function esperar(socket, evento, ms = 1000) {
  return new Promise((resolver) => {
    const reloj = setTimeout(() => resolver(null), ms);
    socket.once(evento, (datos) => { clearTimeout(reloj); resolver(datos); });
  });
}

const PEDIDO = {
  id: 42, estado: 'pendiente', paraLlevar: true, total: 50, observacion: null,
  cliente: { nombre: 'Ana Prueba', celular: '70000001' }, lineas: [],
};

// --- la API y el canal en el mismo servidor ------------------------------------------------

test('/socket.io/ lo responde Socket.IO, no Express, y el servidor sigue en pie', async () => {
  for (let i = 0; i < 3; i += 1) {
    const r = await fetch(`${url}/socket.io/?EIO=4&transport=polling`);
    assert.equal(r.status, 200);
    assert.match(await r.text(), /^0\{"sid"/); // el saludo del protocolo, no un 404 de Express
  }
  const salud = await fetch(`${url}/api/v1/salud`);
  assert.equal(salud.status, 200);
});

test('Express sigue respondiendo lo demas con su formato de error', async () => {
  const r = await fetch(`${url}/api/v1/no-existe`);
  assert.equal(r.status, 404);
  assert.equal((await r.json()).error.codigo, 'RUTA_NO_ENCONTRADA');
});

// --- quien puede entrar -------------------------------------------------------------------

for (const [nombre, token, codigo] of [
  ['sin token', undefined, 'TOKEN_AUSENTE'],
  ['con un token inventado', 'esto.no.es-un-token', 'TOKEN_INVALIDO'],
  ['con un token firmado por una clave ajena al realm', firmar(deCocina, { clave: ajena.privateKey }), 'TOKEN_INVALIDO'],
  ['con un token de otra aplicacion', firmar(deCocina, { audience: 'otra-aplicacion' }), 'TOKEN_INVALIDO'],
  ['con un token vencido', firmar({ ...deCocina, iat: Math.floor(Date.now() / 1000) - 7200 }, { expiresIn: '60m' }), 'TOKEN_EXPIRADO'],
  ['con un token valido pero sin los roles del sistema', firmar(sinRol), 'ROL_SIN_PERMISO'],
]) {
  test(`el canal rechaza una conexion ${nombre}: ${codigo}`, async () => {
    const { conectado, codigo: recibido } = await entrar(token);
    assert.equal(conectado, false);
    assert.equal(recibido, codigo);
  });
}

test('recepcion y cocina entran con su token', async () => {
  assert.equal((await entrar(firmar(deRecepcion))).conectado, true);
  assert.equal((await entrar(firmar(deCocina))).conectado, true);
});

// --- a quien le llega cada aviso -----------------------------------------------------------

test('un pedido nuevo le llega a cocina sin el celular, y a recepcion completo', async () => {
  const { socket: deCocinaSocket } = await entrar(firmar(deCocina));
  const { socket: deRecepcionSocket } = await entrar(firmar(deRecepcion));
  const enCocina = esperar(deCocinaSocket, 'pedido:nuevo');
  const enRecepcion = esperar(deRecepcionSocket, 'pedido:nuevo');
  canal.pedidoNuevo(PEDIDO);
  assert.deepEqual((await enCocina).cliente, { nombre: 'Ana Prueba' });
  assert.deepEqual((await enRecepcion).cliente, { nombre: 'Ana Prueba', celular: '70000001' });
});

test('una venta directa de bebidas no se avisa a nadie: nace entregada (D-38)', async () => {
  const { socket: deCocinaSocket } = await entrar(firmar(deCocina));
  const { socket: deRecepcionSocket } = await entrar(firmar(deRecepcion));
  const enCocina = esperar(deCocinaSocket, 'pedido:nuevo', 500);
  const enRecepcion = esperar(deRecepcionSocket, 'pedido:nuevo', 500);
  canal.pedidoNuevo({ ...PEDIDO, id: 43, estado: 'entregado', cliente: null, paraLlevar: null, numero: null });
  assert.equal(await enRecepcion, null);
  assert.equal(await enCocina, null);
});

test('lo agregado a un pedido en cocina les llega a los dos, a cocina sin el celular (D-37)', async () => {
  const { socket: deCocinaSocket } = await entrar(firmar(deCocina));
  const { socket: deRecepcionSocket } = await entrar(firmar(deRecepcion));
  const enCocina = esperar(deCocinaSocket, 'pedido:actualizado');
  const enRecepcion = esperar(deRecepcionSocket, 'pedido:actualizado');
  canal.pedidoActualizado({ ...PEDIDO, id: 45, estado: 'en_preparacion', version: 2 });
  const aCocina = await enCocina;
  assert.equal(aCocina.id, 45);
  assert.equal(aCocina.version, 2);
  assert.deepEqual(aCocina.cliente, { nombre: 'Ana Prueba' });
  assert.deepEqual((await enRecepcion).cliente, { nombre: 'Ana Prueba', celular: '70000001' });
});

test('lo agregado a un pedido listo le llega a recepcion y no a cocina, que ya no lo tiene', async () => {
  const { socket: deCocinaSocket } = await entrar(firmar(deCocina));
  const { socket: deRecepcionSocket } = await entrar(firmar(deRecepcion));
  const enCocina = esperar(deCocinaSocket, 'pedido:actualizado', 500);
  const enRecepcion = esperar(deRecepcionSocket, 'pedido:actualizado');
  canal.pedidoActualizado({ ...PEDIDO, id: 46, estado: 'listo' });
  assert.equal((await enRecepcion).id, 46);
  assert.equal(await enCocina, null);
});

test('un cambio de estado les llega a los dos roles, con desde, hacia y cuando', async () => {
  const { socket: deCocinaSocket } = await entrar(firmar(deCocina));
  const { socket: deRecepcionSocket } = await entrar(firmar(deRecepcion));
  const enCocina = esperar(deCocinaSocket, 'pedido:estado');
  const enRecepcion = esperar(deRecepcionSocket, 'pedido:estado');
  canal.estadoCambiado({ id: 42, anterior: 'en_preparacion', nuevo: 'listo' });
  for (const aviso of [await enCocina, await enRecepcion]) {
    assert.equal(aviso.id, 42);
    assert.equal(aviso.anterior, 'en_preparacion');
    assert.equal(aviso.nuevo, 'listo');
    assert.ok(!Number.isNaN(Date.parse(aviso.fechaHora)));
  }
});

test('el aviso llega en mucho menos de 2 segundos', async () => {
  const { socket } = await entrar(firmar(deCocina));
  const inicio = process.hrtime.bigint();
  const llegada = esperar(socket, 'pedido:nuevo');
  canal.pedidoNuevo({ ...PEDIDO, id: 44 });
  assert.equal((await llegada).id, 44);
  const ms = Number(process.hrtime.bigint() - inicio) / 1e6;
  assert.ok(ms < 2000, `tardo ${ms} ms`);
});
