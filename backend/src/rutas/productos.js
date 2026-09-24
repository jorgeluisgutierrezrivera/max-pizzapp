const express = require('express');
const { exigirRol, ROLES_DEL_SISTEMA } = require('../autenticacion');
const { ErrorApi } = require('../errores');

// La carta: GET /api/v1/productos?categoria=pizza&disponible=true
//
// La usan los dos roles: recepcion para armar el pedido y cocina para marcar un producto
// agotado (RF-13). Sin filtros devuelve TODA la carta, agotados incluidos: la pantalla los
// muestra atenuados, y un producto que desaparece sin aviso confunde mas que uno marcado.

// Los mismos valores que el tipo categoria_producto de la base.
const CATEGORIAS = ['pizza', 'entrada', 'bebida', 'postre'];
const FILTROS = ['categoria', 'disponible'];

// Una sola consulta, siempre con el mismo texto. Los filtros viajan como parametros y un
// filtro ausente llega como NULL, que desactiva su condicion: no se arma SQL concatenando
// nada que venga del cliente. El orden es el de la carta: pizzas tradicionales, premium y
// despues las demas categorias (los tipos enumerados ordenan por su declaracion).
const SQL_CARTA = `
  SELECT id, nombre, categoria, gama, precio, precio_media, imagen, disponible
    FROM producto
   WHERE ($1::categoria_producto IS NULL OR categoria = $1::categoria_producto)
     AND ($2::boolean IS NULL OR disponible = $2::boolean)
   ORDER BY categoria, gama NULLS LAST, nombre`;

function filtroInvalido(mensaje) {
  return new ErrorApi(400, 'FILTRO_INVALIDO', mensaje);
}

// Se valida ANTES de tocar la base: un valor que no esta en la lista no llega a la consulta.
// Un parametro repetido (?categoria=a&categoria=b) llega como lista y tambien se rechaza.
function leerFiltros(query) {
  if (Object.keys(query).some((clave) => !FILTROS.includes(clave))) {
    throw filtroInvalido('La carta solo se puede filtrar por categoria y disponible.');
  }
  const { categoria, disponible } = query;
  if (categoria !== undefined && !(typeof categoria === 'string' && CATEGORIAS.includes(categoria))) {
    throw filtroInvalido('La categoria debe ser pizza, entrada, bebida o postre.');
  }
  if (disponible !== undefined && disponible !== 'true' && disponible !== 'false') {
    throw filtroInvalido('El filtro disponible debe ser true o false.');
  }
  return {
    categoria: categoria === undefined ? null : categoria,
    disponible: disponible === undefined ? null : disponible === 'true',
  };
}

// PostgreSQL devuelve los numeric como texto, para no perder precision. Los precios de la
// carta tienen dos decimales y caben sin perdida en un numero de JSON: la app los recibe
// listos para mostrar. La imagen es solo el nombre del archivo; la app sabe donde buscarlo.
function aProducto(fila) {
  return {
    id: fila.id,
    nombre: fila.nombre,
    categoria: fila.categoria,
    gama: fila.gama,
    precio: Number(fila.precio),
    precioMedia: fila.precio_media === null ? null : Number(fila.precio_media),
    imagen: fila.imagen,
    disponible: fila.disponible,
  };
}

function rutasProductos({ pool, autenticar }) {
  const rutas = express.Router();

  rutas.get('/productos', autenticar, exigirRol(...ROLES_DEL_SISTEMA), async (req, res) => {
    const { categoria, disponible } = leerFiltros(req.query);
    const { rows } = await pool.query(SQL_CARTA, [categoria, disponible]);
    res.json({ productos: rows.map(aProducto) });
  });

  return rutas;
}

module.exports = { rutasProductos, CATEGORIAS };
