// Pruebas de POST /api/v1/pedidos/:id/lineas: agregar a un pedido ya enviado (D-37). La
// aplicacion real con el emisor de tokens local y una base simulada con un pedido en cada
// estado. La matriz de lo que se puede agregar se genera: 5 estados x (bebida, pizza).
// La carrera entre "Listo" y "Agregar" se prueba contra la base real, que es la que toma el
// bloqueo (pruebas/api/probar_pedidos.py).
const test = require('node:test');
const assert = require('node:assert/strict');
const { crearApp } = require('../src/app');
const { firmar, deRecepcion, deCocina, sinRol, levantarEmisor, levantarApp } = require('./soporte/emisor');

const ESTADOS = ['pendiente', 'en_preparacion', 'listo', 'entregado', 'cancelado'];
const SUB = '11111111-2222-3333-4444-555555555555';

const CARTA = [
  { id: 1, nombre: 'Salame', categoria: 'pizza', precio: '45.00', disponible: true },
  { id: 2, nombre: 'Peperoni', categoria: 'pizza', precio: '50.00', disponible: true },
  { id: 7, nombre: 'Napolitana', categoria: 'pizza', precio: '40.00', disponible: false },
  { id: 10, nombre: 'Gaseosa 2 L', categoria: 'bebida', precio: '18.00', disponible: true },
  { id: 20, nombre: 'Extra queso', categoria: 'extra', precio: '8.00', disponible: true },
];
const producto = (id) => CARTA.find((p) => p.id === id);

// Un pedido por estado: el #1 pendiente, el #2 en preparacion, y asi. Cada uno nacio con una
// Peperoni de Bs 50 (la linea 100 + id).
function baseSimulada({ fallarEn = null } = {}) {
  const b = { consultas: [], liberaciones: [], agregadas: [], totales: new Map() };
  let siguienteLinea = 500;

  function responder(sql, p = []) {
    const s = sql.trim();
    b.consultas.push({ sql: s, parametros: p });
    if (fallarEn && fallarEn.test(s)) {
      fallarEn = null;
      throw Object.assign(new Error('fallo simulado de la base'), { code: 'XX000' });
    }
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(s)) return { rows: [] };
    if (/^SELECT estado FROM pedido WHERE id = \$1 FOR UPDATE$/.test(s)) {
      const estado = ESTADOS[p[0] - 1];
      return { rows: estado ? [{ estado }] : [] };
    }
    if (/FROM producto/.test(s) && /FOR SHARE/.test(s)) {
      return { rows: CARTA.filter((r) => p[0].includes(r.id)) };
    }
    if (/^INSERT INTO detalle_pedido/.test(s)) {
      const id = siguienteLinea++;
      b.agregadas.push({ id, parametros: p });
      return { rows: [{ id }] };
    }
    if (/^UPDATE pedido SET total = total \+ \$2/.test(s)) {
      b.totales.set(p[0], p[1]);
      return { rows: [] };
    }
    if (/FROM pedido p/.test(s)) {
      return {
        rows: p[0].map((id) => ({
          id, numero_del_dia: 7, estado: ESTADOS[id - 1], para_llevar: false, observacion: null,
          total: String(50 + Number(b.totales.get(id) || 0)), creado_en: new Date('2026-09-24T15:00:00Z'),
          creado_por_nombre: 'Recepcion de prueba', cliente_id: 77, cliente_nombre: 'Ana Prueba', cliente_celular: '70000001',
        })),
      };
    }
    if (/FROM detalle_pedido d/.test(s)) {
      const original = {
        id: 100 + p[0][0], pedido_id: p[0][0], linea_de_id: null, cantidad: 1, precio_unitario: '50.00', subtotal: '50.00',
        agregado_en: null, producto_id: 2, producto_nombre: 'Peperoni', producto_categoria: 'pizza', mitad_id: null, mitad_nombre: null,
      };
      const agregadas = b.agregadas.map(({ id, parametros: q }) => ({
        id, pedido_id: q[0], linea_de_id: q[3], cantidad: q[4], precio_unitario: q[5], subtotal: q[6],
        agregado_en: new Date('2026-09-24T15:10:00Z'),
        producto_id: q[1], producto_nombre: producto(q[1]).nombre, producto_categoria: producto(q[1]).categoria,
        mitad_id: q[2], mitad_nombre: q[2] === null ? null : producto(q[2]).nombre,
      }));
      return { rows: [original, ...agregadas] };
    }
    throw new Error(`consulta no esperada en la prueba: ${s.slice(0, 60)}`);
  }

  b.pool = {
    query: async (sql, p) => responder(sql, p),
    connect: async () => ({
      query: async (sql, p) => responder(sql, p),
      release: (descartar) => b.liberaciones.push(Boolean(descartar)),
    }),
  };
  b.textos = () => b.consultas.map((c) => c.sql);
  b.hubo = (patron) => b.consultas.some((c) => patron.test(c.sql));
  return b;
}

let emisor;
const recepcion = firmar(deRecepcion);
const cocina = firmar(deCocina);

test.before(async () => { emisor = await levantarEmisor(); });
test.after(() => emisor.cerrar());

async function agregar(id, cuerpo, { token = recepcion, base = baseSimulada(), avisos } = {}) {
  const api = await levantarApp(crearApp({ pool: base.pool, autenticar: emisor.autenticar, avisos }));
  try {
    const cabeceras = { 'content-type': 'application/json' };
    if (token) cabeceras.authorization = `Bearer ${token}`;
    const r = await fetch(`${api.base}/pedidos/${id}/lineas`, {
      method: 'POST', headers: cabeceras, body: JSON.stringify(cuerpo),
    });
    return { estado: r.status, cuerpo: await r.json(), base };
  } finally {
    api.cerrar();
  }
}

const SODA = { lineas: [{ productoId: 10, cantidad: 1 }], totalEsperado: 18 };
const PIZZA = { lineas: [{ productoId: 1, mitadId: 2, cantidad: 1, extras: [20] }], totalEsperado: 55.5 };

// --- acceso -----------------------------------------------------------------------------

test('agregar sin token: 401; con un token sin rol: 403; y la base ni se toca', async () => {
  const sinToken = await agregar(1, SODA, { token: null });
  assert.equal(sinToken.estado, 401);
  assert.equal(sinToken.base.consultas.length, 0);
  const nadie = await agregar(1, SODA, { token: firmar(sinRol) });
  assert.equal(nadie.estado, 403);
});

test('cocina no puede agregar: 403 y la base ni se toca', async () => {
  const { estado, cuerpo, base } = await agregar(1, SODA, { token: cocina });
  assert.equal(estado, 403);
  assert.equal(cuerpo.error.codigo, 'ROL_SIN_PERMISO');
  assert.equal(base.consultas.length, 0);
});

// --- que se puede agregar segun el estado (la matriz de D-37) ------------------------------

const SE_PUEDE = {
  pendiente: { bebida: true, pizza: true },
  en_preparacion: { bebida: true, pizza: true },
  listo: { bebida: true, pizza: false },
  entregado: { bebida: false, pizza: false },
  cancelado: { bebida: false, pizza: false },
};

for (const [i, estadoDelPedido] of ESTADOS.entries()) {
  for (const [que, cuerpo] of [['bebida', SODA], ['pizza', PIZZA]]) {
    const permitido = SE_PUEDE[estadoDelPedido][que];
    test(`agregar una ${que} a un pedido ${estadoDelPedido}: ${permitido ? '200' : '409 AGREGADO_NO_PERMITIDO'}`, async () => {
      const { estado, cuerpo: respuesta, base } = await agregar(i + 1, cuerpo);
      if (permitido) {
        assert.equal(estado, 200);
        assert.ok(base.hubo(/^COMMIT$/));
        assert.equal(respuesta.pedido.version, que === 'pizza' ? 3 : 2);
      } else {
        assert.equal(estado, 409);
        assert.equal(respuesta.error.codigo, 'AGREGADO_NO_PERMITIDO');
        assert.equal(respuesta.error.estadoActual, estadoDelPedido);
        assert.ok(base.hubo(/^ROLLBACK$/));
        assert.ok(!base.hubo(/^INSERT/));
        assert.ok(!base.hubo(/^UPDATE/));
      }
      assert.deepEqual(base.liberaciones, [false]);
    });
  }
}

test('la pizza a un pedido listo dice que va en otro pedido, y que las bebidas si se pueden', async () => {
  const { cuerpo } = await agregar(3, PIZZA);
  assert.match(cuerpo.error.mensaje, /otro pedido/);
  assert.match(cuerpo.error.mensaje, /bebidas si/);
});

// --- lo que se guarda --------------------------------------------------------------------

test('agregar: bloqueo del pedido, carta, lineas y total, en ese orden y en una transaccion', async () => {
  const { base } = await agregar(2, PIZZA);
  const textos = base.textos();
  const i = (patron) => textos.findIndex((t) => patron.test(t));
  assert.equal(textos[0], 'BEGIN');
  assert.ok(i(/FOR UPDATE/) < i(/FOR SHARE/));
  assert.ok(i(/FOR SHARE/) < i(/^INSERT INTO detalle_pedido/));
  assert.ok(i(/^INSERT INTO detalle_pedido/) < i(/^UPDATE pedido SET total/));
  assert.ok(i(/^UPDATE pedido SET total/) < i(/^COMMIT$/));
});

test('agregar: cada linea guarda cuando y quien; el extra, colgado de su pizza; el total suma lo agregado', async () => {
  const { estado, cuerpo, base } = await agregar(2, PIZZA);
  assert.equal(estado, 200);
  const [pizza, extra] = base.agregadas;
  // pedido, producto, mitad, linea_de, cantidad, unitario, subtotal, quien (sub), quien (nombre)
  assert.deepEqual(pizza.parametros, [2, 1, 2, null, 1, '47.50', '47.50', SUB, 'Recepcion de prueba']);
  assert.deepEqual(extra.parametros, [2, 20, null, pizza.id, 1, '8.00', '8.00', SUB, 'Recepcion de prueba']);
  const insercion = base.consultas.find((c) => /^INSERT INTO detalle_pedido/.test(c.sql));
  assert.match(insercion.sql, /agregado_en/);
  assert.match(insercion.sql, /now\(\)/);
  const suma = base.consultas.find((c) => /^UPDATE pedido SET total/.test(c.sql));
  assert.deepEqual(suma.parametros, [2, '55.50']);
  // La respuesta es el pedido entero, con lo agregado marcado y el total nuevo.
  const { pedido } = cuerpo;
  assert.equal(pedido.total, 105.5);
  assert.equal(pedido.lineas[0].agregadoEn, null);
  assert.ok(pedido.lineas[1].agregadoEn);
  assert.equal(pedido.lineas[1].mitad.nombre, 'Peperoni');
  assert.equal(pedido.lineas[1].extras[0].producto.nombre, 'Extra queso');
});

test('agregar: todo viaja como parametro, nada pegado al SQL', async () => {
  const { base } = await agregar(1, PIZZA);
  for (const { sql } of base.consultas) assert.ok(!/47\.5|55\.5|Recepcion de prueba/.test(sql), sql);
});

// --- lo que se rechaza -------------------------------------------------------------------

test('el total no coincide: 409 PRECIO_CAMBIADO con lo que suma lo agregado, y no se guarda nada', async () => {
  const { estado, cuerpo, base } = await agregar(1, { ...SODA, totalEsperado: 15 });
  assert.equal(estado, 409);
  assert.equal(cuerpo.error.codigo, 'PRECIO_CAMBIADO');
  assert.equal(cuerpo.error.totalCorrecto, 18);
  assert.ok(!base.hubo(/^INSERT/));
  assert.ok(base.hubo(/^ROLLBACK$/));
});

test('un producto agotado: 409 PRODUCTO_NO_DISPONIBLE con cual es', async () => {
  const { estado, cuerpo, base } = await agregar(1, { lineas: [{ productoId: 7, cantidad: 1 }], totalEsperado: 40 });
  assert.equal(estado, 409);
  assert.equal(cuerpo.error.codigo, 'PRODUCTO_NO_DISPONIBLE');
  assert.deepEqual(cuerpo.error.producto, { id: 7, nombre: 'Napolitana' });
  assert.ok(!base.hubo(/^INSERT/));
});

test('un pedido que no existe: 404 y ROLLBACK', async () => {
  const { estado, cuerpo, base } = await agregar(99, SODA);
  assert.equal(estado, 404);
  assert.equal(cuerpo.error.codigo, 'PEDIDO_NO_ENCONTRADO');
  assert.ok(base.hubo(/^ROLLBACK$/));
});

for (const [nombre, cuerpo] of [
  ['sin lineas', { lineas: [], totalEsperado: 0 }],
  ['sin el total', { lineas: [{ productoId: 10, cantidad: 1 }] }],
  ['una cantidad de 1000', { lineas: [{ productoId: 10, cantidad: 1000 }], totalEsperado: 18000 }],
]) {
  test(`agregar ${nombre}: 400 VENTA_INVALIDA sin tocar la base`, async () => {
    const { estado, cuerpo: respuesta, base } = await agregar(1, cuerpo);
    assert.equal(estado, 400);
    assert.equal(respuesta.error.codigo, 'VENTA_INVALIDA');
    assert.equal(base.consultas.length, 0);
  });
}

test('un numero de pedido invalido: 400 ID_INVALIDO sin tocar la base', async () => {
  const { estado, cuerpo, base } = await agregar('abc', SODA);
  assert.equal(estado, 400);
  assert.equal(cuerpo.error.codigo, 'ID_INVALIDO');
  assert.equal(base.consultas.length, 0);
});

test('la base falla a mitad: ROLLBACK, 500 y el total no se toca', async () => {
  const base = baseSimulada({ fallarEn: /^INSERT INTO detalle_pedido/ });
  const { estado } = await agregar(1, SODA, { base });
  assert.equal(estado, 500);
  assert.ok(base.hubo(/^ROLLBACK$/));
  assert.ok(!base.hubo(/^UPDATE/));
  assert.ok(!base.hubo(/^COMMIT$/));
});

// --- el aviso en vivo ---------------------------------------------------------------------

function avisosQueAnotan(base) {
  const anotados = [];
  return {
    anotados,
    pedidoNuevo() {},
    estadoCambiado() {},
    pedidoActualizado: (pedido) => anotados.push({ pedido, despuesDelCommit: base.hubo(/^COMMIT$/) }),
  };
}

test('lo agregado se avisa una vez, despues del COMMIT, con el pedido completo', async () => {
  const base = baseSimulada();
  const avisos = avisosQueAnotan(base);
  await agregar(2, PIZZA, { base, avisos });
  assert.equal(avisos.anotados.length, 1);
  assert.equal(avisos.anotados[0].despuesDelCommit, true);
  assert.equal(avisos.anotados[0].pedido.id, 2);
  assert.equal(avisos.anotados[0].pedido.lineas.length, 2);
});

test('un agregado rechazado no avisa nada', async () => {
  const base = baseSimulada();
  const avisos = avisosQueAnotan(base);
  await agregar(4, SODA, { base, avisos });
  assert.deepEqual(avisos.anotados, []);
});
