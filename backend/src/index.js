const { Pool } = require('pg');
const { cargarConfig } = require('./config');
const { crearAutenticador } = require('./autenticacion');
const { crearServidor } = require('./servidor');

const config = cargarConfig();

const pool = new Pool({ ...config.bd, max: 10, idleTimeoutMillis: 30000, connectionTimeoutMillis: 5000 });
// Un cliente inactivo que pierde la conexion emite "error"; sin este manejador, el proceso
// entero caeria por una desconexion que el pool ya sabe recuperar.
pool.on('error', (err) => console.error('[bd] error en un cliente inactivo:', err.message));

// La API y el canal en vivo, en el mismo servidor (ver servidor.js: el orden importa).
const { servidor, canal } = crearServidor({ pool, autenticar: crearAutenticador(config.identidad) });

servidor.listen(config.puerto, () => {
  console.log(`[api] escuchando en el puerto ${config.puerto}`);
  console.log(`[api] emisor esperado: ${config.identidad.emisor}`);
});

// Apagado ordenado: se deja de aceptar peticiones, se cierra el pool y recien entonces se
// sale. Sin esto, cada redespliegue deja conexiones colgando en PostgreSQL.
let apagando = false;
function apagar(senal) {
  if (apagando) return;
  apagando = true;
  console.log(`[api] ${senal} recibida: cerrando`);
  canal.cerrar(() => {
    pool.end().finally(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGTERM', () => apagar('SIGTERM'));
process.on('SIGINT', () => apagar('SIGINT'));
