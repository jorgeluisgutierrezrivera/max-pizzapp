// Pruebas de POST /api/v1/pedidos: la aplicacion real con el emisor de tokens local y una
// base simulada que entiende la transaccion. Anota cada consulta, guarda lo que se inserta
// y lo devuelve al leer, asi se comprueba:
//   - QUE llega a la base: todo como parametro, nada pegado al texto SQL;
//   - el ORDEN de la transaccion: BEGIN, lecturas y escrituras, COMMIT;
//   - que un fallo a mitad de camino termina en ROLLBACK y no deja nada.
// Que las consultas funcionen contra el esquema real lo prueba pruebas/api/probar_pedidos.py.
const test = require('node:test');
const assert = require('node:assert/strict');
const { crearApp } = require('../src/app');
const { firmar, deRecepcion, deCocina, sinRol, levantarEmisor, levantarApp } = require('./soporte/emisor');

// La carta como la entrega pg: los numeric llegan como texto.
const CARTA = [
  { id: 1, nombre: 'Salame', categoria: 'pizza', precio: '45.00', disponible: true },
  { id: 2, nombre: 'Peperoni', categoria: 'pizza', precio: '50.00', disponible: true },
  { id: 5, nombre: 'Hawaiana', categoria: 'pizza', precio: '50.00', disponible: true },
  { id: 7, nombre: 'Napolitana', categoria: 'pizza', precio: '40.00', disponible: false },
  { id: 10, nombre: 'Gaseosa 2 L', categoria: 'bebida', precio: '18.00', disponible: true },
  { id: 20, nombre: 'Extra queso', categoria: 'extra', precio: '8.00', disponible: true },
];
const nombreDe = (id) => CARTA.find((p) => p.id === id);

// La hora que la base toma despues del bloqueo del numero del dia.
const AHORA = new Date('2026-09-24T19:00:00Z');

// Una base simulada. "fallarEn" hace fallar la primera consulta que coincida.
function baseSimulada({ fallarEn = null, errorDeConexion = null, rollbackFalla = false } = {}) {
  const b = { consultas: [], liberaciones: [], cliente: null, pedido: null, lineas: [] };
  let siguienteLinea = 100;

  function responder(sql, p = []) {
    const s = sql.trim();
    b.consultas.push({ sql: s, parametros: p });
    if (fallarEn && fallarEn.test(s)) {
      fallarEn = null;
      throw Object.assign(new Error('fallo simulado de la base'), { code: 'XX000' });
    }
    if (s === 'ROLLBACK' && rollbackFalla) throw Object.assign(new Error('conexion cortada'), { code: 'ECONNRESET' });
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(s)) return { rows: [] };
    if (/FROM producto/.test(s) && /FOR SHARE/.test(s)) {
      return { rows: CARTA.filter((r) => p[0].includes(r.id)) };
    }
    if (/pg_advisory_xact_lock/.test(s)) return { rows: [{}] };
    if (/^WITH ahora AS/.test(s)) return { rows: [{ creado_en: AHORA, numero: 12 }] };
    if (/^INSERT INTO cliente/.test(s)) {
      b.cliente = { id: 77, nombre: p[0], celular: p[1] === undefined ? null : p[1] };
      return { rows: [{ id: 77 }] };
    }
    if (/^INSERT INTO pedido/.test(s)) {
      b.pedido = { id: 42, parametros: p };
      return { rows: [{ id: 42 }] };
    }
    if (/^INSERT INTO detalle_pedido/.test(s)) {
      const id = siguienteLinea++;
      b.lineas.push({ id, parametros: p });
      return { rows: [{ id }] };
    }
    if (/^INSERT INTO historial_estado/.test(s)) return { rows: [] };
    if (/FROM pedido p/.test(s)) {
      const q = b.pedido.parametros;
      return {
        rows: [{
          id: 42, numero_del_dia: q[7], estado: q[3], para_llevar: q[6], observacion: q[4], total: q[5],
          creado_en: q[8] || new Date('2026-09-24T15:00:00Z'), creado_por_nombre: q[2], cliente_id: q[0],
          cliente_nombre: b.cliente && b.cliente.nombre, cliente_celular: b.cliente && b.cliente.celular,
        }],
      };
    }
    if (/FROM detalle_pedido d/.test(s)) {
      return {
        rows: b.lineas.map(({ id, parametros: q }) => ({
          id, pedido_id: q[0], linea_de_id: q[3], cantidad: q[4], precio_unitario: q[5], subtotal: q[6], agregado_en: null,
          producto_id: q[1], producto_nombre: nombreDe(q[1]).nombre, producto_categoria: nombreDe(q[1]).categoria,
          mitad_id: q[2], mitad_nombre: q[2] === null ? null : nombreDe(q[2]).nombre,
        })),
      };
    }
    throw new Error(`consulta no esperada en la prueba: ${s.slice(0, 60)}`);
  }

  b.pool = {
    query: async (sql, p) => responder(sql, p),
    connect: async () => {
      if (errorDeConexion) throw errorDeConexion;
      return { query: async (sql, p) => responder(sql, p), release: (descartar) => b.liberaciones.push(Boolean(descartar)) };
    },
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

// Levanta la app con una base simulada nueva, envia el cuerpo y devuelve la respuesta y la base.
async function enviar(cuerpo, { token = recepcion, base = baseSimulada(), crudo = false, avisos } = {}) {
  const api = await levantarApp(crearApp({ pool: base.pool, autenticar: emisor.autenticar, avisos }));
  try {
    const cabeceras = { 'content-type': 'application/json' };
    if (token) cabeceras.authorization = `Bearer ${token}`;
    const r = await fetch(`${api.base}/pedidos`, {
      method: 'POST', headers: cabeceras, body: crudo ? cuerpo : JSON.stringify(cuerpo),
    });
    return { estado: r.status, cuerpo: await r.json(), ubicacion: r.headers.get('location'), base };
  } finally {
    api.cerrar();
  }
}

// La venta de ejemplo: 2 mitad Salame / mitad Peperoni, 1 Hawaiana con extra queso y
// 2 gaseosas. 2 x 47,50 + 58 + 36 = Bs 189.
const VENTA = {
  paraLlevar: true,
  cliente: { nombre: 'Ana Prueba', celular: '70000001' },
  observacion: 'sin cebolla',
  lineas: [
    { productoId: 1, mitadId: 2, cantidad: 2 },
    { productoId: 5, cantidad: 1, extras: [20] },
    { productoId: 10, cantidad: 2 },
  ],
  totalEsperado: 189,
};

// --- acceso -----------------------------------------------------------------------------

test('crear pedido sin token: 401 y no se pide ni una conexion', async () => {
  const { estado, cuerpo, base } = await enviar(VENTA, { token: null });
  assert.equal(estado, 401);
  assert.equal(cuerpo.error.codigo, 'TOKEN_AUSENTE');
  assert.equal(base.consultas.length, 0);
});

test('cocina no puede crear pedidos: 403 y la base ni se toca', async () => {
  const { estado, cuerpo, base } = await enviar(VENTA, { token: cocina });
  assert.equal(estado, 403);
  assert.equal(cuerpo.error.codigo, 'ROL_SIN_PERMISO');
  assert.equal(base.consultas.length, 0);
});

test('un token sin los roles del sistema: 403', async () => {
  const { estado } = await enviar(VENTA, { token: firmar(sinRol) });
  assert.equal(estado, 403);
});

// --- entrada invalida -------------------------------------------------------------------

test('una venta mal armada: 400 VENTA_INVALIDA sin tocar la base', async () => {
  const { estado, cuerpo, base } = await enviar({ ...VENTA, cliente: { nombre: 'Ana', celular: '123' } });
  assert.equal(estado, 400);
  assert.equal(cuerpo.error.codigo, 'VENTA_INVALIDA');
  assert.match(cuerpo.error.mensaje, /8 digitos/);
  assert.equal(base.consultas.length, 0);
});

test('un cuerpo que no es JSON: 400 JSON_INVALIDO', async () => {
  const { estado, cuerpo } = await enviar('{"paraLlevar": tru', { crudo: true });
  assert.equal(estado, 400);
  assert.equal(cuerpo.error.codigo, 'JSON_INVALIDO');
});

// --- la venta valida --------------------------------------------------------------------

test('crear pedido: 201 con el pedido guardado y el precio del servidor', async () => {
  const { estado, cuerpo, ubicacion } = await enviar(VENTA);
  assert.equal(estado, 201);
  assert.equal(ubicacion, '/api/v1/pedidos/42');
  const { pedido } = cuerpo;
  assert.equal(pedido.id, 42);
  assert.equal(pedido.numero, 12);
  assert.equal(pedido.version, 4);
  assert.equal(pedido.estado, 'pendiente');
  assert.equal(pedido.paraLlevar, true);
  assert.equal(pedido.total, 189);
  assert.equal(pedido.observacion, 'sin cebolla');
  assert.equal(pedido.creadoPor, 'Recepcion de prueba');
  assert.deepEqual(pedido.cliente, { nombre: 'Ana Prueba', celular: '70000001' });
  assert.deepEqual(pedido.lineas.map((l) => [l.producto.nombre, l.mitad && l.mitad.nombre, l.cantidad, l.precioUnitario, l.subtotal]), [
    ['Salame', 'Peperoni', 2, 47.5, 95],
    ['Hawaiana', null, 1, 50, 50],
    ['Gaseosa 2 L', null, 2, 18, 36],
  ]);
  // El extra no es una linea suelta: viaja dentro de su pizza.
  assert.deepEqual(pedido.lineas[1].extras.map((e) => [e.producto.nombre, e.cantidad, e.precioUnitario, e.subtotal]), [
    ['Extra queso', 1, 8, 8],
  ]);
});

test('crear pedido: una sola transaccion, en orden, y la conexion se devuelve', async () => {
  const { base } = await enviar(VENTA);
  const textos = base.textos();
  const iBegin = textos.indexOf('BEGIN');
  const iCommit = textos.indexOf('COMMIT');
  assert.equal(iBegin, 0);
  assert.ok(iCommit > iBegin);
  assert.ok(!base.hubo(/^ROLLBACK/));
  // Todas las escrituras quedan dentro de la transaccion.
  textos.forEach((t, i) => { if (/^INSERT/.test(t)) assert.ok(i > iBegin && i < iCommit, t); });
  // Los productos se leen con FOR SHARE: nadie cambia un precio mientras se calcula.
  assert.ok(textos.some((t) => /FOR SHARE/.test(t)));
  assert.deepEqual(base.liberaciones, [false]);
});

test('el numero del dia: bloqueo, maximo mas uno y el pedido, en ese orden y dentro de la transaccion (D-35)', async () => {
  const { base } = await enviar(VENTA);
  const textos = base.textos();
  const iBloqueo = textos.findIndex((t) => /pg_advisory_xact_lock/.test(t));
  const iNumero = textos.findIndex((t) => /^WITH ahora AS/.test(t));
  const iPedido = textos.findIndex((t) => /^INSERT INTO pedido/.test(t));
  assert.ok(iBloqueo > textos.indexOf('BEGIN'));
  assert.ok(iBloqueo < iNumero && iNumero < iPedido && iPedido < textos.indexOf('COMMIT'));
  // Un bloqueo de TRANSACCION: se suelta solo con el COMMIT o el ROLLBACK, no hay que soltarlo a mano.
  assert.ok(!base.hubo(/pg_advisory_unlock/));
  // El dia se cuenta en la hora de Bolivia, desde la hora tomada despues del bloqueo.
  assert.match(textos[iNumero], /clock_timestamp\(\)/);
  assert.match(textos[iNumero], /America\/La_Paz/);
});

test('crear pedido: todo viaja como parametro, nada pegado al SQL', async () => {
  const { base } = await enviar(VENTA);
  for (const { sql } of base.consultas) {
    assert.ok(!/Ana Prueba|70000001|sin cebolla|47\.5/.test(sql), sql);
  }
  const pedido = base.consultas.find((c) => /^INSERT INTO pedido/.test(c.sql));
  assert.deepEqual(pedido.parametros, [
    77, '11111111-2222-3333-4444-555555555555', 'Recepcion de prueba', 'pendiente', 'sin cebolla', '189.00', true,
    12, AHORA,
  ]);
  const historial = base.consultas.find((c) => /^INSERT INTO historial_estado/.test(c.sql));
  assert.deepEqual(historial.parametros, [42, 'pendiente', '11111111-2222-3333-4444-555555555555', 'Recepcion de prueba']);
});

test('crear pedido: el extra se guarda colgado de la linea de su pizza, con su cantidad', async () => {
  const { base } = await enviar(VENTA);
  const [salame, hawaiana, extra, gaseosa] = base.lineas;
  assert.deepEqual(salame.parametros, [42, 1, 2, null, 2, '47.50', '95.00']);
  assert.deepEqual(hawaiana.parametros, [42, 5, null, null, 1, '50.00', '50.00']);
  assert.deepEqual(extra.parametros, [42, 20, null, hawaiana.id, 1, '8.00', '8.00']);
  assert.deepEqual(gaseosa.parametros, [42, 10, null, null, 2, '18.00', '36.00']);
});

test('con celular, el cliente se busca por su numero; sin celular, es uno nuevo', async () => {
  const conCelular = await enviar(VENTA);
  assert.ok(conCelular.base.hubo(/ON CONFLICT \(celular\)/));

  const sinCelular = await enviar({ ...VENTA, cliente: { nombre: 'Usuario Demo' } });
  assert.equal(sinCelular.estado, 201);
  assert.ok(!sinCelular.base.hubo(/ON CONFLICT/));
  assert.deepEqual(sinCelular.cuerpo.pedido.cliente, { nombre: 'Usuario Demo', celular: null });
});

test('solo bebidas a nombre de un cliente: 400, las bebidas solas son una venta directa (D-38)', async () => {
  const { estado, cuerpo, base } = await enviar({
    ...VENTA, lineas: [{ productoId: 10, cantidad: 2 }], totalEsperado: 36,
  });
  assert.equal(estado, 400);
  assert.match(cuerpo.error.mensaje, /venta directa/);
  assert.ok(!base.hubo(/^INSERT/));
});

const DIRECTA = { ventaDirecta: true, lineas: [{ productoId: 10, cantidad: 2 }], totalEsperado: 36 };

test('venta directa: 201, entregada, sin cliente, sin para llevar y sin numero del dia (D-38)', async () => {
  const { estado, cuerpo, base } = await enviar(DIRECTA);
  assert.equal(estado, 201);
  const { pedido } = cuerpo;
  assert.equal(pedido.estado, 'entregado');
  assert.equal(pedido.cliente, null);
  assert.equal(pedido.paraLlevar, null);
  assert.equal(pedido.numero, null);
  assert.equal(pedido.total, 36);
  // Ni cliente, ni bloqueo del numero: nadie la canta.
  assert.ok(!base.hubo(/^INSERT INTO cliente/));
  assert.ok(!base.hubo(/pg_advisory_xact_lock/));
  const insercion = base.consultas.find((c) => /^INSERT INTO pedido/.test(c.sql));
  assert.deepEqual(insercion.parametros, [
    null, '11111111-2222-3333-4444-555555555555', 'Recepcion de prueba', 'entregado', null, '36.00', null, null, null,
  ]);
  // Queda quien la vendio y cuando: nace entregada.
  const historial = base.consultas.find((c) => /^INSERT INTO historial_estado/.test(c.sql));
  assert.equal(historial.parametros[1], 'entregado');
});

test('venta directa con una pizza: 400, sin tocar la base mas alla de leer la carta', async () => {
  const { estado, cuerpo, base } = await enviar({
    ventaDirecta: true, lineas: [{ productoId: 2, cantidad: 1 }], totalEsperado: 50,
  });
  assert.equal(estado, 400);
  assert.match(cuerpo.error.mensaje, /solo de bebidas/);
  assert.ok(!base.hubo(/^INSERT/));
});

test('venta directa con el nombre del cliente: 400 sin tocar la base', async () => {
  const { estado, base } = await enviar({ ...DIRECTA, cliente: { nombre: 'Ana Prueba' } });
  assert.equal(estado, 400);
  assert.equal(base.consultas.length, 0);
});

// --- lo que se rechaza con la carta en la mano -------------------------------------------

test('el total no coincide: 409 PRECIO_CAMBIADO con el total correcto, y no se guarda nada', async () => {
  const { estado, cuerpo, base } = await enviar({ ...VENTA, totalEsperado: 180 });
  assert.equal(estado, 409);
  assert.equal(cuerpo.error.codigo, 'PRECIO_CAMBIADO');
  assert.equal(cuerpo.error.totalCorrecto, 189);
  assert.ok(base.hubo(/^ROLLBACK/));
  assert.ok(!base.hubo(/^INSERT/));
  assert.deepEqual(base.liberaciones, [false]);
});

test('un producto agotado: 409 PRODUCTO_NO_DISPONIBLE con su nombre, y no se guarda nada', async () => {
  const { estado, cuerpo, base } = await enviar({
    ...VENTA, lineas: [{ productoId: 7, cantidad: 1 }], totalEsperado: 40,
  });
  assert.equal(estado, 409);
  assert.equal(cuerpo.error.codigo, 'PRODUCTO_NO_DISPONIBLE');
  assert.match(cuerpo.error.mensaje, /Napolitana/);
  assert.deepEqual(cuerpo.error.producto, { id: 7, nombre: 'Napolitana' });
  assert.ok(base.hubo(/^ROLLBACK/));
  assert.ok(!base.hubo(/^INSERT/));
});

test('un producto que no existe: 400, y no se guarda nada', async () => {
  const { estado, cuerpo, base } = await enviar({
    ...VENTA, lineas: [{ productoId: 999, cantidad: 1 }], totalEsperado: 10,
  });
  assert.equal(estado, 400);
  assert.equal(cuerpo.error.codigo, 'VENTA_INVALIDA');
  assert.ok(!base.hubo(/^INSERT/));
});

// --- fallos a mitad de camino ------------------------------------------------------------

test('la base falla a mitad de la transaccion: ROLLBACK, 500 sin detalles, y nada a medias', async () => {
  const base = baseSimulada({ fallarEn: /^INSERT INTO detalle_pedido/ });
  const { estado, cuerpo } = await enviar(VENTA, { base });
  assert.equal(estado, 500);
  assert.equal(cuerpo.error.codigo, 'ERROR_INTERNO');
  assert.ok(!/fallo simulado/.test(cuerpo.error.mensaje));
  const textos = base.textos();
  assert.ok(textos.includes('ROLLBACK'));
  assert.ok(!textos.includes('COMMIT'));
  // Despues del fallo no se escribe nada mas.
  assert.equal(textos.slice(textos.findIndex((t) => /^INSERT INTO detalle_pedido/.test(t)) + 1).filter((t) => /^INSERT/.test(t)).length, 0);
  assert.deepEqual(base.liberaciones, [false]);
});

test('si tambien falla el ROLLBACK, la conexion se descarta en vez de volver al pool', async () => {
  const base = baseSimulada({ fallarEn: /^INSERT INTO pedido/, rollbackFalla: true });
  const { estado } = await enviar(VENTA, { base });
  assert.equal(estado, 500);
  assert.deepEqual(base.liberaciones, [true]);
});

// --- el aviso en vivo ---------------------------------------------------------------------

// Anota cada aviso y si, en ese momento, la base ya habia hecho el COMMIT.
function avisosQueAnotan(base) {
  const anotados = [];
  return {
    anotados,
    pedidoNuevo: (pedido) => anotados.push({ tipo: 'pedidoNuevo', pedido, despuesDelCommit: base.hubo(/^COMMIT$/) }),
    pedidoActualizado: (pedido) => anotados.push({ tipo: 'pedidoActualizado', pedido, despuesDelCommit: base.hubo(/^COMMIT$/) }),
    estadoCambiado: (aviso) => anotados.push({ tipo: 'estadoCambiado', aviso, despuesDelCommit: base.hubo(/^COMMIT$/) }),
  };
}

test('el aviso del pedido nuevo sale una vez, despues del COMMIT, con el pedido completo', async () => {
  const base = baseSimulada();
  const avisos = avisosQueAnotan(base);
  await enviar(VENTA, { base, avisos });
  assert.equal(avisos.anotados.length, 1);
  const [aviso] = avisos.anotados;
  assert.equal(aviso.tipo, 'pedidoNuevo');
  assert.equal(aviso.despuesDelCommit, true);
  assert.equal(aviso.pedido.id, 42);
  assert.equal(aviso.pedido.total, 189);
});

for (const [nombre, opciones, cuerpo] of [
  ['una venta mal armada', {}, { ...VENTA, lineas: [] }],
  ['un precio que cambio', {}, { ...VENTA, totalEsperado: 180 }],
  ['un fallo a mitad de la transaccion', { fallarEn: /^INSERT INTO detalle_pedido/ }, VENTA],
]) {
  test(`con ${nombre} no sale ningun aviso: nadie se entera de un pedido que no existe`, async () => {
    const base = baseSimulada(opciones);
    const avisos = avisosQueAnotan(base);
    await enviar(cuerpo, { base, avisos });
    assert.deepEqual(avisos.anotados, []);
  });
}

test('si el canal falla al avisar, el pedido igual queda guardado y respondido', async () => {
  const avisos = { pedidoNuevo: () => { throw new Error('canal caido'); }, estadoCambiado() {} };
  const { estado, cuerpo } = await enviar(VENTA, { avisos });
  assert.equal(estado, 201);
  assert.equal(cuerpo.pedido.id, 42);
});

test('la base no responde al conectar: 503 BASE_NO_DISPONIBLE', async () => {
  const base = baseSimulada({ errorDeConexion: Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' }) });
  const { estado, cuerpo } = await enviar(VENTA, { base });
  assert.equal(estado, 503);
  assert.equal(cuerpo.error.codigo, 'BASE_NO_DISPONIBLE');
});
