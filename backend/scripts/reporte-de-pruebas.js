// Corre la suite de la API y deja su reporte en el repositorio (tarjeta 10, D-57):
//   docs/pruebas/reportes/api.txt        para leer, con la fecha y el entorno al principio;
//   docs/pruebas/reportes/api-junit.xml  para las herramientas de integracion continua.
// Es la misma suite que `npm test`: no necesita base, Keycloak ni ningun .env.
//
// Uso, desde backend/:
//   npm run test:reporte
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const BACKEND = path.join(__dirname, '..');
const RAIZ = path.join(BACKEND, '..');
const REPORTES = path.join(RAIZ, 'docs', 'pruebas', 'reportes');

// Las rutas, relativas a la raiz del repositorio: la absoluta depende de la maquina en que
// se corrio. Aparecen en las trazas que imprimen a proposito las pruebas que provocan un
// error, y en el atributo "file" de cada caso del JUnit.
function relativas(texto) {
  const posix = RAIZ.split(path.sep).join('/');
  for (const prefijo of [`file:///${posix}/`, `${RAIZ}${path.sep}`, `${posix}/`]) {
    texto = texto.split(prefijo).join('');
  }
  return texto;
}
const TEXTO = path.join(REPORTES, 'api.txt');
const JUNIT = path.join(REPORTES, 'api-junit.xml');

fs.mkdirSync(REPORTES, { recursive: true });
const inicio = new Date();
const corrida = spawnSync(process.execPath, [
  '--test',
  '--test-reporter=spec', '--test-reporter-destination=stdout',
  '--test-reporter=junit', `--test-reporter-destination=${JUNIT}`,
  'test/*.test.js',
], { cwd: BACKEND, encoding: 'utf8', env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' } });

// El reporter "spec" pinta colores cuando cree que escribe en una terminal: en el archivo,
// sin los codigos de color.
const salida = relativas((corrida.stdout || '').replace(/\u001b\[[0-9;]*m/g, ''));
process.stdout.write(salida);
if (fs.existsSync(JUNIT)) fs.writeFileSync(JUNIT, relativas(fs.readFileSync(JUNIT, 'utf8')));
if (corrida.stderr) process.stderr.write(corrida.stderr);

const { version } = require(path.join(BACKEND, 'package.json'));
const cabecera = [
  'Max Pizzapp - reporte de la suite de la API',
  `Fecha:   ${inicio.toISOString()} (duro ${((Date.now() - inicio) / 1000).toFixed(1)} s)`,
  `Version: maxpizzapp-backend ${version}, Node ${process.version}, ${os.type()} ${os.release()}`,
  'Comando: cd backend && npm ci && npm test   (este reporte: npm run test:reporte)',
  'Sin base de datos ni Keycloak reales: la base es simulada y los tokens, de un emisor local.',
  `Resultado: ${corrida.status === 0 ? 'TODO EN VERDE' : 'CON FALLAS'}`,
  ''.padEnd(78, '-'),
  '',
].join('\n');
fs.writeFileSync(TEXTO, cabecera + salida);
console.log(`\nReportes: ${path.relative(process.cwd(), TEXTO)} y ${path.relative(process.cwd(), JUNIT)}`);
process.exit(corrida.status === null ? 1 : corrida.status);
