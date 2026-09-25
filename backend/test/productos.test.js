// Pruebas de GET /api/v1/productos: la aplicacion real con el emisor de tokens local y una
// base simulada que anota cada consulta. Asi se comprueba no solo la respuesta, sino QUE
// llega a la base: los filtros viajan como parametros y un filtro invalido no llega nunca.
// Que la consulta funcione contra el esquema real lo prueba pruebas/api/probar_carta.py.
const test = require('node:test');
const assert = require('node:assert/strict');
const { crearApp } = require('../src/app');
const {
  firmar, deRecepcion, deCocina, sinRol, levantarEmisor, levantarApp, pedir,
} = require('./soporte/emisor');

// Filas tal como las entrega pg: los numeric llegan como texto.
const FILAS = [
  { id: 7, nombre: 'Hawaiana', categoria: 'pizza', precio: '50.00', descripcion: 'Doble queso, jamón y piña caramelizada', imagen: 'hawaiana.png', disponible: false, solo_entera: false },
  { id: 3, nombre: 'Peperoni', categoria: 'pizza', precio: '50.00', descripcion: 'Doble queso, jamón y peperoni', imagen: 'peperoni.png', disponible: true, solo_entera: false },
  { id: 4, nombre: 'Tres estaciones', categoria: 'pizza', precio: '50.00', descripcion: 'Doble queso, peperoni, salame y choclo', imagen: 'tres-estaciones.webp', disponible: true, solo_entera: true },
  { id: 10, nombre: 'Gaseosa 2 L', categoria: 'bebida', precio: '18.00', descripcion: null, imagen: 'gaseosa.png', disponible: true, solo_entera: false },
  { id: 20, nombre: 'Extra queso', categoria: 'extra', precio: '8.00', descripcion: null, imagen: null, disponible: true, solo_entera: false },
];

function poolQueAnota(responder = async () => ({ rows: FILAS })) {
  const consultas = [];
  return {
    consultas,
    query: async (sql, parametros) => {
      consultas.push({ sql, parametros });
      return responder(sql, parametros);
    },
  };
}

let emisor;
let api;
let pool;
const recepcion = firmar(deRecepcion);
const cocina = firmar(deCocina);

test.before(async () => {
  emisor = await levantarEmisor();
  pool = poolQueAnota();
  api = await levantarApp(crearApp({ pool, autenticar: emisor.autenticar }));
});

test.after(() => {
  emisor.cerrar();
  api.cerrar();
});

test.beforeEach(() => { pool.consultas.length = 0; });

async function conPoolQueFalla(error) {
  const otra = await levantarApp(crearApp({
    pool: poolQueAnota(async () => { throw error; }),
    autenticar: emisor.autenticar,
  }));
  try {
    return await pedir(`${otra.base}/productos`, recepcion);
  } finally {
    otra.cerrar();
  }
}

// --- acceso -----------------------------------------------------------------

test('productos sin token: 401 y la base ni se consulta', async () => {
  const { estado, cuerpo } = await pedir(`${api.base}/productos`);
  assert.equal(estado, 401);
  assert.equal(cuerpo.error.codigo, 'TOKEN_AUSENTE');
  assert.equal(pool.consultas.length, 0);
});

test('productos con un token sin los roles del sistema: 403', async () => {
  const { estado, cuerpo } = await pedir(`${api.base}/productos`, firmar(sinRol));
  assert.equal(estado, 403);
  assert.equal(cuerpo.error.codigo, 'ROL_SIN_PERMISO');
  assert.equal(pool.consultas.length, 0);
});

test('productos: recepcion y cocina pueden leer la carta', async () => {
  for (const token of [recepcion, cocina]) {
    const { estado } = await pedir(`${api.base}/productos`, token);
    assert.equal(estado, 200);
  }
});

// --- el listado --------------------------------------------------------------

test('productos: la carta completa, con precios numericos, agotados incluidos y las pizzas solo enteras marcadas (D-39)', async () => {
  const { estado, cuerpo } = await pedir(`${api.base}/productos`, recepcion);
  assert.equal(estado, 200);
  assert.deepEqual(cuerpo, {
    productos: [
      { id: 7, nombre: 'Hawaiana', categoria: 'pizza', precio: 50, descripcion: 'Doble queso, jamón y piña caramelizada', imagen: 'hawaiana.png', disponible: false, soloEntera: false },
      { id: 3, nombre: 'Peperoni', categoria: 'pizza', precio: 50, descripcion: 'Doble queso, jamón y peperoni', imagen: 'peperoni.png', disponible: true, soloEntera: false },
      { id: 4, nombre: 'Tres estaciones', categoria: 'pizza', precio: 50, descripcion: 'Doble queso, peperoni, salame y choclo', imagen: 'tres-estaciones.webp', disponible: true, soloEntera: true },
      { id: 10, nombre: 'Gaseosa 2 L', categoria: 'bebida', precio: 18, descripcion: null, imagen: 'gaseosa.png', disponible: true, soloEntera: false },
      { id: 20, nombre: 'Extra queso', categoria: 'extra', precio: 8, descripcion: null, imagen: null, disponible: true, soloEntera: false },
    ],
  });
});

test('productos: sin filtros, los dos parametros llegan como NULL', async () => {
  await pedir(`${api.base}/productos`, recepcion);
  assert.equal(pool.consultas.length, 1);
  assert.deepEqual(pool.consultas[0].parametros, [null, null]);
});

test('productos: una carta vacia es una lista vacia, no un error', async () => {
  const vacia = await levantarApp(crearApp({
    pool: poolQueAnota(async () => ({ rows: [] })), autenticar: emisor.autenticar,
  }));
  try {
    const { estado, cuerpo } = await pedir(`${vacia.base}/productos`, recepcion);
    assert.equal(estado, 200);
    assert.deepEqual(cuerpo, { productos: [] });
  } finally {
    vacia.cerrar();
  }
});

// --- los filtros ---------------------------------------------------------------

test('filtro categoria: llega como parametro, nunca dentro del texto SQL', async () => {
  await pedir(`${api.base}/productos?categoria=pizza`, recepcion);
  const [{ sql, parametros }] = pool.consultas;
  assert.deepEqual(parametros, ['pizza', null]);
  assert.ok(!sql.includes('pizza'));
});

test('filtro disponible: el texto se convierte en booleano', async () => {
  await pedir(`${api.base}/productos?disponible=false`, cocina);
  await pedir(`${api.base}/productos?disponible=true`, cocina);
  assert.deepEqual(pool.consultas.map((c) => c.parametros), [[null, false], [null, true]]);
});

test('filtro categoria=extra: los extras se piden como cualquier categoria', async () => {
  const { estado } = await pedir(`${api.base}/productos?categoria=extra`, recepcion);
  assert.equal(estado, 200);
  assert.deepEqual(pool.consultas[0].parametros, ['extra', null]);
});

test('la respuesta no trae gama ni precio de media: solo pizzas enteras (D-27)', async () => {
  const { cuerpo } = await pedir(`${api.base}/productos`, recepcion);
  for (const producto of cuerpo.productos) {
    assert.ok(!('gama' in producto) && !('precioMedia' in producto));
  }
});

test('los dos filtros juntos', async () => {
  await pedir(`${api.base}/productos?categoria=bebida&disponible=true`, recepcion);
  assert.deepEqual(pool.consultas[0].parametros, ['bebida', true]);
});

test('la consulta es siempre la misma, con o sin filtros', async () => {
  await pedir(`${api.base}/productos`, recepcion);
  await pedir(`${api.base}/productos?categoria=postre&disponible=false`, recepcion);
  assert.equal(pool.consultas[0].sql, pool.consultas[1].sql);
});

// --- filtros invalidos: 400 y la base no se toca ----------------------------------

const INVALIDOS = [
  ['una categoria que no existe', 'categoria=pasta'],
  ['una categoria con mayusculas', 'categoria=Pizza'],
  ['un intento de inyeccion', `categoria=${encodeURIComponent("pizza' OR 1=1 --")}`],
  ['la categoria repetida', 'categoria=pizza&categoria=bebida'],
  ['la categoria vacia', 'categoria='],
  ['disponible con otro valor', 'disponible=si'],
  ['disponible como numero', 'disponible=1'],
  ['un filtro desconocido', 'orden=precio'],
  ['un filtro con corchetes', 'categoria[]=pizza'],
];

for (const [descripcion, consulta] of INVALIDOS) {
  test(`filtro invalido (${descripcion}): 400 FILTRO_INVALIDO`, async () => {
    const { estado, cuerpo } = await pedir(`${api.base}/productos?${consulta}`, recepcion);
    assert.equal(estado, 400);
    assert.equal(cuerpo.error.codigo, 'FILTRO_INVALIDO');
    assert.equal(pool.consultas.length, 0);
  });
}

test('un filtro invalido sin token sigue siendo 401: primero se sabe quien llama', async () => {
  const { estado } = await pedir(`${api.base}/productos?categoria=pasta`);
  assert.equal(estado, 401);
});

// --- la base -----------------------------------------------------------------------

test('base caida: 503 BASE_NO_DISPONIBLE, sin filtrar el detalle', async () => {
  const caida = Object.assign(new Error('connect ECONNREFUSED 172.18.0.2:5432'), { code: 'ECONNREFUSED' });
  const { estado, cuerpo } = await conPoolQueFalla(caida);
  assert.equal(estado, 503);
  assert.equal(cuerpo.error.codigo, 'BASE_NO_DISPONIBLE');
  assert.ok(!JSON.stringify(cuerpo).includes('172.18'));
});

test('base sin conexiones libres (espera agotada del pool): 503', async () => {
  const { estado } = await conPoolQueFalla(new Error('timeout exceeded when trying to connect'));
  assert.equal(estado, 503);
});

test('base reiniciandose (57P03): 503', async () => {
  const { estado } = await conPoolQueFalla(Object.assign(new Error('the database system is starting up'), { code: '57P03' }));
  assert.equal(estado, 503);
});

test('un error de SQL es un fallo nuestro: 500, sin el texto del error', async () => {
  const { estado, cuerpo } = await conPoolQueFalla(Object.assign(new Error('syntax error at or near "FORM"'), { code: '42601' }));
  assert.equal(estado, 500);
  assert.equal(cuerpo.error.codigo, 'ERROR_INTERNO');
  assert.ok(!JSON.stringify(cuerpo).includes('FORM'));
});
