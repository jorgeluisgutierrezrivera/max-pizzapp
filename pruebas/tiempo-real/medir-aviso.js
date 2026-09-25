// Mide el tiempo real de punta a punta, contra la API y el canal de verdad:
//
//   1. Pedido nuevo: desde que recepcion envia la venta hasta que la pantalla de cocina
//      recibe el aviso. Es el "menos de 2 segundos" que exige el E2 (RF-06).
//   2. Cambio de estado: desde que cocina marca el pedido hasta que recepcion recibe el
//      aviso (RF-03).
//   3. Lo agregado: desde que recepcion le agrega una pizza al pedido que cocina ya esta
//      preparando hasta que cocina recibe el pedido con la pizza nueva (D-37, RF-14). Las
//      pruebas del backend avisaban directo al canal y no vieron que este aviso no salia.
//
// No se corre solo: lo lanza medir_aviso.py, que obtiene los tokens reales de Keycloak y
// los pasa por el entorno (TOKEN_RECEPCION, TOKEN_COCINA). Nunca se imprimen.
// Cada pedido que crea lo cancela al terminar: no deja nada en la cola de cocina.
//
// Usa el cliente de Socket.IO que el backend ya tiene como dependencia de desarrollo, en la
// misma version que el servidor, para no mantener otro package.json.
const path = require('node:path');
const { createRequire } = require('node:module');

const requerir = createRequire(path.join(__dirname, '..', '..', 'backend', 'package.json'));
const { io } = requerir('socket.io-client');

const API = process.env.API_URL;
const ORIGEN = new URL(API).origin;
const VECES = Number(process.env.VECES || 10);
const LIMITE_MS = 2000;

async function llamar(metodo, ruta, token, cuerpo) {
  const r = await fetch(API + ruta, {
    method: metodo,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  return { estado: r.status, cuerpo: await r.json() };
}

// Conecta con el token y anota la hora de llegada de cada aviso, por pedido.
function conectar(token, evento, clave) {
  const llegadas = new Map();
  const socket = io(ORIGEN, { auth: { token }, transports: ['websocket'], reconnection: false });
  socket.on(evento, (datos) => llegadas.set(clave(datos), performance.now()));
  const listo = new Promise((resolver, rechazar) => {
    socket.on('connect', resolver);
    socket.on('connect_error', (err) => rechazar(new Error(`el canal rechazo la conexion: ${err.message}`)));
  });
  return { socket, llegadas, listo };
}

// Espera a que el aviso de ese pedido haya llegado (puede llegar antes que la respuesta HTTP).
async function llegadaDe(llegadas, clave, plazoMs = 5000) {
  const fin = performance.now() + plazoMs;
  while (!llegadas.has(clave)) {
    if (performance.now() > fin) return null;
    await new Promise((r) => setTimeout(r, 5));
  }
  return llegadas.get(clave);
}

function resumen(nombre, tiempos) {
  const orden = [...tiempos].sort((a, b) => a - b);
  const en = (q) => orden[Math.min(orden.length - 1, Math.floor(q * orden.length))];
  const f = (ms) => `${ms.toFixed(0)} ms`;
  console.log(`  ${nombre.padEnd(30)} ${orden.length} mediciones · minimo ${f(orden[0])} · mediana ${f(en(0.5))}`
    + ` · p95 ${f(en(0.95))} · maximo ${f(orden[orden.length - 1])}`);
  return orden[orden.length - 1];
}

async function main() {
  const recepcion = process.env.TOKEN_RECEPCION;
  const cocina = process.env.TOKEN_COCINA;

  const { cuerpo: carta } = await llamar('GET', '/productos?categoria=pizza', recepcion);
  const peperoni = carta.productos.find((p) => p.nombre === 'Peperoni');

  const enCocina = conectar(cocina, 'pedido:nuevo', (p) => p.id);
  const enRecepcion = conectar(recepcion, 'pedido:estado', (a) => `${a.id}:${a.nuevo}`);
  const agregadoEnCocina = conectar(cocina, 'pedido:actualizado', (p) => `${p.id}:${p.version}`);
  await Promise.all([enCocina.listo, enRecepcion.listo, agregadoEnCocina.listo]);
  console.log(`Canal: ${ORIGEN} · transporte ${enCocina.socket.io.engine.transport.name}`);

  const nuevos = [];
  const cambios = [];
  const agregados = [];
  const creados = [];
  try {
    for (let i = 0; i < VECES; i += 1) {
      const inicio = performance.now();
      const { estado, cuerpo } = await llamar('POST', '/pedidos', recepcion, {
        paraLlevar: true,
        cliente: { nombre: 'Ana Prueba', celular: '70000001' },
        observacion: 'medicion del aviso',
        lineas: [{ productoId: peperoni.id, cantidad: 1 }],
        totalEsperado: peperoni.precio,
      });
      if (estado !== 201) throw new Error(`la venta respondio ${estado}: ${JSON.stringify(cuerpo)}`);
      const { id } = cuerpo.pedido;
      creados.push(id);
      const llegada = await llegadaDe(enCocina.llegadas, id);
      if (llegada === null) throw new Error(`cocina no recibio el pedido #${id}`);
      nuevos.push(llegada - inicio);

      const inicioCambio = performance.now();
      await llamar('PATCH', `/pedidos/${id}/estado`, cocina, { estado: 'en_preparacion' });
      const llegadaCambio = await llegadaDe(enRecepcion.llegadas, `${id}:en_preparacion`);
      if (llegadaCambio === null) throw new Error(`recepcion no recibio el cambio del pedido #${id}`);
      cambios.push(llegadaCambio - inicioCambio);

      const inicioAgregado = performance.now();
      const agregado = await llamar('POST', `/pedidos/${id}/lineas`, recepcion, {
        lineas: [{ productoId: peperoni.id, cantidad: 1 }],
        totalEsperado: peperoni.precio,
      });
      if (agregado.estado !== 200) throw new Error(`agregar respondio ${agregado.estado}: ${JSON.stringify(agregado.cuerpo)}`);
      // La version es la cantidad de lineas: con la pizza agregada, 2.
      const llegadaAgregado = await llegadaDe(agregadoEnCocina.llegadas, `${id}:2`);
      if (llegadaAgregado === null) throw new Error(`cocina no recibio lo agregado al pedido #${id}`);
      agregados.push(llegadaAgregado - inicioAgregado);
    }
  } finally {
    for (const id of creados) {
      await llamar('POST', `/pedidos/${id}/cancelacion`, recepcion, { motivo: 'Medicion del aviso' });
    }
    enCocina.socket.close();
    enRecepcion.socket.close();
    agregadoEnCocina.socket.close();
  }

  console.log('Del envio al aviso: la venta en cocina, el cambio de estado en recepcion y lo agregado en cocina:');
  const peorNuevo = resumen('pedido nuevo -> cocina', nuevos);
  const peorCambio = resumen('cambio de estado -> recepcion', cambios);
  const peorAgregado = resumen('lo agregado -> cocina', agregados);
  console.log(`Pedidos de la medicion cancelados: ${creados.length}`);
  const bien = peorNuevo < LIMITE_MS && peorCambio < LIMITE_MS && peorAgregado < LIMITE_MS;
  console.log(bien ? `TODO BAJO ${LIMITE_MS} ms` : `HAY MEDICIONES DE ${LIMITE_MS} ms O MAS`);
  process.exit(bien ? 0 : 1);
}

main().catch((err) => {
  console.error('La medicion fallo:', err.message);
  process.exit(1);
});
