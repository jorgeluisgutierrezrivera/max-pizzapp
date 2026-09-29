// Mide cuanto tarda una pantalla en darse cuenta de que el canal en vivo se corto (RNF-05:
// avisar en menos de 10 segundos). Dos modos:
//
//   MODO=corte (el de por defecto), contra la API LOCAL. Pone un "tapon" TCP entre el cliente
//   de Socket.IO y la API: deja pasar todo y, en un instante dado, deja de reenviar SIN
//   cerrar nada, que es lo que hace una red colgada. Ni la API ni el cliente reciben un
//   cierre: solo el latido puede notarlo (D-44). Mide desde ese instante hasta que el cliente
//   da la conexion por perdida. El corte cae en un momento al azar del ciclo del latido, asi
//   que las mediciones cubren del mejor al peor caso.
//
//   MODO=saludo, contra cualquier API, tambien la publica. Lee el latido que anuncia el
//   servidor en el saludo de Socket.IO: prueba que produccion corre con los valores medidos
//   en local. No necesita token.
//
// El cliente es el mismo tipo de cliente que la app: el de Flutter arma su temporizador con
// la misma regla, pingInterval + pingTimeout.
//
// No se corre solo: lo lanza medir_caida.py, que obtiene el token real de cocina en Keycloak
// y lo pasa por el entorno (TOKEN_COCINA). Nunca se imprime.
const net = require('node:net');
const path = require('node:path');
const { createRequire } = require('node:module');

const requerir = createRequire(path.join(__dirname, '..', '..', 'backend', 'package.json'));
const { io } = requerir('socket.io-client');

const API = process.env.API_URL;
const ORIGEN = new URL(API).origin;
const MODO = process.env.MODO || 'corte';
const VECES = Number(process.env.VECES || 10);
const LIMITE_MS = 10000;

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

async function leerSaludo() {
  const r = await fetch(`${ORIGEN}/socket.io/?EIO=4&transport=polling`);
  const texto = await r.text();
  if (!texto.startsWith('0{')) throw new Error(`el servidor no respondio el saludo de Socket.IO (${r.status})`);
  return JSON.parse(texto.slice(1));
}

async function modoSaludo() {
  const { pingInterval, pingTimeout } = await leerSaludo();
  const total = pingInterval + pingTimeout;
  console.log(`Canal: ${ORIGEN}`);
  console.log(`  latido cada ${pingInterval} ms, espera ${pingTimeout} ms: una red colgada se nota en ${total} ms como maximo`);
  console.log(total < LIMITE_MS ? `BAJO ${LIMITE_MS} ms` : `NO BAJA DE ${LIMITE_MS} ms`);
  return total < LIMITE_MS;
}

// El tapon: reenvia en los dos sentidos hasta que se congela. Congelado, tira lo que llega
// y tampoco pasa los cierres, como una red que dejo de responder sin avisar.
function crearTapon(destino) {
  const pares = new Set();
  const servidor = net.createServer((cliente) => {
    const api = net.connect(destino.port, destino.hostname);
    const par = { cliente, api, congelado: false };
    pares.add(par);
    const reenviar = (desde, hacia) => {
      desde.on('data', (datos) => { if (!par.congelado) hacia.write(datos); });
      desde.on('end', () => { if (!par.congelado) hacia.end(); });
      desde.on('error', () => {});
    };
    reenviar(cliente, api);
    reenviar(api, cliente);
    cliente.on('close', () => pares.delete(par));
  });
  return {
    escuchar: () => new Promise((listo) => servidor.listen(0, '127.0.0.1', () => listo(servidor.address().port))),
    congelar: () => { for (const par of pares) par.congelado = true; },
    soltar: () => { for (const par of pares) { par.cliente.destroy(); par.api.destroy(); } pares.clear(); },
    cerrar: () => servidor.close(),
  };
}

// Una medicion: conecta por el tapon, espera un latido, deja pasar un momento al azar dentro
// del ciclo y congela. Devuelve cuanto tardo el cliente en declarar la conexion perdida.
async function medirUnCorte(tapon, puerto, token, cicloMs) {
  const socket = io(`http://127.0.0.1:${puerto}`, {
    auth: { token }, transports: ['websocket'], reconnection: false,
  });
  try {
    await new Promise((listo, fallo) => {
      socket.on('connect', listo);
      socket.on('connect_error', (err) => fallo(new Error(`el canal rechazo la conexion: ${err.message}`)));
    });
    await new Promise((listo) => socket.io.engine.once('ping', listo));
    await esperar(Math.random() * cicloMs);
    const perdida = new Promise((listo) => socket.once('disconnect', (motivo) => listo({ motivo, fin: performance.now() })));
    const inicio = performance.now();
    tapon.congelar();
    const { motivo, fin } = await perdida;
    return { ms: fin - inicio, motivo };
  } finally {
    socket.close();
    tapon.soltar();
  }
}

async function modoCorte() {
  const destino = new URL(ORIGEN);
  if (destino.protocol !== 'http:') {
    throw new Error('el modo corte funciona contra la API local (http). Contra la publica, use MODO=saludo');
  }
  const { pingInterval, pingTimeout } = await leerSaludo();
  console.log(`Canal: ${ORIGEN} · latido cada ${pingInterval} ms, espera ${pingTimeout} ms`);

  const tapon = crearTapon(destino);
  const puerto = await tapon.escuchar();
  const tiempos = [];
  try {
    for (let i = 0; i < VECES; i += 1) {
      const { ms, motivo } = await medirUnCorte(tapon, puerto, process.env.TOKEN_COCINA, pingInterval);
      if (motivo !== 'ping timeout') throw new Error(`la conexion se cerro por "${motivo}", no por el latido`);
      tiempos.push(ms);
      console.log(`  corte ${String(i + 1).padStart(2)}: detectado a los ${(ms / 1000).toFixed(2)} s (${motivo})`);
    }
  } finally {
    tapon.cerrar();
  }

  const orden = [...tiempos].sort((a, b) => a - b);
  const s = (ms) => `${(ms / 1000).toFixed(2)} s`;
  console.log(`Del corte de la red a la conexion perdida: ${orden.length} mediciones · minimo ${s(orden[0])}`
    + ` · mediana ${s(orden[Math.floor(orden.length / 2)])} · maximo ${s(orden[orden.length - 1])}`);
  const bien = orden[orden.length - 1] < LIMITE_MS;
  console.log(bien ? `TODO BAJO ${LIMITE_MS / 1000} s` : `HAY MEDICIONES DE ${LIMITE_MS / 1000} s O MAS`);
  return bien;
}

(MODO === 'saludo' ? modoSaludo() : modoCorte())
  .then((bien) => process.exit(bien ? 0 : 1))
  .catch((err) => {
    console.error('La medicion fallo:', err.message);
    process.exit(1);
  });
