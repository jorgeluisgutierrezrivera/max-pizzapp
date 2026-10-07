const express = require('express');
const { exigirRol, ROLES_DEL_SISTEMA } = require('../autenticacion');
const { ErrorApi } = require('../errores');
const { avisar } = require('../tiempo-real');

// La carta:
//
//   GET   /api/v1/productos?categoria=pizza&disponible=true   leerla (los dos roles)
//   PATCH /api/v1/productos/:id/disponibilidad                marcarlo agotado o disponible
//                                                             (RF-13, D-66; cada rol lo suyo, D-76)
//   PATCH /api/v1/productos/disponibilidad                    agotar o reponer una categoria
//                                                             entera: se acabo la masa (D-70)
//
// Recepcion la usa para armar el pedido, y cocina para marcar lo que se acabo. Sin filtros
// devuelve TODA la carta, agotados incluidos: la pantalla los muestra atenuados, y un
// producto que desaparece sin aviso confunde mas que uno marcado.
//
// La ruta de la disponibilidad cambia SOLO eso: precios, nombres y altas son del rol
// administrador, fuera de alcance (D-13).
//
// Cada rol agota y repone solo lo que maneja (D-76): las pizzas, los extras y lo que sale de
// la cocina, cocina; las bebidas, recepcion, que las tiene en el mostrador. Lo ajeno responde
// 403 sin cambiar nada. Leer la carta es para los dos: recepcion vende lo que cocina tiene.

// Los mismos valores que el tipo categoria_producto de la base. «extra» es un agregado que
// se vende colgado de una pizza (D-28).
const CATEGORIAS = ['pizza', 'entrada', 'bebida', 'postre', 'extra'];
const FILTROS = ['categoria', 'disponible'];

// Que agota y repone cada rol (D-76). Entradas y postres hoy no tienen productos: salen de la
// cocina, asi que son de cocina.
const CATEGORIAS_DEL_ROL = {
  cocina: ['pizza', 'extra', 'entrada', 'postre'],
  recepcion: ['bebida'],
};

// Las categorias que puede marcar quien llama, segun sus roles.
function categoriasDe(roles) {
  return CATEGORIAS.filter((c) => roles.some((rol) => (CATEGORIAS_DEL_ROL[rol] || []).includes(c)));
}

function deOtroRol(categoria) {
  const mensaje = categoria === 'bebida'
    ? 'Las bebidas las agota y repone recepcion.'
    : 'Las pizzas y los extras los agota y repone cocina.';
  return new ErrorApi(403, 'ROL_SIN_PERMISO', mensaje, { categoria });
}

// Una sola consulta, siempre con el mismo texto. Los filtros viajan como parametros y un
// filtro ausente llega como NULL, que desactiva su condicion: no se arma SQL concatenando
// nada que venga del cliente. El orden es el de la carta: primero las pizzas y despues las
// demas categorias (los tipos enumerados ordenan por su declaracion), y dentro de cada una
// por nombre, que es como la vendedora busca lo que le piden (D-30).
const SQL_CARTA = `
  SELECT id, nombre, categoria, precio, descripcion, imagen, disponible, solo_entera
    FROM producto
   WHERE ($1::categoria_producto IS NULL OR categoria = $1::categoria_producto)
     AND ($2::boolean IS NULL OR disponible = $2::boolean)
   ORDER BY categoria, nombre`;

// Marca el producto y devuelve tambien como estaba, en una sola consulta: la fila se bloquea
// al leerla (FOR UPDATE), asi dos marcas a la vez no se pisan y la segunda ve la primera.
// Sin el valor anterior no se sabria si hay algo que avisar.
//
// Solo cambia si la categoria es de quien llama ($3, D-76). Las tres respuestas posibles:
// ninguna fila (no existe: 404), una fila sin "id" (es de otro rol: 403, no cambio nada) o
// la fila actualizada.
const SQL_DISPONIBILIDAD = `
  WITH anterior AS (
    SELECT id, disponible, categoria FROM producto WHERE id = $1 FOR UPDATE
  ), cambio AS (
    UPDATE producto AS p
       SET disponible = $2
      FROM anterior
     WHERE p.id = anterior.id
       AND anterior.categoria = ANY($3::categoria_producto[])
    RETURNING p.id, p.nombre, p.categoria, p.precio, p.descripcion, p.imagen, p.disponible,
              p.solo_entera
  )
  SELECT anterior.categoria AS categoria_actual, anterior.disponible AS disponible_antes, cambio.*
    FROM anterior LEFT JOIN cambio ON true`;

// Agota o repone una categoria entera (D-70): una sola consulta, que cambia solo lo que hacia
// falta y devuelve que cambio. Sin cambios, no hay nada que avisar.
const SQL_DISPONIBILIDAD_DE_CATEGORIA = `
  UPDATE producto
     SET disponible = $2
   WHERE categoria = $1::categoria_producto AND disponible <> $2
  RETURNING id`;

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
    throw filtroInvalido('La categoria debe ser pizza, entrada, bebida, postre o extra.');
  }
  if (disponible !== undefined && disponible !== 'true' && disponible !== 'false') {
    throw filtroInvalido('El filtro disponible debe ser true o false.');
  }
  return {
    categoria: categoria === undefined ? null : categoria,
    disponible: disponible === undefined ? null : disponible === 'true',
  };
}

// El :id de la ruta: un entero positivo que cabe en la columna, o nada.
function leerId(texto) {
  if (!/^[1-9][0-9]{0,9}$/.test(texto) || Number(texto) > 2147483647) {
    throw new ErrorApi(400, 'ID_INVALIDO', 'El numero de producto no es valido.');
  }
  return Number(texto);
}

// El cuerpo: exactamente { "disponible": true } o { "disponible": false }. Un campo de mas
// tambien se rechaza: esta ruta no cambia nada mas del producto.
function leerDisponibilidad(cuerpo) {
  const valido = cuerpo !== null && typeof cuerpo === 'object' && !Array.isArray(cuerpo)
    && Object.keys(cuerpo).length === 1 && typeof cuerpo.disponible === 'boolean';
  if (!valido) {
    throw new ErrorApi(400, 'DISPONIBILIDAD_INVALIDA',
      'Indica solo si el producto esta disponible: { "disponible": true } o { "disponible": false }.');
  }
  return cuerpo.disponible;
}

// El cuerpo de la categoria entera: exactamente { "categoria": "pizza", "disponible": false }.
function leerCambioDeCategoria(cuerpo) {
  const valido = cuerpo !== null && typeof cuerpo === 'object' && !Array.isArray(cuerpo)
    && Object.keys(cuerpo).length === 2 && CATEGORIAS.includes(cuerpo.categoria)
    && typeof cuerpo.disponible === 'boolean';
  if (!valido) {
    throw new ErrorApi(400, 'DISPONIBILIDAD_INVALIDA',
      'Indica la categoria y si queda disponible: { "categoria": "pizza", "disponible": false }.');
  }
  return { categoria: cuerpo.categoria, disponible: cuerpo.disponible };
}

// PostgreSQL devuelve los numeric como texto, para no perder precision. Los precios de la
// carta tienen dos decimales y caben sin perdida en un numero de JSON: la app los recibe
// listos para mostrar. La imagen es solo el nombre del archivo; la app sabe donde buscarlo.
// La descripcion son los ingredientes, que la vendedora ve al elegir; puede faltar.
// No hay precio de media: en una pizza de dos mitades cada una vale la mitad exacta (D-27).
// soloEntera marca las pizzas que ya combinan sabores y no se venden por mitades (D-39).
function aProducto(fila) {
  return {
    id: fila.id,
    nombre: fila.nombre,
    categoria: fila.categoria,
    precio: Number(fila.precio),
    descripcion: fila.descripcion,
    imagen: fila.imagen,
    disponible: fila.disponible,
    soloEntera: fila.solo_entera,
  };
}

function rutasProductos({ pool, autenticar, avisos }) {
  const rutas = express.Router();

  rutas.get('/productos', autenticar, exigirRol(...ROLES_DEL_SISTEMA), async (req, res) => {
    const { categoria, disponible } = leerFiltros(req.query);
    const { rows } = await pool.query(SQL_CARTA, [categoria, disponible]);
    res.json({ productos: rows.map(aProducto) });
  });

  // Una categoria entera (D-70). Va antes que la de un producto solo por claridad: no chocan,
  // porque esta tiene un tramo menos. Un solo aviso, con todos los que cambiaron.
  rutas.patch('/productos/disponibilidad', autenticar, exigirRol(...ROLES_DEL_SISTEMA), async (req, res) => {
    const { categoria, disponible } = leerCambioDeCategoria(req.body);
    // Lo ajeno se rechaza antes de tocar la base (D-76).
    if (!categoriasDe(req.usuario.roles).includes(categoria)) throw deOtroRol(categoria);
    const { rows } = await pool.query(SQL_DISPONIBILIDAD_DE_CATEGORIA, [categoria, disponible]);
    const ids = rows.map((fila) => fila.id).sort((a, b) => a - b);
    res.json({ categoria, disponible, cambiados: ids });
    if (ids.length > 0) {
      const por = req.usuario.roles[0];
      avisar(() => avisos.categoriaCambiada({ categoria, disponible, ids, por }));
    }
  });

  // Se valida todo ANTES de tocar la base. Marcar lo que ya estaba igual responde 200 y no
  // avisa: no hay nada que contar, y dos personas que tocan el mismo interruptor a la vez no
  // generan avisos repetidos. El aviso sale despues de guardar (como en los pedidos).
  rutas.patch('/productos/:id/disponibilidad', autenticar, exigirRol(...ROLES_DEL_SISTEMA), async (req, res) => {
    const id = leerId(req.params.id);
    const disponible = leerDisponibilidad(req.body);
    const { rows } = await pool.query(SQL_DISPONIBILIDAD, [id, disponible, categoriasDe(req.usuario.roles)]);
    if (rows.length === 0) {
      throw new ErrorApi(404, 'PRODUCTO_NO_ENCONTRADO', 'Ese producto no esta en la carta.');
    }
    // El producto existe pero es de otro rol: la consulta no lo cambio (D-76).
    if (rows[0].id === null) throw deOtroRol(rows[0].categoria_actual);
    const producto = aProducto(rows[0]);
    res.json({ producto });
    if (rows[0].disponible_antes !== disponible) {
      const { nombre, categoria } = producto;
      const por = req.usuario.roles[0];
      avisar(() => avisos.disponibilidadCambiada({ id, nombre, categoria, disponible, por }));
    }
  });

  return rutas;
}

module.exports = { rutasProductos, CATEGORIAS, CATEGORIAS_DEL_ROL };
