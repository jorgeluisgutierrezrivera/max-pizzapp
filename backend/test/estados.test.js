// Pruebas de leer, avanzar y cancelar pedidos: la aplicacion real con el emisor de tokens
// local y una base simulada con pedidos en cada estado. La matriz completa de cambios de
// estado por rol se genera, no se escribe a mano: 5 estados de origen x 3 destinos x 2 roles,
// y la cancelacion desde los 5 estados con los 2 roles.
// La carrera entre dos cambios simultaneos se prueba contra la base real, que es la que
// toma el bloqueo (pruebas/api/probar_pedidos.py).
const test = require('node:test');
const assert = require('node:assert/strict');
const { crearApp } = require('../src/app');
const { firmar, deRecepcion, deCocina, sinRol, levantarEmisor, levantarApp } = require('./soporte/emisor');

const ESTADOS = ['pendiente', 'en_preparacion', 'listo', 'entregado', 'cancelado'];
const SUB = '11111111-2222-3333-4444-555555555555';

// Un pedido por estado: el #1 pendiente, el #2 en preparacion, y asi.
function pedidosIniciales() {
  return new Map(ESTADOS.map((estado, i) => [i + 1, { estado }]));
}

function baseSimulada({ pedidos = pedidosIniciales() } = {}) {
  const b = { consultas: [], historial: [], liberaciones: [], pedidos };

  function responder(sql, p = [], tx = null) {
    const s = sql.trim();
    b.consultas.push({ sql: s, parametros: p });
    if (s === 'BEGIN') { tx.cambios = []; return { rows: [] }; }
    if (s === 'COMMIT') {
      tx.cambios.forEach(([id, estado]) => { b.pedidos.get(id).estado = estado; });
      b.historial.push(...tx.historial);
      return { rows: [] };
    }
    if (s === 'ROLLBACK') return { rows: [] };
    if (/^SELECT estado FROM pedido WHERE id = \$1 FOR UPDATE$/.test(s)) {
      const pedido = b.pedidos.get(p[0]);
      return { rows: pedido ? [{ estado: pedido.estado }] : [] };
    }
    if (/^UPDATE pedido SET estado/.test(s)) { tx.cambios.push([p[0], p[1]]); return { rows: [] }; }
    if (/^INSERT INTO historial_estado/.test(s)) { tx.historial.push(p); return { rows: [] }; }
    if (/^SELECT id\s+FROM pedido/.test(s)) {
      return { rows: [...b.pedidos].filter(([, v]) => p[0].includes(v.estado)).map(([id]) => ({ id })) };
    }
    if (/FROM pedido p/.test(s)) {
      return {
        rows: p[0].filter((id) => b.pedidos.has(id)).map((id) => ({
          id, estado: b.pedidos.get(id).estado, para_llevar: true, observacion: null, total: '50.00',
          creado_en: new Date('2026-09-24T15:00:00Z'), creado_por_nombre: 'Recepcion de prueba',
          cliente_nombre: 'Ana Prueba', cliente_celular: '70000001',
        })),
      };
    }
    if (/FROM detalle_pedido d/.test(s)) {
      return {
        rows: p[0].map((id) => ({
          id: 100 + id, pedido_id: id, linea_de_id: null, cantidad: 1, precio_unitario: '50.00', subtotal: '50.00',
          producto_id: 2, producto_nombre: 'Peperoni', producto_categoria: 'pizza', mitad_id: null, mitad_nombre: null,
        })),
      };
    }
    if (/FROM historial_estado/.test(s)) {
      return {
        rows: [
          { estado: 'pendiente', usuario_nombre: 'Recepcion de prueba', fecha_hora: new Date('2026-09-24T15:00:00Z'), motivo: null },
          { estado: 'cancelado', usuario_nombre: 'Recepcion de prueba', fecha_hora: new Date('2026-09-24T15:05:00Z'), motivo: 'El cliente se fue' },
        ],
      };
    }
    throw new Error(`consulta no esperada en la prueba: ${s.slice(0, 60)}`);
  }

  b.pool = {
    query: async (sql, p) => responder(sql, p),
    connect: async () => {
      const tx = { cambios: [], historial: [] };
      return {
        query: async (sql, p) => responder(sql, p, tx),
        release: (descartar) => b.liberaciones.push(Boolean(descartar)),
      };
    },
  };
  b.hubo = (patron) => b.consultas.some((c) => patron.test(c.sql));
  return b;
}

let emisor;
const recepcion = firmar(deRecepcion);
const cocina = firmar(deCocina);
const TOKENS = { recepcion, cocina };

test.before(async () => { emisor = await levantarEmisor(); });
test.after(() => emisor.cerrar());

async function llamar(metodo, ruta, { token = recepcion, cuerpo, base = baseSimulada() } = {}) {
  const api = await levantarApp(crearApp({ pool: base.pool, autenticar: emisor.autenticar }));
  try {
    const cabeceras = { 'content-type': 'application/json' };
    if (token) cabeceras.authorization = `Bearer ${token}`;
    const r = await fetch(`${api.base}${ruta}`, {
      method: metodo, headers: cabeceras, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
    });
    return { estado: r.status, cuerpo: await r.json(), base };
  } finally {
    api.cerrar();
  }
}

// --- leer la cola -----------------------------------------------------------------------

test('la cola sin token: 401; con un token sin rol: 403', async () => {
  assert.equal((await llamar('GET', '/pedidos', { token: null })).estado, 401);
  assert.equal((await llamar('GET', '/pedidos', { token: firmar(sinRol) })).estado, 403);
});

test('la cola sin filtro trae los activos, en orden y con el celular para recepcion', async () => {
  const { estado, cuerpo, base } = await llamar('GET', '/pedidos');
  assert.equal(estado, 200);
  assert.deepEqual(cuerpo.pedidos.map((p) => [p.id, p.estado]), [[1, 'pendiente'], [2, 'en_preparacion'], [3, 'listo']]);
  const filtro = base.consultas.find((c) => /^SELECT id\s+FROM pedido/.test(c.sql));
  assert.deepEqual(filtro.parametros, [['pendiente', 'en_preparacion', 'listo']]);
  assert.equal(cuerpo.pedidos[0].cliente.celular, '70000001');
});

test('cocina pide su cola y no recibe el celular del cliente (D-31)', async () => {
  const { estado, cuerpo, base } = await llamar('GET', '/pedidos?estado=pendiente,en_preparacion', { token: cocina });
  assert.equal(estado, 200);
  assert.deepEqual(cuerpo.pedidos.map((p) => p.id), [1, 2]);
  const filtro = base.consultas.find((c) => /^SELECT id\s+FROM pedido/.test(c.sql));
  assert.deepEqual(filtro.parametros, [['pendiente', 'en_preparacion']]);
  for (const p of cuerpo.pedidos) assert.deepEqual(p.cliente, { nombre: 'Ana Prueba' });
});

test('una cola vacia responde una lista vacia sin leer lineas', async () => {
  const base = baseSimulada({ pedidos: new Map() });
  const { estado, cuerpo } = await llamar('GET', '/pedidos', { base });
  assert.equal(estado, 200);
  assert.deepEqual(cuerpo.pedidos, []);
  assert.ok(!base.hubo(/FROM detalle_pedido/));
});

for (const [nombre, consulta] of [
  ['un estado que no existe', '?estado=pagado'],
  ['un estado vacio en la lista', '?estado=pendiente,'],
  ['el estado repetido como parametro', '?estado=listo&estado=pendiente'],
  ['otro parametro', '?cliente=Ana'],
  ['un intento de inyeccion', "?estado=listo'%20OR%201=1--"],
]) {
  test(`la cola con ${nombre}: 400 FILTRO_INVALIDO sin tocar la base`, async () => {
    const { estado, cuerpo, base } = await llamar('GET', `/pedidos${consulta}`);
    assert.equal(estado, 400);
    assert.equal(cuerpo.error.codigo, 'FILTRO_INVALIDO');
    assert.equal(base.consultas.length, 0);
  });
}

// --- leer uno ----------------------------------------------------------------------------

test('un pedido con su historial, incluido el motivo de la cancelacion', async () => {
  const { estado, cuerpo } = await llamar('GET', '/pedidos/5');
  assert.equal(estado, 200);
  assert.equal(cuerpo.pedido.id, 5);
  assert.equal(cuerpo.pedido.lineas.length, 1);
  assert.deepEqual(cuerpo.pedido.historial.map((h) => [h.estado, h.usuario, h.motivo]), [
    ['pendiente', 'Recepcion de prueba', null],
    ['cancelado', 'Recepcion de prueba', 'El cliente se fue'],
  ]);
});

test('un pedido que no existe: 404', async () => {
  const { estado, cuerpo } = await llamar('GET', '/pedidos/999');
  assert.equal(estado, 404);
  assert.equal(cuerpo.error.codigo, 'PEDIDO_NO_ENCONTRADO');
});

for (const id of ['abc', '0', '-1', '1.5', '99999999999', '1e3']) {
  test(`el numero de pedido «${id}»: 400 ID_INVALIDO sin tocar la base`, async () => {
    const { estado, cuerpo, base } = await llamar('GET', `/pedidos/${id}`);
    assert.equal(estado, 400);
    assert.equal(cuerpo.error.codigo, 'ID_INVALIDO');
    assert.equal(base.consultas.length, 0);
  });
}

// --- la matriz de estados por rol ---------------------------------------------------------

// Lo que dice el plan (seccion 3.4): quien es dueno de cada destino y desde donde.
const DUENO = { en_preparacion: 'cocina', listo: 'cocina', entregado: 'recepcion' };
const DESDE = { en_preparacion: ['pendiente'], listo: ['en_preparacion'], entregado: ['listo'] };

for (const [i, actual] of ESTADOS.entries()) {
  const id = i + 1;
  for (const hacia of Object.keys(DUENO)) {
    for (const rol of ['recepcion', 'cocina']) {
      const esperado = rol !== DUENO[hacia] ? 403 : DESDE[hacia].includes(actual) ? 200 : 409;
      test(`matriz: ${rol} lleva un pedido ${actual} a ${hacia}: ${esperado}`, async () => {
        const { estado, cuerpo, base } = await llamar('PATCH', `/pedidos/${id}/estado`, {
          token: TOKENS[rol], cuerpo: { estado: hacia },
        });
        assert.equal(estado, esperado);
        if (esperado === 403) {
          assert.equal(cuerpo.error.codigo, 'ROL_SIN_PERMISO');
          assert.equal(base.consultas.length, 0); // el rol se decide sin tocar la base
        } else if (esperado === 409) {
          assert.equal(cuerpo.error.codigo, 'TRANSICION_NO_PERMITIDA');
          assert.equal(cuerpo.error.estadoActual, actual);
          assert.ok(base.hubo(/^ROLLBACK$/));
          assert.ok(!base.hubo(/^UPDATE/));
          assert.equal(base.pedidos.get(id).estado, actual);
        } else {
          assert.equal(cuerpo.pedido.estado, hacia);
          assert.equal(base.pedidos.get(id).estado, hacia);
          const nombre = rol === 'cocina' ? 'Cocina de prueba' : 'Recepcion de prueba';
          assert.deepEqual(base.historial, [[id, hacia, SUB, nombre, null]]);
        }
        assert.ok(base.liberaciones.every((d) => d === false));
      });
    }
  }
}

// --- la cancelacion ---------------------------------------------------------------------

for (const [i, actual] of ESTADOS.entries()) {
  const id = i + 1;
  const permitido = ['pendiente', 'en_preparacion'].includes(actual);

  test(`cancelar un pedido ${actual}: ${permitido ? '200 con el motivo en el historial' : '409'}`, async () => {
    const { estado, cuerpo, base } = await llamar('POST', `/pedidos/${id}/cancelacion`, {
      cuerpo: { motivo: '  El cliente se fue  ' },
    });
    if (permitido) {
      assert.equal(estado, 200);
      assert.equal(cuerpo.pedido.estado, 'cancelado');
      assert.deepEqual(base.historial, [[id, 'cancelado', SUB, 'Recepcion de prueba', 'El cliente se fue']]);
    } else {
      assert.equal(estado, 409);
      assert.equal(cuerpo.error.codigo, 'TRANSICION_NO_PERMITIDA');
      assert.equal(base.pedidos.get(id).estado, actual);
      assert.deepEqual(base.historial, []);
    }
  });

  test(`cocina no puede cancelar un pedido ${actual}: 403`, async () => {
    const { estado, base } = await llamar('POST', `/pedidos/${id}/cancelacion`, {
      token: cocina, cuerpo: { motivo: 'El cliente se fue' },
    });
    assert.equal(estado, 403);
    assert.equal(base.consultas.length, 0);
  });
}

for (const [nombre, cuerpo] of [
  ['sin motivo', {}],
  ['con el motivo en blanco', { motivo: '   ' }],
  ['con un motivo de 121 caracteres', { motivo: 'a'.repeat(121) }],
  ['con el motivo como numero', { motivo: 12 }],
]) {
  test(`cancelar ${nombre}: 400 MOTIVO_INVALIDO sin tocar la base`, async () => {
    const r = await llamar('POST', '/pedidos/1/cancelacion', { cuerpo });
    assert.equal(r.estado, 400);
    assert.equal(r.cuerpo.error.codigo, 'MOTIVO_INVALIDO');
    assert.equal(r.base.consultas.length, 0);
  });
}

test('cancelar un pedido que no existe: 404 y ROLLBACK', async () => {
  const { estado, cuerpo, base } = await llamar('POST', '/pedidos/999/cancelacion', { cuerpo: { motivo: 'x' } });
  assert.equal(estado, 404);
  assert.equal(cuerpo.error.codigo, 'PEDIDO_NO_ENCONTRADO');
  assert.ok(base.hubo(/^ROLLBACK$/));
});

// --- lo que el PATCH no acepta -----------------------------------------------------------

for (const [nombre, cuerpo, codigo] of [
  ['cancelado: la cancelacion lleva motivo y tiene su ruta', { estado: 'cancelado' }, 'ESTADO_INVALIDO'],
  ['pendiente: no se vuelve atras', { estado: 'pendiente' }, 'ESTADO_INVALIDO'],
  ['un estado inventado', { estado: 'pagado' }, 'ESTADO_INVALIDO'],
  ['un nombre heredado de los objetos', { estado: 'constructor' }, 'ESTADO_INVALIDO'],
  ['sin cuerpo', undefined, 'ESTADO_INVALIDO'],
]) {
  test(`PATCH con ${nombre}: 400 sin tocar la base`, async () => {
    const r = await llamar('PATCH', '/pedidos/1/estado', { token: cocina, cuerpo });
    assert.equal(r.estado, 400);
    assert.equal(r.cuerpo.error.codigo, codigo);
    assert.equal(r.base.consultas.length, 0);
  });
}

test('PATCH de un pedido que no existe: 404', async () => {
  const { estado } = await llamar('PATCH', '/pedidos/999/estado', { token: cocina, cuerpo: { estado: 'listo' } });
  assert.equal(estado, 404);
});

test('un cambio de estado: bloqueo, cambio e historial dentro de una transaccion', async () => {
  const { base } = await llamar('PATCH', '/pedidos/1/estado', { token: cocina, cuerpo: { estado: 'en_preparacion' } });
  const textos = base.consultas.map((c) => c.sql);
  const i = (patron) => textos.findIndex((t) => patron.test(t));
  assert.ok(i(/^BEGIN$/) < i(/FOR UPDATE$/));
  assert.ok(i(/FOR UPDATE$/) < i(/^UPDATE pedido/));
  assert.ok(i(/^UPDATE pedido/) < i(/^INSERT INTO historial_estado/));
  assert.ok(i(/^INSERT INTO historial_estado/) < i(/^COMMIT$/));
});
