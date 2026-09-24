// La venta que llega de recepcion: se valida su forma y se calcula su precio.
//
// Es logica pura, sin base ni HTTP: recibe el cuerpo de la peticion y los productos de la
// carta, y devuelve lo que hay que guardar o el error exacto. Asi la regla de precio se
// prueba con la misma tabla de casos que la app (plan 05, seccion 6). Si alguna vez la app
// y el servidor difieren, manda el servidor.
//
// El dinero se cuenta en CENTAVOS ENTEROS: 47,50 es 4750. Sumar decimales acumula errores
// de redondeo; sumar enteros, no.

const MAXIMO_POR_LINEA = 999; // el mismo tope que la app y que la base
const MAXIMO_DE_LINEAS = 100;
const MAXIMO_DE_EXTRAS = 10;
const LARGO_NOMBRE = 120;
const LARGO_OBSERVACION = 240;
const CELULAR = /^[67][0-9]{7}$/; // celular boliviano: 8 digitos que empiezan con 6 o 7

class VentaInvalida extends Error {
  constructor(mensaje) {
    super(mensaje);
    this.codigo = 'VENTA_INVALIDA';
  }
}

class ProductoNoDisponible extends Error {
  constructor(id, nombre) {
    super(`${nombre} no esta disponible. Quitalo de la venta o elige otro.`);
    this.codigo = 'PRODUCTO_NO_DISPONIBLE';
    this.producto = { id, nombre };
  }
}

function esEnteroEntre(valor, minimo, maximo) {
  return Number.isInteger(valor) && valor >= minimo && valor <= maximo;
}

function esId(valor) {
  return Number.isInteger(valor) && valor > 0 && valor <= 2147483647;
}

// Un precio de la base ('47.50') o de la peticion (47.5), en centavos. Con dos decimales,
// redondear el producto por 100 es exacto; un tercer decimal no es un precio valido.
function aCentavos(valor) {
  const numero = typeof valor === 'string' ? Number(valor) : valor;
  if (typeof numero !== 'number' || !Number.isFinite(numero) || numero < 0) return null;
  const centavos = Math.round(numero * 100);
  return Math.abs(centavos - numero * 100) < 1e-6 ? centavos : null;
}

// D-27: una pizza de dos mitades cuesta la mitad exacta de la suma, redondeando la media
// mitad de centavo hacia arriba. Es la misma cuenta que precioDeDosMitades en la app.
function precioDeDosMitades(a, b) {
  return Math.floor((a + b + 1) / 2);
}

function textoOpcional(valor, largo, campo) {
  if (valor === undefined || valor === null) return null;
  if (typeof valor !== 'string') throw new VentaInvalida(`${campo} debe ser texto.`);
  const limpio = valor.trim();
  if (limpio.length > largo) throw new VentaInvalida(`${campo} admite hasta ${largo} caracteres.`);
  return limpio === '' ? null : limpio;
}

// --- 1. La forma ------------------------------------------------------------------------
// Todo lo que se puede comprobar sin la carta. Devuelve la venta normalizada.
function leerVenta(cuerpo) {
  if (!cuerpo || typeof cuerpo !== 'object' || Array.isArray(cuerpo)) {
    throw new VentaInvalida('La venta llego vacia.');
  }
  const { paraLlevar, cliente, observacion, lineas, totalEsperado } = cuerpo;

  if (typeof paraLlevar !== 'boolean') {
    throw new VentaInvalida('Falta indicar si el pedido es para llevar o para comer aqui.');
  }

  if (!cliente || typeof cliente !== 'object' || Array.isArray(cliente)) {
    throw new VentaInvalida('Falta el nombre del cliente.');
  }
  const nombre = textoOpcional(cliente.nombre, LARGO_NOMBRE, 'El nombre');
  if (nombre === null) throw new VentaInvalida('Falta el nombre del cliente.');
  const celular = textoOpcional(cliente.celular, 20, 'El celular');
  if (celular !== null && !CELULAR.test(celular)) {
    throw new VentaInvalida('El celular debe tener 8 digitos y empezar con 6 o 7.');
  }

  if (!Array.isArray(lineas) || lineas.length === 0) {
    throw new VentaInvalida('Agregue al menos un producto.');
  }
  if (lineas.length > MAXIMO_DE_LINEAS) {
    throw new VentaInvalida(`Una venta admite hasta ${MAXIMO_DE_LINEAS} lineas.`);
  }
  const normalizadas = lineas.map((linea, i) => {
    const donde = `La linea ${i + 1}`;
    if (!linea || typeof linea !== 'object' || Array.isArray(linea)) {
      throw new VentaInvalida(`${donde} no es valida.`);
    }
    const { productoId, mitadId = null, cantidad, extras = [] } = linea;
    if (!esId(productoId)) throw new VentaInvalida(`${donde} no dice que producto es.`);
    if (mitadId !== null && !esId(mitadId)) {
      throw new VentaInvalida(`${donde} tiene una segunda mitad no valida.`);
    }
    if (mitadId === productoId) {
      throw new VentaInvalida(`${donde} tiene las dos mitades del mismo sabor: es una pizza de un sabor.`);
    }
    if (!esEnteroEntre(cantidad, 1, MAXIMO_POR_LINEA)) {
      throw new VentaInvalida(`${donde}: la cantidad va de 1 a ${MAXIMO_POR_LINEA}.`);
    }
    if (!Array.isArray(extras) || extras.length > MAXIMO_DE_EXTRAS || !extras.every(esId)) {
      throw new VentaInvalida(`${donde} tiene extras no validos.`);
    }
    if (new Set(extras).size !== extras.length) {
      throw new VentaInvalida(`${donde} repite un extra.`);
    }
    return { productoId, mitadId, cantidad, extras };
  });

  const totalEsperadoCentavos = aCentavos(totalEsperado);
  if (totalEsperadoCentavos === null) {
    throw new VentaInvalida('Falta el total que se mostro en la venta.');
  }

  return {
    paraLlevar,
    cliente: { nombre, celular },
    observacion: textoOpcional(observacion, LARGO_OBSERVACION, 'La observacion'),
    lineas: normalizadas,
    totalEsperadoCentavos,
  };
}

// Los ids de producto que la venta menciona, para leerlos de la base de una vez.
function idsDeProductos(venta) {
  const ids = new Set();
  for (const linea of venta.lineas) {
    ids.add(linea.productoId);
    if (linea.mitadId !== null) ids.add(linea.mitadId);
    linea.extras.forEach((id) => ids.add(id));
  }
  return [...ids];
}

// --- 2. El precio -----------------------------------------------------------------------
// Con los productos de la base (id -> { nombre, categoria, precio, disponible }), cada
// linea recibe su precio unitario y su subtotal. Los extras cuelgan de su pizza y llevan
// su misma cantidad. Un pedido con pizzas nace pendiente; uno sin pizzas, listo (D-32).
function calcularVenta(venta, productos) {
  function producto(id, donde) {
    const p = productos.get(id);
    if (!p) throw new VentaInvalida(`${donde} menciona un producto que no existe en la carta.`);
    if (!p.disponible) throw new ProductoNoDisponible(id, p.nombre);
    const precio = aCentavos(p.precio);
    if (precio === null) throw new Error(`precio no valido en la base para el producto ${id}`);
    return { ...p, precio };
  }

  let total = 0;
  let hayPizzas = false;

  const lineas = venta.lineas.map((linea, i) => {
    const donde = `La linea ${i + 1}`;
    const principal = producto(linea.productoId, donde);

    if (principal.categoria === 'extra') {
      throw new VentaInvalida(`${donde}: un extra se agrega a una pizza, no se vende solo.`);
    }
    if (principal.categoria !== 'pizza' && (linea.mitadId !== null || linea.extras.length > 0)) {
      throw new VentaInvalida(`${donde}: solo una pizza lleva segunda mitad o extras.`);
    }

    let unitario = principal.precio;
    if (linea.mitadId !== null) {
      const mitad = producto(linea.mitadId, donde);
      if (mitad.categoria !== 'pizza') {
        throw new VentaInvalida(`${donde}: la otra mitad tiene que ser una pizza.`);
      }
      unitario = precioDeDosMitades(principal.precio, mitad.precio);
    }

    const extras = linea.extras.map((id) => {
      const extra = producto(id, donde);
      if (extra.categoria !== 'extra') {
        throw new VentaInvalida(`${donde}: ${extra.nombre} no es un extra.`);
      }
      const subtotal = extra.precio * linea.cantidad;
      total += subtotal;
      return { productoId: id, cantidad: linea.cantidad, unitario: extra.precio, subtotal };
    });

    if (principal.categoria === 'pizza') hayPizzas = true;
    const subtotal = unitario * linea.cantidad;
    total += subtotal;
    return {
      productoId: linea.productoId,
      mitadId: linea.mitadId,
      cantidad: linea.cantidad,
      unitario,
      subtotal,
      extras,
    };
  });

  return { lineas, total, estadoInicial: hayPizzas ? 'pendiente' : 'listo' };
}

// Centavos a la forma en que los guarda la base (numeric) y los muestra la API.
function aBolivianos(centavos) {
  return centavos / 100;
}

module.exports = {
  leerVenta, idsDeProductos, calcularVenta, precioDeDosMitades, aCentavos, aBolivianos,
  VentaInvalida, ProductoNoDisponible, MAXIMO_POR_LINEA, LARGO_OBSERVACION,
};
