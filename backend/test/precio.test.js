// La regla de precio del servidor, sin base ni HTTP: la misma tabla de casos que prueba la
// app (plan 05, seccion 6), con los precios reales de la carta. Si la app y el servidor
// difieren alguna vez, esta tabla dice cual de los dos se equivoco.
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  leerVenta, leerAgregado, idsDeProductos, calcularVenta, calcularLineas, precioDeDosMitades,
  aCentavos, VentaInvalida, ProductoNoDisponible,
} = require('../src/precio');

// Los precios llegan de la base como texto, igual que los entrega pg.
const CARTA = new Map([
  [1, { nombre: 'Salame', categoria: 'pizza', precio: '45.00', disponible: true }],
  [2, { nombre: 'Peperoni', categoria: 'pizza', precio: '50.00', disponible: true }],
  [3, { nombre: 'Carnívora', categoria: 'pizza', precio: '60.00', disponible: true }],
  [4, { nombre: 'Criolla española', categoria: 'pizza', precio: '65.00', disponible: true, solo_entera: true }],
  [9, { nombre: 'Cuatro quesos', categoria: 'pizza', precio: '55.00', disponible: true }],
  [5, { nombre: 'Hawaiana', categoria: 'pizza', precio: '50.00', disponible: true }],
  [6, { nombre: 'Choclo', categoria: 'pizza', precio: '45.00', disponible: true }],
  [7, { nombre: 'Napolitana', categoria: 'pizza', precio: '40.00', disponible: false }],
  [8, { nombre: 'Dos estaciones', categoria: 'pizza', precio: '50.00', disponible: true, solo_entera: true }],
  [10, { nombre: 'Gaseosa 2 L', categoria: 'bebida', precio: '18.00', disponible: true }],
  [20, { nombre: 'Extra queso', categoria: 'extra', precio: '8.00', disponible: true }],
  [21, { nombre: 'Extra choclo', categoria: 'extra', precio: '5.00', disponible: true }],
]);

// Una venta valida minima; cada caso cambia solo lo que prueba.
function venta(lineas, cambios = {}) {
  return {
    paraLlevar: true,
    cliente: { nombre: 'Ana Prueba', celular: '70000001' },
    observacion: null,
    lineas,
    totalEsperado: 0,
    ...cambios,
  };
}

function calcular(lineas) {
  return calcularVenta(leerVenta(venta(lineas)), CARTA);
}

// La venta directa de bebidas (D-38): sin cliente, sin "para llevar", sin observacion.
function directa(lineas, cambios = {}) {
  return { ventaDirecta: true, lineas, totalEsperado: 0, ...cambios };
}

// --- la tabla del plan 05, seccion 6 ---------------------------------------------------

const TABLA = [
  ['1 Peperoni', [{ productoId: 2, cantidad: 1 }], 5000],
  ['1 mitad Salame, mitad Peperoni', [{ productoId: 1, mitadId: 2, cantidad: 1 }], 4750],
  // La tabla del plan 05 usaba Carnívora con Criolla española (62,50); la Criolla se vende solo
  // entera (D-39), y la mitad y mitad que termina en 50 centavos se prueba con Cuatro quesos.
  ['1 mitad Carnívora, mitad Cuatro quesos', [{ productoId: 3, mitadId: 9, cantidad: 1 }], 5750],
  ['2 mitad Salame, mitad Peperoni', [{ productoId: 1, mitadId: 2, cantidad: 2 }], 9500],
  ['1 Hawaiana con extra queso', [{ productoId: 5, cantidad: 1, extras: [20] }], 5800],
  ['3 Choclo, cada una con extra choclo', [{ productoId: 6, cantidad: 3, extras: [21] }], 15000],
];

test('precio: venta directa de 2 gaseosas = Bs 36', () => {
  assert.equal(calcularVenta(leerVenta(directa([{ productoId: 10, cantidad: 2 }])), CARTA).total, 3600);
});

for (const [nombre, lineas, total] of TABLA) {
  test(`precio: ${nombre} = Bs ${total / 100}`, () => {
    assert.equal(calcular(lineas).total, total);
  });
}

test('precio: la mitad A con B cuesta lo mismo que B con A', () => {
  const ab = calcular([{ productoId: 1, mitadId: 2, cantidad: 1 }]).total;
  const ba = calcular([{ productoId: 2, mitadId: 1, cantidad: 1 }]).total;
  assert.equal(ab, ba);
});

test('precio: la mitad exacta redondea la media mitad de centavo hacia arriba', () => {
  assert.equal(precioDeDosMitades(4500, 5000), 4750);
  assert.equal(precioDeDosMitades(4501, 5000), 4751); // 4750,5 -> 4751
  assert.equal(precioDeDosMitades(0, 1), 1);
});

test('precio: cada linea guarda su precio unitario y su subtotal; los extras, la cantidad de su pizza', () => {
  const { lineas } = calcular([{ productoId: 6, cantidad: 3, extras: [21] }, { productoId: 10, cantidad: 2 }]);
  assert.deepEqual(lineas[0], {
    productoId: 6, mitadId: null, cantidad: 3, unitario: 4500, subtotal: 13500,
    extras: [{ productoId: 21, cantidad: 3, unitario: 500, subtotal: 1500 }],
  });
  assert.deepEqual(lineas[1], {
    productoId: 10, mitadId: null, cantidad: 2, unitario: 1800, subtotal: 3600, extras: [],
  });
});

test('estado inicial: un pedido, con pizzas y bebidas, nace pendiente', () => {
  assert.equal(calcular([{ productoId: 2, cantidad: 1 }, { productoId: 10, cantidad: 1 }]).estadoInicial, 'pendiente');
});

test('estado inicial: la venta directa de bebidas nace entregada (D-38)', () => {
  const calculo = calcularVenta(leerVenta(directa([{ productoId: 10, cantidad: 2 }])), CARTA);
  assert.equal(calculo.estadoInicial, 'entregado');
});

test('un pedido a nombre de un cliente lleva al menos una pizza: solo bebidas se rechaza (D-38)', () => {
  assert.throws(() => calcular([{ productoId: 10, cantidad: 2 }]), (err) => {
    assert.ok(err instanceof VentaInvalida);
    assert.match(err.message, /al menos una pizza.*venta directa/);
    return true;
  });
});

test('una venta directa con una pizza se rechaza: las pizzas van en un pedido (D-38)', () => {
  const v = leerVenta(directa([{ productoId: 10, cantidad: 1 }, { productoId: 2, cantidad: 1 }]));
  assert.throws(() => calcularVenta(v, CARTA), (err) => {
    assert.ok(err instanceof VentaInvalida);
    assert.match(err.message, /solo de bebidas/);
    return true;
  });
});

test('lo que se agrega a un pedido: su precio y si trae pizzas (D-37)', () => {
  const soda = calcularLineas(leerAgregado({ lineas: [{ productoId: 10, cantidad: 1 }], totalEsperado: 18 }), CARTA);
  assert.equal(soda.total, 1800);
  assert.equal(soda.hayPizzas, false);
  const pizza = calcularLineas(leerAgregado({ lineas: [{ productoId: 1, mitadId: 2, cantidad: 1 }], totalEsperado: 47.5 }), CARTA);
  assert.equal(pizza.total, 4750);
  assert.equal(pizza.hayPizzas, true);
});

test('los ids de producto que menciona la venta, sin repetir', () => {
  const v = leerVenta(venta([
    { productoId: 1, mitadId: 2, cantidad: 1, extras: [20] },
    { productoId: 2, cantidad: 1, extras: [20, 21] },
  ]));
  assert.deepEqual(idsDeProductos(v).sort((a, b) => a - b), [1, 2, 20, 21]);
});

// --- rechazos que dependen de la carta ------------------------------------------------

function rechazaConCarta(nombre, lineas, clase, fragmento) {
  test(`rechaza: ${nombre}`, () => {
    assert.throws(() => calcular(lineas), (err) => {
      assert.ok(err instanceof clase, `se esperaba ${clase.name} y llego ${err.constructor.name}`);
      assert.match(err.message, fragmento);
      return true;
    });
  });
}

rechazaConCarta('la otra mitad no es una pizza', [{ productoId: 1, mitadId: 10, cantidad: 1 }], VentaInvalida, /otra mitad/);
rechazaConCarta('un extra vendido solo, sin pizza', [{ productoId: 20, cantidad: 1 }], VentaInvalida, /no se vende solo/);
rechazaConCarta('una bebida con extras', [{ productoId: 10, cantidad: 1, extras: [20] }], VentaInvalida, /solo una pizza/);
rechazaConCarta('una bebida con segunda mitad', [{ productoId: 10, mitadId: 1, cantidad: 1 }], VentaInvalida, /solo una pizza/);
rechazaConCarta('algo que no es un extra puesto como extra', [{ productoId: 1, cantidad: 1, extras: [10] }], VentaInvalida, /no es un extra/);
rechazaConCarta('un producto que no existe', [{ productoId: 999, cantidad: 1 }], VentaInvalida, /no existe/);
rechazaConCarta('una pizza agotada', [{ productoId: 7, cantidad: 1 }], ProductoNoDisponible, /Napolitana/);
rechazaConCarta('una mitad agotada', [{ productoId: 1, mitadId: 7, cantidad: 1 }], ProductoNoDisponible, /Napolitana/);
rechazaConCarta('una pizza solo entera como segunda mitad (D-39)', [{ productoId: 1, mitadId: 8, cantidad: 1 }], VentaInvalida, /Dos estaciones se vende solo entera/);
rechazaConCarta('Carnívora con Criolla española: la Criolla se vende solo entera (D-39)', [{ productoId: 3, mitadId: 4, cantidad: 1 }], VentaInvalida, /Criolla española se vende solo entera/);
rechazaConCarta('una pizza solo entera como primera mitad (D-39)', [{ productoId: 8, mitadId: 2, cantidad: 1 }], VentaInvalida, /Dos estaciones se vende solo entera/);

test('una pizza solo entera se vende entera, a su precio (D-39)', () => {
  assert.equal(calcular([{ productoId: 8, cantidad: 2 }]).total, 10000);
});

// --- rechazos de forma: no hace falta la carta -----------------------------------------

function rechazaForma(nombre, cuerpo, fragmento) {
  test(`rechaza la forma: ${nombre}`, () => {
    assert.throws(() => leerVenta(cuerpo), (err) => {
      assert.ok(err instanceof VentaInvalida);
      assert.match(err.message, fragmento);
      return true;
    });
  });
}

const PIZZA = [{ productoId: 2, cantidad: 1 }];

rechazaForma('sin cuerpo', undefined, /vacia/);
rechazaForma('una lista en vez de una venta', [], /vacia/);
rechazaForma('sin lineas', venta([]), /al menos un producto/);
rechazaForma('lineas que no son lista', venta('dos pizzas'), /al menos un producto/);
rechazaForma('mas de 100 lineas', venta(Array.from({ length: 101 }, () => ({ productoId: 10, cantidad: 1 }))), /100 lineas/);
rechazaForma('sin decir si es para llevar', venta(PIZZA, { paraLlevar: undefined }), /para llevar/);
rechazaForma('para llevar como texto', venta(PIZZA, { paraLlevar: 'si' }), /para llevar/);
rechazaForma('sin cliente', venta(PIZZA, { cliente: undefined }), /nombre del cliente/);
rechazaForma('nombre vacio', venta(PIZZA, { cliente: { nombre: '   ' } }), /nombre del cliente/);
rechazaForma('nombre de 121 caracteres', venta(PIZZA, { cliente: { nombre: 'a'.repeat(121) } }), /120/);
rechazaForma('celular de 7 digitos', venta(PIZZA, { cliente: { nombre: 'Ana', celular: '7000001' } }), /8 digitos/);
rechazaForma('celular que empieza con 5', venta(PIZZA, { cliente: { nombre: 'Ana', celular: '50000001' } }), /8 digitos/);
rechazaForma('celular con espacios', venta(PIZZA, { cliente: { nombre: 'Ana', celular: '7000 0001' } }), /8 digitos/);
rechazaForma('celular con prefijo de pais', venta(PIZZA, { cliente: { nombre: 'Ana', celular: '+59170000001' } }), /8 digitos/);
rechazaForma('celular como numero', venta(PIZZA, { cliente: { nombre: 'Ana', celular: 70000001 } }), /texto/);
rechazaForma('observacion de 241 caracteres', venta(PIZZA, { observacion: 'a'.repeat(241) }), /240/);
rechazaForma('cantidad 0', venta([{ productoId: 2, cantidad: 0 }]), /cantidad/);
rechazaForma('cantidad negativa', venta([{ productoId: 2, cantidad: -1 }]), /cantidad/);
rechazaForma('cantidad decimal', venta([{ productoId: 2, cantidad: 1.5 }]), /cantidad/);
rechazaForma('cantidad 1000', venta([{ productoId: 2, cantidad: 1000 }]), /cantidad/);
rechazaForma('cantidad como texto', venta([{ productoId: 2, cantidad: '2' }]), /cantidad/);
rechazaForma('producto como texto', venta([{ productoId: '2', cantidad: 1 }]), /que producto/);
rechazaForma('mitades del mismo sabor', venta([{ productoId: 2, mitadId: 2, cantidad: 1 }]), /mismo sabor/);
rechazaForma('un extra repetido', venta([{ productoId: 2, cantidad: 1, extras: [20, 20] }]), /repite/);
rechazaForma('extras que no son ids', venta([{ productoId: 2, cantidad: 1, extras: ['queso'] }]), /extras/);
rechazaForma('sin el total mostrado', venta(PIZZA, { totalEsperado: undefined }), /total/);
rechazaForma('total negativo', venta(PIZZA, { totalEsperado: -5 }), /total/);
rechazaForma('total con tres decimales', venta(PIZZA, { totalEsperado: 47.505 }), /total/);

// La venta directa: lo que no le corresponde se rechaza, no se ignora.
rechazaForma('venta directa con cliente', directa([{ productoId: 10, cantidad: 1 }], { cliente: { nombre: 'Ana' } }), /no lleva cliente/);
rechazaForma('venta directa para llevar', directa([{ productoId: 10, cantidad: 1 }], { paraLlevar: true }), /no lleva cliente/);
rechazaForma('venta directa para comer aqui', directa([{ productoId: 10, cantidad: 1 }], { paraLlevar: false }), /no lleva cliente/);
rechazaForma('venta directa con observacion', directa([{ productoId: 10, cantidad: 1 }], { observacion: 'sin hielo' }), /no lleva cliente/);
rechazaForma('venta directa sin lineas', directa([]), /al menos un producto/);
rechazaForma('venta directa sin el total', directa([{ productoId: 10, cantidad: 1 }], { totalEsperado: undefined }), /total/);
rechazaForma('ventaDirecta como texto', venta(PIZZA, { ventaDirecta: 'si' }), /verdadero o falso/);

// Lo que se agrega: solo lineas y el total que se mostro.
function rechazaAgregado(nombre, cuerpo, fragmento) {
  test(`rechaza lo agregado: ${nombre}`, () => {
    assert.throws(() => leerAgregado(cuerpo), (err) => {
      assert.ok(err instanceof VentaInvalida);
      assert.match(err.message, fragmento);
      return true;
    });
  });
}
rechazaAgregado('sin cuerpo', undefined, /nada para agregar/);
rechazaAgregado('sin lineas', { lineas: [], totalEsperado: 0 }, /al menos un producto/);
rechazaAgregado('cantidad 0', { lineas: [{ productoId: 10, cantidad: 0 }], totalEsperado: 0 }, /cantidad/);
rechazaAgregado('sin el total', { lineas: [{ productoId: 10, cantidad: 1 }] }, /total/);

// --- lo que se normaliza ---------------------------------------------------------------

test('normaliza: la venta directa queda sin cliente, sin para llevar y sin observacion', () => {
  const v = leerVenta(directa([{ productoId: 10, cantidad: 2 }], { totalEsperado: 36 }));
  assert.equal(v.ventaDirecta, true);
  assert.equal(v.cliente, null);
  assert.equal(v.paraLlevar, null);
  assert.equal(v.observacion, null);
  assert.equal(v.totalEsperadoCentavos, 3600);
  // Enviar esos campos en null es lo mismo que no enviarlos.
  assert.doesNotThrow(() => leerVenta(directa([{ productoId: 10, cantidad: 1 }], { cliente: null, paraLlevar: null })));
});

test('normaliza: celular y observacion vacios quedan como nulos; el nombre sin espacios', () => {
  const v = leerVenta(venta(PIZZA, {
    cliente: { nombre: '  Ana Prueba ', celular: '' }, observacion: '   ',
  }));
  assert.deepEqual(v.cliente, { nombre: 'Ana Prueba', celular: null });
  assert.equal(v.observacion, null);
});

test('normaliza: el total mostrado pasa a centavos exactos', () => {
  assert.equal(leerVenta(venta(PIZZA, { totalEsperado: 47.5 })).totalEsperadoCentavos, 4750);
  assert.equal(aCentavos('62.50'), 6250);
  // El ruido de la coma flotante no rechaza un total legitimo; un tercer decimal, si.
  assert.equal(aCentavos(0.1 + 0.2), 30);
  assert.equal(aCentavos(47.505), null);
});
