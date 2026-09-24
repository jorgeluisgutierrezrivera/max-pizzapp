const express = require('express');
const { exigirRol, ROLES_DEL_SISTEMA } = require('../autenticacion');
const { ErrorApi } = require('../errores');
const { leerVenta, VentaInvalida, ProductoNoDisponible } = require('../precio');
const { crearPedido } = require('../pedidos/crear');
const { leerPedidos, idsPorEstados, leerHistorial, puedeVerCelular } = require('../pedidos/leer');
const { TRANSICIONES, cambiarEstado } = require('../pedidos/estados');

// Los pedidos, con su CRUD completo:
//
//   POST   /api/v1/pedidos                   crear (recepcion, RF-02)
//   GET    /api/v1/pedidos?estado=...        leer la cola (los dos roles, RF-06)
//   GET    /api/v1/pedidos/:id               leer uno, con su historial
//   PATCH  /api/v1/pedidos/:id/estado        avanzar (cocina: RF-07; recepcion: RF-05)
//   POST   /api/v1/pedidos/:id/cancelacion   dar de baja, con motivo (recepcion, RF-09)
//
// No hay DELETE: la baja es la cancelacion, y el pedido cancelado se conserva con su
// historial (D-33). El servidor vuelve a validar todo lo que la app ya valido, calcula el
// precio con la regla de D-27 y decide quien puede hacer cada cambio.
//
// Cada operacion que cambia algo avisa por el canal en vivo DESPUES del COMMIT: nadie se
// entera de un pedido que no llego a guardarse, ni de un cambio que se deshizo.

const ESTADOS = ['pendiente', 'en_preparacion', 'listo', 'entregado', 'cancelado'];
const ACTIVOS = ['pendiente', 'en_preparacion', 'listo'];
const LARGO_MOTIVO = 120;

// Los errores de la regla de venta, en el formato unico de la API. El de un producto
// agotado lleva cual es, para que la app lo marque en la venta sin adivinarlo del texto.
function aErrorApi(err) {
  if (err instanceof VentaInvalida) return new ErrorApi(400, 'VENTA_INVALIDA', err.message);
  if (err instanceof ProductoNoDisponible) {
    return new ErrorApi(409, 'PRODUCTO_NO_DISPONIBLE', err.message, { producto: err.producto });
  }
  return err;
}

// ?estado=pendiente,en_preparacion — uno o varios, separados por coma. Sin filtro, los
// activos. Como en la carta, se valida antes de tocar la base.
function leerFiltroDeEstado(query) {
  if (Object.keys(query).some((clave) => clave !== 'estado')) {
    throw new ErrorApi(400, 'FILTRO_INVALIDO', 'Los pedidos solo se pueden filtrar por estado.');
  }
  if (query.estado === undefined) return ACTIVOS;
  const estados = typeof query.estado === 'string' ? query.estado.split(',') : null;
  if (!estados || estados.some((e) => !ESTADOS.includes(e))) {
    throw new ErrorApi(400, 'FILTRO_INVALIDO',
      'El estado debe ser pendiente, en_preparacion, listo, entregado o cancelado, separados por coma.');
  }
  return [...new Set(estados)];
}

// El :id de la ruta: un entero positivo que cabe en la columna, o nada.
function leerId(texto) {
  if (!/^[1-9][0-9]{0,9}$/.test(texto) || Number(texto) > 2147483647) {
    throw new ErrorApi(400, 'ID_INVALIDO', 'El numero de pedido no es valido.');
  }
  return Number(texto);
}

function leerMotivo(cuerpo) {
  const motivo = cuerpo && typeof cuerpo.motivo === 'string' ? cuerpo.motivo.trim() : '';
  if (motivo === '') {
    throw new ErrorApi(400, 'MOTIVO_INVALIDO', 'Escribe por que se cancela el pedido.');
  }
  if (motivo.length > LARGO_MOTIVO) {
    throw new ErrorApi(400, 'MOTIVO_INVALIDO', `El motivo admite hasta ${LARGO_MOTIVO} caracteres.`);
  }
  return motivo;
}

// Un aviso que falla no deshace nada: la operacion ya se guardo y se respondio. Se anota y
// la pantalla se pone al dia la proxima vez que lea la lista.
function avisar(accion) {
  try {
    accion();
  } catch (err) {
    console.error('[canal] no se pudo avisar:', err.message);
  }
}

function rutasPedidos({ pool, autenticar, avisos }) {
  const rutas = express.Router();
  const deCualquierRol = [autenticar, exigirRol(...ROLES_DEL_SISTEMA)];

  async function uno(id, usuario) {
    const [pedido] = await leerPedidos(pool, [id], { verCelular: puedeVerCelular(usuario) });
    return pedido;
  }

  rutas.post('/pedidos', autenticar, exigirRol('recepcion'), async (req, res) => {
    let id;
    try {
      // La forma se valida ANTES de pedir una conexion: una venta mal armada no toca la base.
      const venta = leerVenta(req.body);
      id = await crearPedido(pool, venta, req.usuario);
    } catch (err) {
      throw aErrorApi(err);
    }
    const pedido = await uno(id, req.usuario);
    res.status(201).location(`/api/v1/pedidos/${id}`).json({ pedido });
    avisar(() => avisos.pedidoNuevo(pedido));
  });

  rutas.get('/pedidos', ...deCualquierRol, async (req, res) => {
    const estados = leerFiltroDeEstado(req.query);
    const ids = await idsPorEstados(pool, estados);
    const pedidos = await leerPedidos(pool, ids, { verCelular: puedeVerCelular(req.usuario) });
    res.json({ pedidos });
  });

  rutas.get('/pedidos/:id', ...deCualquierRol, async (req, res) => {
    const id = leerId(req.params.id);
    const pedido = await uno(id, req.usuario);
    if (!pedido) throw new ErrorApi(404, 'PEDIDO_NO_ENCONTRADO', `No existe el pedido #${id}.`);
    res.json({ pedido: { ...pedido, historial: await leerHistorial(pool, id) } });
  });

  rutas.patch('/pedidos/:id/estado', ...deCualquierRol, async (req, res) => {
    const id = leerId(req.params.id);
    const hacia = req.body && req.body.estado;
    if (hacia === 'cancelado') {
      throw new ErrorApi(400, 'ESTADO_INVALIDO', 'Para cancelar un pedido se usa la cancelacion, con su motivo.');
    }
    if (typeof hacia !== 'string' || !Object.hasOwn(TRANSICIONES, hacia)) {
      throw new ErrorApi(400, 'ESTADO_INVALIDO', 'El estado debe ser en_preparacion, listo o entregado.');
    }
    const { anterior } = await cambiarEstado(pool, id, hacia, req.usuario);
    res.json({ pedido: await uno(id, req.usuario) });
    avisar(() => avisos.estadoCambiado({ id, anterior, nuevo: hacia }));
  });

  rutas.post('/pedidos/:id/cancelacion', autenticar, exigirRol('recepcion'), async (req, res) => {
    const id = leerId(req.params.id);
    const motivo = leerMotivo(req.body);
    const { anterior } = await cambiarEstado(pool, id, 'cancelado', req.usuario, motivo);
    res.json({ pedido: await uno(id, req.usuario) });
    avisar(() => avisos.estadoCambiado({ id, anterior, nuevo: 'cancelado' }));
  });

  return rutas;
}

module.exports = { rutasPedidos };
