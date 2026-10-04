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

// --- PATCH /productos/:id/disponibilidad (RF-13, D-66) ------------------------------
// La misma app con una base que responde al UPDATE como lo haria PostgreSQL: devuelve la fila
// con el valor nuevo y el que tenia antes, o nada si el producto no existe. Los avisos se
// anotan, para comprobar cuando se avisa y que lleva el aviso.

const HAWAIANA = { ...FILAS[0], disponible: true };

function baseDeLaCarta(fila = HAWAIANA) {
  return poolQueAnota(async (sql, [id, disponible]) => {
    if (fila === null || id !== fila.id) return { rows: [] };
    const actualizada = { ...fila, disponible, disponible_antes: fila.disponible };
    fila = { ...fila, disponible };
    return { rows: [actualizada] };
  });
}

async function conLaCarta(probar, fila) {
  const base = baseDeLaCarta(fila);
  const avisados = [];
  const avisos = { disponibilidadCambiada: (aviso) => avisados.push(aviso) };
  const otra = await levantarApp(crearApp({ pool: base, autenticar: emisor.autenticar, avisos }));
  try {
    return await probar({ base: otra.base, consultas: base.consultas, avisados });
  } finally {
    otra.cerrar();
  }
}

async function marcar(base, id, cuerpo, token, tipo = 'application/json') {
  const cabeceras = { 'content-type': tipo };
  if (token) cabeceras.authorization = `Bearer ${token}`;
  const r = await fetch(`${base}/productos/${id}/disponibilidad`, {
    method: 'PATCH', headers: cabeceras, body: typeof cuerpo === 'string' ? cuerpo : JSON.stringify(cuerpo),
  });
  return { estado: r.status, cuerpo: await r.json() };
}

test('disponibilidad sin token: 401 y la base ni se consulta', () => conLaCarta(async ({ base, consultas }) => {
  const { estado, cuerpo } = await marcar(base, 7, { disponible: false });
  assert.equal(estado, 401);
  assert.equal(cuerpo.error.codigo, 'TOKEN_AUSENTE');
  assert.equal(consultas.length, 0);
}));

test('disponibilidad con un token sin los roles del sistema: 403', () => conLaCarta(async ({ base, consultas }) => {
  const { estado, cuerpo } = await marcar(base, 7, { disponible: false }, firmar(sinRol));
  assert.equal(estado, 403);
  assert.equal(cuerpo.error.codigo, 'ROL_SIN_PERMISO');
  assert.equal(consultas.length, 0);
}));

for (const [rol, token] of [['recepcion', recepcion], ['cocina', cocina]]) {
  test(`${rol} marca un producto agotado: 200 con el producto, y avisa quien lo marco`, () => conLaCarta(async ({ base, consultas, avisados }) => {
    const { estado, cuerpo } = await marcar(base, 7, { disponible: false }, token);
    assert.equal(estado, 200);
    assert.deepEqual(cuerpo.producto, {
      id: 7, nombre: 'Hawaiana', categoria: 'pizza', precio: 50, descripcion: 'Doble queso, jamón y piña caramelizada',
      imagen: 'hawaiana.png', disponible: false, soloEntera: false,
    });
    assert.deepEqual(avisados, [{ id: 7, nombre: 'Hawaiana', categoria: 'pizza', disponible: false, por: rol }]);
    // Una sola consulta, parametrizada, que solo toca la carta: ningun pedido cambia (CA-13.2).
    assert.equal(consultas.length, 1);
    assert.deepEqual(consultas[0].parametros, [7, false]);
    assert.match(consultas[0].sql, /UPDATE producto/);
    assert.match(consultas[0].sql, /\$1/);
    assert.doesNotMatch(consultas[0].sql, /pedido/i);
  }));
}

test('reponer un agotado: 200, disponible otra vez, y avisa', () => conLaCarta(async ({ base, avisados }) => {
  const { estado, cuerpo } = await marcar(base, 7, { disponible: true }, cocina);
  assert.equal(estado, 200);
  assert.equal(cuerpo.producto.disponible, true);
  assert.equal(avisados.length, 1);
  assert.equal(avisados[0].disponible, true);
}, { ...HAWAIANA, disponible: false }));

test('marcar lo que ya estaba igual: 200 y no avisa (dos toques a la vez no repiten el aviso)', () => conLaCarta(async ({ base, avisados }) => {
  const primero = await marcar(base, 7, { disponible: false }, cocina);
  const segundo = await marcar(base, 7, { disponible: false }, recepcion);
  assert.equal(primero.estado, 200);
  assert.equal(segundo.estado, 200);
  assert.equal(segundo.cuerpo.producto.disponible, false);
  assert.equal(avisados.length, 1);
}));

test('un producto que no existe: 404 PRODUCTO_NO_ENCONTRADO, y no avisa', () => conLaCarta(async ({ base, avisados }) => {
  const { estado, cuerpo } = await marcar(base, 999, { disponible: false }, recepcion);
  assert.equal(estado, 404);
  assert.equal(cuerpo.error.codigo, 'PRODUCTO_NO_ENCONTRADO');
  assert.equal(avisados.length, 0);
}));

for (const id of ['abc', '0', '-3', '7.5', '99999999999', '2147483648']) {
  test(`numero de producto invalido (${id}): 400 ID_INVALIDO, sin tocar la base`, () => conLaCarta(async ({ base, consultas }) => {
    const { estado, cuerpo } = await marcar(base, id, { disponible: false }, recepcion);
    assert.equal(estado, 400);
    assert.equal(cuerpo.error.codigo, 'ID_INVALIDO');
    assert.equal(consultas.length, 0);
  }));
}

for (const [caso, cuerpoInvalido] of [
  ['vacio', {}],
  ['como texto', { disponible: 'false' }],
  ['nulo', { disponible: null }],
  ['como numero', { disponible: 0 }],
  ['con otro campo', { disponible: false, precio: 1 }],
  ['solo otro campo', { precio: 1 }],
  ['una lista', [false]],
]) {
  test(`cuerpo invalido (${caso}): 400 DISPONIBILIDAD_INVALIDA, sin tocar la base`, () => conLaCarta(async ({ base, consultas }) => {
    const { estado, cuerpo } = await marcar(base, 7, cuerpoInvalido, cocina);
    assert.equal(estado, 400);
    assert.equal(cuerpo.error.codigo, 'DISPONIBILIDAD_INVALIDA');
    assert.equal(consultas.length, 0);
  }));
}

test('cuerpo que no es JSON: 400, sin tocar la base', () => conLaCarta(async ({ base, consultas }) => {
  const { estado } = await marcar(base, 7, 'disponible=false', cocina, 'application/x-www-form-urlencoded');
  assert.equal(estado, 400);
  assert.equal(consultas.length, 0);
}));

test('un booleano suelto como cuerpo: 400 JSON_INVALIDO, lo rechaza el lector de JSON', () => conLaCarta(async ({ base, consultas }) => {
  const { estado, cuerpo } = await marcar(base, 7, 'false', cocina);
  assert.equal(estado, 400);
  assert.equal(cuerpo.error.codigo, 'JSON_INVALIDO');
  assert.equal(consultas.length, 0);
}));
