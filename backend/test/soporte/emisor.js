// Un emisor de tokens local para las pruebas. Genera su propio par de claves RSA y publica
// un JWKS en un puerto local, asi las pruebas pueden fabricar los tokens que Keycloak no
// emite a voluntad: expirados, de otra audiencia, de otro emisor o firmados con una clave
// ajena. No es un archivo de pruebas: lo usan los que terminan en .test.js.
const http = require('node:http');
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const { crearAutenticador } = require('../../src/autenticacion');

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
const sinRol = { name: 'Nadie', realm_access: { roles: ['default-roles-maxpizzapp'] } };

function escuchar(servidor) {
  return new Promise((resolver) => servidor.listen(0, '127.0.0.1', () => resolver(servidor)));
}

// Publica el JWKS y devuelve el autenticador real de la API apuntando a el.
async function levantarEmisor() {
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256', use: 'sig' };
  const servidor = await escuchar(http.createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ keys: [jwk] }));
  }));
  const autenticar = crearAutenticador({
    emisor: EMISOR, audiencia: AUDIENCIA,
    jwksUri: `http://127.0.0.1:${servidor.address().port}/certs`,
  });
  return { autenticar, cerrar: () => servidor.close() };
}

// Pone una app de Express a escuchar en un puerto libre y devuelve la base de su API.
async function levantarApp(app) {
  const servidor = await escuchar(http.createServer(app));
  return { base: `http://127.0.0.1:${servidor.address().port}/api/v1`, cerrar: () => servidor.close() };
}

async function pedir(url, token) {
  const r = await fetch(url, { headers: token ? { authorization: `Bearer ${token}` } : {} });
  const cuerpo = await r.json();
  return { estado: r.status, cuerpo };
}

module.exports = {
  EMISOR, AUDIENCIA, firmar, ajena, deRecepcion, deCocina, sinRol,
  levantarEmisor, levantarApp, pedir,
};
