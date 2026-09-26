// El contrato escrito (docs/api/openapi.yaml) y la API real no pueden separarse: cada ruta
// del contrato existe en el servidor, cada ruta del servidor esta en el contrato, y la unica
// publica es la que el contrato declara publica.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { crearApp } = require('../src/app');
const { levantarEmisor, levantarApp } = require('./soporte/emisor');

const CONTRATO = path.join(__dirname, '..', '..', 'docs', 'api', 'openapi.yaml');
const FUENTES = [
  path.join(__dirname, '..', 'src', 'app.js'),
  ...fs.readdirSync(path.join(__dirname, '..', 'src', 'rutas')).map((f) => path.join(__dirname, '..', 'src', 'rutas', f)),
];

// Las rutas del contrato, leidas del YAML sin librerias: la seccion "paths" tiene cada ruta
// con dos espacios de sangria y cada metodo con cuatro. "security: []" marca la publica.
function rutasDelContrato() {
  const lineas = fs.readFileSync(CONTRATO, 'utf8').split(/\r?\n/);
  const inicio = lineas.indexOf('paths:');
  const fin = lineas.indexOf('components:');
  const rutas = [];
  let rutaActual = null;
  for (const linea of lineas.slice(inicio + 1, fin)) {
    const ruta = linea.match(/^ {2}(\/\S*):$/);
    if (ruta) rutaActual = ruta[1];
    const metodo = linea.match(/^ {4}(get|post|put|patch|delete):$/);
    if (metodo) rutas.push({ metodo: metodo[1].toUpperCase(), ruta: rutaActual, publica: false });
    if (/^ {6}security: \[\]$/.test(linea)) rutas[rutas.length - 1].publica = true;
  }
  return rutas;
}

// Las rutas que el servidor monta, leidas de su codigo: api.get('/salud', ...),
// rutas.post('/pedidos/:id/lineas', ...).
function rutasDelServidor() {
  const rutas = [];
  for (const archivo of FUENTES) {
    const codigo = fs.readFileSync(archivo, 'utf8');
    for (const [, metodo, ruta] of codigo.matchAll(/\b(?:api|rutas)\.(get|post|put|patch|delete)\('([^']+)'/g)) {
      rutas.push(`${metodo.toUpperCase()} ${ruta.replace(/:(\w+)/g, '{$1}')}`);
    }
  }
  return rutas.sort();
}

let emisor;
let api;

test.before(async () => {
  emisor = await levantarEmisor();
  const pool = { query: async () => ({ rows: [{ '?column?': 1 }] }) };
  api = await levantarApp(crearApp({ pool, autenticar: emisor.autenticar }));
});

test.after(() => {
  emisor.cerrar();
  api.cerrar();
});

test('el contrato y el servidor tienen las mismas rutas', () => {
  const delContrato = rutasDelContrato().map((r) => `${r.metodo} ${r.ruta}`).sort();
  assert.ok(delContrato.length >= 9, `el contrato tiene ${delContrato.length} rutas`);
  assert.deepEqual(delContrato, rutasDelServidor());
});

test('solo la ruta de salud es publica, en el contrato y en el servidor', async () => {
  const rutas = rutasDelContrato();
  assert.deepEqual(rutas.filter((r) => r.publica).map((r) => r.ruta), ['/salud']);
  for (const { metodo, ruta, publica } of rutas) {
    const r = await fetch(`${api.base}${ruta.replace('{id}', '1')}`, {
      method: metodo,
      headers: { 'content-type': 'application/json' },
      body: metodo === 'GET' ? undefined : '{}',
    });
    const cuerpo = await r.json();
    if (publica) {
      assert.equal(r.status, 200, `${metodo} ${ruta}`);
    } else {
      // Existe (no es el 404 de ruta desconocida) y pide token antes que nada.
      assert.equal(r.status, 401, `${metodo} ${ruta}`);
      assert.equal(cuerpo.error.codigo, 'TOKEN_AUSENTE', `${metodo} ${ruta}`);
    }
  }
});
