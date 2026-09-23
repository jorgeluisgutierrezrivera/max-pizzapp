// Pruebas de integracion del acceso: la aplicacion real, con un emisor de tokens local.
// La prueba genera su propio par de claves RSA y publica un JWKS en un puerto local, asi
// puede fabricar los tokens que Keycloak no emite a voluntad: expirados, de otra
// audiencia, de otro emisor o firmados con una clave ajena.
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const { crearApp } = require('../src/app');
const { crearAutenticador } = require('../src/autenticacion');

const EMISOR = 'https://auth.ejemplo.test/realms/maxpizzapp';
const AUDIENCIA = 'backend-api';
const KID = 'clave-de-prueba';

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const ajena = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

function firmar(carga, { clave = privateKey, kid = KID, ...opciones } = {}) {
  return jwt.sign(carga, clave, {
    algorithm: 'RS256', keyid: kid, issuer: EMISOR, audience: AUDIENCIA,
    expiresIn: '60m', subject: '11111111-2222-3333-4444-555555555555', ...opciones,
  });
}

const deRecepcion = { name: 'Recepcion de prueba', preferred_username: 'recepcion.demo', realm_access: { roles: ['recepcion', 'default-roles-maxpizzapp'] } };
const deCocina = { name: 'Cocina de prueba', preferred_username: 'cocina.demo', realm_access: { roles: ['cocina'] } };

let jwksServidor;
let apiServidor;
let base;
let baseSinBd;
let apiSinBdServidor;

test.before(async () => {
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256', use: 'sig' };
  jwksServidor = http.createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ keys: [jwk] }));
  });
  await new Promise((r) => jwksServidor.listen(0, '127.0.0.1', r));

  const autenticar = crearAutenticador({
    emisor: EMISOR, audiencia: AUDIENCIA,
    jwksUri: `http://127.0.0.1:${jwksServidor.address().port}/certs`,
  });
  // Ruta que exige el rol de cocina: no existe todavia en el negocio (llega con la
  // tarjeta 06), asi que se monta solo aqui para probar el 403.
  const montarExtra = (api, { exigirRol }) => {
    api.get('/prueba/solo-cocina', autenticar, exigirRol('cocina'), (req, res) => res.json({ ok: true }));
  };

  const poolSano = { query: async () => ({ rows: [{ '?column?': 1 }] }) };
  const poolCaido = { query: async () => { throw new Error('connect ECONNREFUSED'); } };

  apiServidor = crearApp({ pool: poolSano, autenticar, montarExtra }).listen(0, '127.0.0.1');
  apiSinBdServidor = crearApp({ pool: poolCaido, autenticar }).listen(0, '127.0.0.1');
  await Promise.all([apiServidor, apiSinBdServidor].map((s) => new Promise((r) => s.on('listening', r))));
  base = `http://127.0.0.1:${apiServidor.address().port}/api/v1`;
  baseSinBd = `http://127.0.0.1:${apiSinBdServidor.address().port}/api/v1`;
});

test.after(() => {
  jwksServidor.close();
  apiServidor.close();
  apiSinBdServidor.close();
});

async function pedir(url, token) {
  const r = await fetch(url, { headers: token ? { authorization: `Bearer ${token}` } : {} });
  const cuerpo = await r.json();
  return { estado: r.status, cuerpo };
}

test('salud: 200 con la base respondiendo', async () => {
  const { estado, cuerpo } = await pedir(`${base}/salud`);
  assert.equal(estado, 200);
  assert.deepEqual(cuerpo, { estado: 'ok', baseDeDatos: 'ok' });
});

test('salud: 503 con la base caida, sin filtrar el detalle del error', async () => {
  const { estado, cuerpo } = await pedir(`${baseSinBd}/salud`);
  assert.equal(estado, 503);
  assert.equal(cuerpo.estado, 'degradado');
  assert.ok(!JSON.stringify(cuerpo).includes('ECONNREFUSED'));
});

test('sin token: 401 TOKEN_AUSENTE', async () => {
  const { estado, cuerpo } = await pedir(`${base}/sesion`);
  assert.equal(estado, 401);
  assert.equal(cuerpo.error.codigo, 'TOKEN_AUSENTE');
});

test('token con la firma manipulada: 401 TOKEN_INVALIDO', async () => {
  const token = firmar(deRecepcion);
  const [cab, carga, firma] = token.split('.');
  const alterada = firma.slice(0, -2) + (firma.endsWith('A') ? 'BB' : 'AA');
  const { estado, cuerpo } = await pedir(`${base}/sesion`, [cab, carga, alterada].join('.'));
  assert.equal(estado, 401);
  assert.equal(cuerpo.error.codigo, 'TOKEN_INVALIDO');
});

test('token firmado con una clave ajena al realm: 401', async () => {
  const { estado } = await pedir(`${base}/sesion`, firmar(deRecepcion, { clave: ajena.privateKey }));
  assert.equal(estado, 401);
});

test('token expirado: 401 TOKEN_EXPIRADO', async () => {
  const token = firmar({ ...deRecepcion, iat: Math.floor(Date.now() / 1000) - 7200 }, { expiresIn: '60m' });
  const { estado, cuerpo } = await pedir(`${base}/sesion`, token);
  assert.equal(estado, 401);
  assert.equal(cuerpo.error.codigo, 'TOKEN_EXPIRADO');
});

test('token de otra audiencia: 401', async () => {
  const { estado } = await pedir(`${base}/sesion`, firmar(deRecepcion, { audience: 'otra-aplicacion' }));
  assert.equal(estado, 401);
});

test('token de otro emisor (el riesgo D-09): 401', async () => {
  const { estado } = await pedir(`${base}/sesion`, firmar(deRecepcion, { issuer: 'http://keycloak:8080/realms/maxpizzapp' }));
  assert.equal(estado, 401);
});

test('token con algoritmo "none": 401', async () => {
  const sinFirma = jwt.sign({ ...deRecepcion, iss: EMISOR, aud: AUDIENCIA, sub: 'x' }, null, { algorithm: 'none' });
  const { estado } = await pedir(`${base}/sesion`, sinFirma);
  assert.equal(estado, 401);
});

test('token valido de recepcion en una ruta de cocina: 403 ROL_SIN_PERMISO', async () => {
  const { estado, cuerpo } = await pedir(`${base}/prueba/solo-cocina`, firmar(deRecepcion));
  assert.equal(estado, 403);
  assert.equal(cuerpo.error.codigo, 'ROL_SIN_PERMISO');
});

test('token valido sin ninguno de los dos roles del sistema: 403', async () => {
  const sinRol = { name: 'Nadie', realm_access: { roles: ['default-roles-maxpizzapp'] } };
  const { estado } = await pedir(`${base}/sesion`, firmar(sinRol));
  assert.equal(estado, 403);
});

test('token valido de cocina en su ruta: pasa', async () => {
  const { estado, cuerpo } = await pedir(`${base}/prueba/solo-cocina`, firmar(deCocina));
  assert.equal(estado, 200);
  assert.deepEqual(cuerpo, { ok: true });
});

test('sesion: el servidor sabe quien llama y solo informa los roles del sistema', async () => {
  const { estado, cuerpo } = await pedir(`${base}/sesion`, firmar(deRecepcion));
  assert.equal(estado, 200);
  assert.equal(cuerpo.nombre, 'Recepcion de prueba');
  assert.equal(cuerpo.usuario, 'recepcion.demo');
  assert.deepEqual(cuerpo.roles, ['recepcion']);
});

test('ruta inexistente: 404 con el formato unico de error', async () => {
  const { estado, cuerpo } = await pedir(`${base}/no-existe`);
  assert.equal(estado, 404);
  assert.deepEqual(Object.keys(cuerpo), ['error']);
  assert.equal(cuerpo.error.codigo, 'RUTA_NO_ENCONTRADA');
});

test('JSON mal formado: 400, no 500', async () => {
  const r = await fetch(`${base}/salud`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{roto' });
  assert.equal(r.status, 400);
  assert.equal((await r.json()).error.codigo, 'JSON_INVALIDO');
});

test('las respuestas no anuncian el servidor', async () => {
  const r = await fetch(`${base}/salud`);
  assert.equal(r.headers.get('x-powered-by'), null);
});
