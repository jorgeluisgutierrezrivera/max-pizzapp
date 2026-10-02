// Pruebas del endurecimiento de la API (tarjeta 09, D-52):
//   - las cabeceras de seguridad en toda respuesta, tambien en los errores;
//   - el limite de peticiones por IP, con 429 en el formato unico, contando por la IP del
//     cliente detras de Caddy y antes de validar el token;
//   - los textos libres sin caracteres de control (el nulo hacia responder 500);
//   - el canal en vivo, que corta un mensaje mas grande que su limite.
// Lo que se ve desde afuera, contra produccion, queda en el plan de la tarjeta 09.
const test = require('node:test');
const assert = require('node:assert/strict');
const { io: conectar } = require('socket.io-client');
const { crearApp } = require('../src/app');
const { crearServidor } = require('../src/servidor');
const { limitePorMinuto } = require('../src/config');
const { leerVenta, VentaInvalida } = require('../src/precio');
const { TAMANO_MAXIMO_DE_MENSAJE } = require('../src/tiempo-real');
const { firmar, deRecepcion, deCocina, levantarEmisor, levantarApp } = require('./soporte/emisor');

let emisor;
test.before(async () => { emisor = await levantarEmisor(); });
test.after(() => emisor.cerrar());

// Una base que responde a la ruta de salud y falla ante cualquier otra consulta: las
// validaciones de esta prueba tienen que cortar ANTES de llegar a la base.
function baseQueNoSeToca() {
  const b = {
    consultas: [],
    query: async (sql) => {
      b.consultas.push(sql);
      if (sql === 'SELECT 1') return { rows: [{}] };
      throw new Error(`la validacion tenia que cortar antes de la base: ${sql.slice(0, 40)}`);
    },
  };
  return b;
}

async function conApp(opciones, prueba) {
  const pool = baseQueNoSeToca();
  const { base, cerrar } = await levantarApp(crearApp({ pool, autenticar: emisor.autenticar, ...opciones }));
  try {
    await prueba(base, pool);
  } finally {
    cerrar();
  }
}

// --- las cabeceras ----------------------------------------------------------------------

function comprobarCabeceras(r) {
  const h = r.headers;
  assert.equal(h.get('content-security-policy'), "default-src 'none';frame-ancestors 'none'");
  assert.equal(h.get('x-content-type-options'), 'nosniff');
  assert.equal(h.get('x-frame-options'), 'SAMEORIGIN');
  assert.equal(h.get('referrer-policy'), 'no-referrer');
  assert.equal(h.get('cross-origin-resource-policy'), 'same-origin');
  assert.equal(h.get('cross-origin-opener-policy'), 'same-origin');
  assert.equal(h.get('x-powered-by'), null, 'no anuncia la tecnologia del servidor');
  assert.equal(h.get('strict-transport-security'), null, 'HSTS lo pone Caddy, no la API');
}

test('las cabeceras de seguridad van en la ruta de salud, en un 401 y en un 404', async () => {
  await conApp({}, async (base) => {
    const salud = await fetch(`${base}/salud`);
    assert.equal(salud.status, 200);
    comprobarCabeceras(salud);

    const sinToken = await fetch(`${base}/pedidos`);
    assert.equal(sinToken.status, 401);
    comprobarCabeceras(sinToken);

    const noExiste = await fetch(`${base}/no-existe`);
    assert.equal(noExiste.status, 404);
    comprobarCabeceras(noExiste);
  });
});

// --- el limite de peticiones --------------------------------------------------------------

test('pasado el limite, 429 en el formato unico, con Retry-After y las cabeceras de seguridad', async () => {
  await conApp({ limitePorMinuto: 3 }, async (base) => {
    for (let i = 1; i <= 3; i += 1) {
      const r = await fetch(`${base}/salud`);
      assert.equal(r.status, 200, `la peticion ${i} entra`);
      assert.match(r.headers.get('ratelimit-policy'), /q=3/, 'anuncia el limite');
    }
    const r = await fetch(`${base}/salud`);
    assert.equal(r.status, 429);
    assert.deepEqual(await r.json(), {
      error: {
        codigo: 'DEMASIADAS_PETICIONES',
        mensaje: 'Demasiadas peticiones seguidas. Espera un momento e intenta de nuevo.',
      },
    });
    const espera = Number(r.headers.get('retry-after'));
    assert.ok(espera > 0 && espera <= 60, `Retry-After en segundos, dentro del minuto: ${espera}`);
    comprobarCabeceras(r);
  });
});

test('el limite cuenta por la IP del cliente que manda Caddy: otra IP sigue entrando', async () => {
  await conApp({ limitePorMinuto: 2 }, async (base) => {
    const desde = (ip) => fetch(`${base}/salud`, { headers: { 'x-forwarded-for': ip } });
    assert.equal((await desde('203.0.113.10')).status, 200);
    assert.equal((await desde('203.0.113.10')).status, 200);
    assert.equal((await desde('203.0.113.10')).status, 429, 'la tercera de la misma IP');
    assert.equal((await desde('203.0.113.20')).status, 200, 'otra IP no se suma a la primera');
  });
});

test('el limite corta antes de validar el token: una avalancha sin token recibe 429', async () => {
  await conApp({ limitePorMinuto: 2 }, async (base) => {
    assert.equal((await fetch(`${base}/pedidos`)).status, 401);
    assert.equal((await fetch(`${base}/pedidos`)).status, 401);
    const r = await fetch(`${base}/pedidos`);
    assert.equal(r.status, 429);
    assert.equal((await r.json()).error.codigo, 'DEMASIADAS_PETICIONES');
  });
});

test('el limite por defecto es 600 por minuto, y un valor invalido no deja arrancar', (t) => {
  const anterior = process.env.LIMITE_PETICIONES_POR_MINUTO;
  t.after(() => {
    if (anterior === undefined) delete process.env.LIMITE_PETICIONES_POR_MINUTO;
    else process.env.LIMITE_PETICIONES_POR_MINUTO = anterior;
  });
  delete process.env.LIMITE_PETICIONES_POR_MINUTO;
  assert.equal(limitePorMinuto(), 600);
  process.env.LIMITE_PETICIONES_POR_MINUTO = ' 1200 ';
  assert.equal(limitePorMinuto(), 1200);
  for (const malo of ['0', '-5', '1.5', 'muchas', '100001', '']) {
    process.env.LIMITE_PETICIONES_POR_MINUTO = malo;
    if (malo === '') {
      assert.equal(limitePorMinuto(), 600, 'vacio es como no ponerla');
    } else {
      assert.throws(() => limitePorMinuto(), /LIMITE_PETICIONES_POR_MINUTO/, `rechaza ${JSON.stringify(malo)}`);
    }
  }
});

// --- los caracteres de control ----------------------------------------------------------

const VENTA = {
  paraLlevar: true,
  cliente: { nombre: 'Ana Prueba', celular: '70000001' },
  observacion: 'sin cebolla',
  lineas: [{ productoId: 1, cantidad: 1 }],
  totalEsperado: 45,
};
const con = (cambios) => ({ ...VENTA, ...cambios });
const conNombre = (nombre) => con({ cliente: { ...VENTA.cliente, nombre } });

test('un nombre con caracteres de control se rechaza como venta invalida', () => {
  const malos = {
    'el nulo': 'Ana\u0000Prueba',
    'un tabulador': 'Ana\tPrueba',
    'un salto de linea': 'Ana\nPrueba',
    'un retorno': 'Ana\rPrueba',
    'el escape de las terminales': 'Ana\u001b[31mPrueba',
    'DEL': 'Ana\u007fPrueba',
    'un C1': 'Ana\u009bPrueba',
  };
  for (const [que, nombre] of Object.entries(malos)) {
    assert.throws(() => leerVenta(conNombre(nombre)),
      (e) => e instanceof VentaInvalida && e.message === 'El nombre tiene caracteres no validos.', que);
  }
});

test('los nombres con acentos, enie, emojis y espacios a los lados siguen entrando', () => {
  assert.equal(leerVenta(conNombre('José Ñandú')).cliente.nombre, 'José Ñandú');
  assert.equal(leerVenta(conNombre('Ana 🍕')).cliente.nombre, 'Ana 🍕');
  assert.equal(leerVenta(conNombre('  Ana Prueba\n')).cliente.nombre, 'Ana Prueba', 'se recortan al leer');
});

test('la observacion admite saltos de linea, pero no el resto de los caracteres de control', () => {
  assert.equal(leerVenta(con({ observacion: 'sin cebolla\nbien cocida' })).observacion, 'sin cebolla\nbien cocida');
  assert.equal(leerVenta(con({ observacion: 'sin cebolla\r\nbien cocida' })).observacion, 'sin cebolla\r\nbien cocida');
  for (const mala of ['sin\u0000cebolla', 'sin\tcebolla', 'sin\u001bcebolla', 'sin\u0085cebolla']) {
    assert.throws(() => leerVenta(con({ observacion: mala })),
      (e) => e instanceof VentaInvalida && e.message === 'La observacion tiene caracteres no validos.',
      JSON.stringify(mala));
  }
});

test('por la API: el nulo en el nombre o en la observacion responde 400, sin tocar la base', async () => {
  await conApp({}, async (base, pool) => {
    for (const venta of [conNombre('Ana\u0000Prueba'), con({ observacion: 'sin\u0000cebolla' })]) {
      const r = await fetch(`${base}/pedidos`, {
        method: 'POST',
        headers: { authorization: `Bearer ${firmar(deRecepcion)}`, 'content-type': 'application/json' },
        body: JSON.stringify(venta),
      });
      assert.equal(r.status, 400);
      assert.equal((await r.json()).error.codigo, 'VENTA_INVALIDA');
    }
    assert.deepEqual(pool.consultas, [], 'nada llego a la base');
  });
});

test('por la API: el motivo de una cancelacion con caracteres de control responde 400', async () => {
  await conApp({}, async (base, pool) => {
    for (const motivo of ['Se\u0000arrepintio', 'Se\narrepintio', 'Se\u001barrepintio']) {
      const r = await fetch(`${base}/pedidos/42/cancelacion`, {
        method: 'POST',
        headers: { authorization: `Bearer ${firmar(deRecepcion)}`, 'content-type': 'application/json' },
        body: JSON.stringify({ motivo }),
      });
      assert.equal(r.status, 400, JSON.stringify(motivo));
      assert.deepEqual(await r.json(), {
        error: { codigo: 'MOTIVO_INVALIDO', mensaje: 'El motivo tiene caracteres no validos.' },
      });
    }
    assert.deepEqual(pool.consultas, [], 'nada llego a la base');
  });
});

// --- el canal en vivo -------------------------------------------------------------------

test('el canal acepta el saludo con un token real y corta un mensaje mas grande que su limite', async (t) => {
  const pool = { query: async () => ({ rows: [] }) };
  const { servidor, canal } = crearServidor({ pool, autenticar: emisor.autenticar });
  await new Promise((listo) => servidor.listen(0, '127.0.0.1', listo));
  t.after(() => new Promise((listo) => canal.cerrar(listo)));

  const socket = conectar(`http://127.0.0.1:${servidor.address().port}`, {
    auth: { token: firmar(deCocina) }, transports: ['websocket'], reconnection: false,
  });
  t.after(() => socket.close());
  await new Promise((listo, fallo) => {
    socket.on('connect', listo);
    socket.on('connect_error', fallo);
  });

  // Uno chico no molesta: el canal no escucha nada de los clientes y lo ignora.
  socket.emit('algo', 'x'.repeat(1024));
  // Uno mas grande que el limite corta la conexion.
  const motivo = new Promise((listo) => socket.once('disconnect', listo));
  socket.emit('algo', 'x'.repeat(TAMANO_MAXIMO_DE_MENSAJE + 1024));
  const reloj = new Promise((listo) => setTimeout(() => listo('sigue conectado'), 2000));
  assert.match(await Promise.race([motivo, reloj]), /transport (close|error)/);
  assert.equal(TAMANO_MAXIMO_DE_MENSAJE, 16 * 1024);
});
