// La carga del listado principal (RNF-01, tarjeta 10, D-58), con k6:
//
//   "carga del listado principal en menos de 2 segundos con 50 pedidos activos y 5 usuarios
//    concurrentes, medida con k6 sobre GET /api/v1/pedidos y reportando el percentil 95"
//
//   1. setup: recepcion crea 50 pedidos pendientes, con datos ficticios.
//   2. 5 usuarios a la vez, durante 60 s: cada uno lee el listado y espera 1 s. Tres son de
//      recepcion y dos de cocina, las dos pantallas que lo leen.
//   3. teardown: cancela los 50, con el motivo "Prueba de carga k6". No queda ninguno activo.
//
// El umbral de 2 s esta en las opciones: si el percentil 95 no lo cumple, o si una lectura
// falla, k6 termina con error. Todo sale de una sola IP: 50 altas, unas 300 lecturas y 50
// cancelaciones quedan bajo el limite de 600 peticiones por minuto de la tarjeta 09.
//
// No se corre solo: lo lanza medir_carga.py, que obtiene los tokens reales de Keycloak y los
// pasa por el entorno (TOKEN_RECEPCION, TOKEN_COCINA). Nunca se imprimen.
import http from 'k6/http';
import { check, fail, sleep } from 'k6';

const API = __ENV.API_URL;
const ACTIVOS = 50;
const USUARIOS = 5;
const MOTIVO = 'Prueba de carga k6';

export const options = {
  scenarios: {
    listado: { executor: 'constant-vus', vus: USUARIOS, duration: '60s' },
  },
  thresholds: {
    'http_req_duration{nombre:listado}': ['p(95)<2000'],
    'http_req_failed{nombre:listado}': ['rate==0'],
    'checks{nombre:listado}': ['rate==1'],
  },
  // El percentil 95 es el del requisito; los demas, para leer el reporte.
  summaryTrendStats: ['min', 'med', 'avg', 'p(90)', 'p(95)', 'max'],
  setupTimeout: '120s',
  teardownTimeout: '120s',
};

function cabeceras(token) {
  return { headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' } };
}

export function setup() {
  const recepcion = __ENV.TOKEN_RECEPCION;
  const carta = http.get(`${API}/productos?categoria=pizza`, cabeceras(recepcion));
  if (carta.status !== 200) fail(`la carta respondio ${carta.status}`);
  const peperoni = carta.json('productos').find((p) => p.nombre === 'Peperoni');
  if (!peperoni) fail('no esta la pizza Peperoni en la carta');

  const ids = [];
  for (let i = 1; i <= ACTIVOS; i += 1) {
    const r = http.post(`${API}/pedidos`, JSON.stringify({
      paraLlevar: true,
      cliente: { nombre: 'Ana Prueba', celular: '70000001' },
      observacion: `${MOTIVO} (${i} de ${ACTIVOS})`,
      lineas: [{ productoId: peperoni.id, cantidad: 1 }],
      totalEsperado: peperoni.precio,
    }), Object.assign(cabeceras(recepcion), { tags: { nombre: 'alta' } }));
    if (r.status !== 201) {
      cancelar(ids, recepcion);
      fail(`la venta ${i} respondio ${r.status}: ${r.body}`);
    }
    ids.push(r.json('pedido.id'));
  }
  console.log(`setup: ${ids.length} pedidos activos creados (#${ids[0]} a #${ids[ids.length - 1]})`);
  return { ids };
}

export default function () {
  // Los usuarios 1, 3 y 5 son recepcion; el 2 y el 4, cocina.
  const token = __VU % 2 === 1 ? __ENV.TOKEN_RECEPCION : __ENV.TOKEN_COCINA;
  const rol = __VU % 2 === 1 ? 'recepcion' : 'cocina';
  const r = http.get(`${API}/pedidos`, Object.assign(cabeceras(token), { tags: { nombre: 'listado', rol } }));
  check(r, {
    'el listado responde 200': (res) => res.status === 200,
    // Comprueba la condicion del requisito: el listado trae los 50 de la prueba (y los que ya
    // hubiera activos).
    [`el listado trae ${ACTIVOS} pedidos activos o mas`]: (res) => res.status === 200 && res.json('pedidos').length >= ACTIVOS,
  }, { nombre: 'listado' });
  sleep(1);
}

function cancelar(ids, token) {
  let cancelados = 0;
  for (const id of ids) {
    const r = http.post(`${API}/pedidos/${id}/cancelacion`, JSON.stringify({ motivo: MOTIVO }),
      Object.assign(cabeceras(token), { tags: { nombre: 'cancelacion' } }));
    if (r.status === 200) cancelados += 1;
    else console.error(`el pedido #${id} no se pudo cancelar: ${r.status} ${r.body}`);
  }
  return cancelados;
}

export function teardown(datos) {
  const cancelados = cancelar(datos.ids, __ENV.TOKEN_RECEPCION);
  console.log(`teardown: ${cancelados} de ${datos.ids.length} pedidos de la prueba cancelados`);
  if (cancelados !== datos.ids.length) fail('quedaron pedidos de la prueba sin cancelar');
}
