const express = require('express');
const { exigirRol } = require('../autenticacion');
const { ErrorApi } = require('../errores');
const { leerVenta, VentaInvalida, ProductoNoDisponible } = require('../precio');
const { crearPedido } = require('../pedidos/crear');
const { leerPedidos, puedeVerCelular } = require('../pedidos/leer');

// Los pedidos: POST /api/v1/pedidos
//
// Recepcion registra la venta (RF-02). El servidor vuelve a validar todo lo que la app ya
// valido, calcula el precio con la regla de D-27 y guarda el pedido en una transaccion. La
// app nunca decide un precio: solo muestra una vista previa.

// Los errores de la regla de venta, en el formato unico de la API. El de un producto
// agotado lleva cual es, para que la app lo marque en la venta sin adivinarlo del texto.
function aErrorApi(err) {
  if (err instanceof VentaInvalida) return new ErrorApi(400, 'VENTA_INVALIDA', err.message);
  if (err instanceof ProductoNoDisponible) {
    return new ErrorApi(409, 'PRODUCTO_NO_DISPONIBLE', err.message, { producto: err.producto });
  }
  return err;
}

function rutasPedidos({ pool, autenticar }) {
  const rutas = express.Router();

  rutas.post('/pedidos', autenticar, exigirRol('recepcion'), async (req, res) => {
    let id;
    try {
      // La forma se valida ANTES de pedir una conexion: una venta mal armada no toca la base.
      const venta = leerVenta(req.body);
      id = await crearPedido(pool, venta, req.usuario);
    } catch (err) {
      throw aErrorApi(err);
    }
    const [pedido] = await leerPedidos(pool, [id], { verCelular: puedeVerCelular(req.usuario) });
    res.status(201).location(`/api/v1/pedidos/${id}`).json({ pedido });
  });

  return rutas;
}

module.exports = { rutasPedidos };
