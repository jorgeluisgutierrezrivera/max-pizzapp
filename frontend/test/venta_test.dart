// La regla de precio (D-27, D-28) y la venta en un solo formulario (D-36), sin pantalla: el
// formulario, la pizza que se arma en el modal y la venta directa de bebidas (D-38). La
// tabla de la sección 6 del plan 05 es la misma que prueba el servidor.
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/carta/venta.dart';

var _id = 0;
Producto producto(String nombre, String categoria, num precio, {bool disponible = true}) => Producto.desdeJson({
  'id': ++_id,
  'nombre': nombre,
  'categoria': categoria,
  'precio': precio,
  'descripcion': null,
  'imagen': null,
  'disponible': disponible,
});

final salame = producto('Salame', 'pizza', 45);
final peperoni = producto('Peperoni', 'pizza', 50);
final hawaiana = producto('Hawaiana', 'pizza', 50);
final choclo = producto('Choclo', 'pizza', 45);
final carnivora = producto('Carnívora', 'pizza', 60);
final criollaEspanola = Producto.desdeJson({
  'id': ++_id,
  'nombre': 'Criolla española',
  'categoria': 'pizza',
  'precio': 65,
  'descripcion': null,
  'imagen': null,
  'disponible': true,
  'soloEntera': true,
});
final agotada = producto('Cuatro quesos', 'pizza', 55, disponible: false);
final extraQueso = producto('Extra queso', 'extra', 8);
final extraChoclo = producto('Extra choclo', 'extra', 5);
final extraAgotado = producto('Extra jamón', 'extra', 8, disponible: false);
final gaseosa = producto('Gaseosa 2 L', 'bebida', 18);
final agua = producto('Agua mineral 600 ml', 'bebida', 6);
final jugoAgotado = producto('Jugo natural 1 L', 'bebida', 15, disponible: false);

final carta = Carta([
  peperoni,
  salame,
  hawaiana,
  choclo,
  carnivora,
  criollaEspanola,
  agotada,
  extraQueso,
  extraChoclo,
  extraAgotado,
  gaseosa,
  agua,
  jugoAgotado,
]);

int bs(num n) => (n * 100).round();

PizzaElegida pizza(Producto sabor, {Producto? mitad, List<Producto> extras = const []}) =>
    PizzaElegida(sabor: sabor, segundaMitad: mitad, extras: extras);

/// Un formulario con el cliente completo, listo para sumarle productos.
FormularioVenta conCliente({bool paraLlevar = true, String nombre = 'Ana Prueba', String celular = ''}) =>
    FormularioVenta(carta)
      ..escribirNombre(nombre)
      ..escribirCelular(celular)
      ..elegirParaLlevar(paraLlevar);

void main() {
  group('la tabla de la sección 6', () {
    int total(FormularioVenta f) => f.total;

    test('1 Peperoni = 50', () {
      expect(total(conCliente()..agregarPizza(pizza(peperoni), 1)), bs(50));
    });

    test('1 mitad Salame, mitad Peperoni = (45 + 50) / 2 = 47,50', () {
      final p = pizza(salame, mitad: peperoni);
      expect(p.precioUnitario, bs(47.5));
      expect(p.titulo, 'Mitad Salame / mitad Peperoni');
    });

    // La tabla del plan 05 usaba Carnívora con Criolla española (62,50); la Criolla se vende
    // solo entera (D-39), y la mitad y mitad que termina en 50 centavos se prueba con Salame y Hawaiana.
    test('1 mitad Salame, mitad Hawaiana = (45 + 50) / 2 = 47,50', () {
      expect(pizza(salame, mitad: hawaiana).precioUnitario, bs(47.5));
    });

    test('Criolla española se vende solo entera: ni como mitad ni con otra mitad (D-39)', () {
      expect(() => pizza(carnivora, mitad: criollaEspanola), throwsA(isA<VentaInvalida>()));
      expect(() => pizza(criollaEspanola, mitad: carnivora), throwsA(isA<VentaInvalida>()));
      expect(pizza(criollaEspanola).precioUnitario, bs(65));
    });

    test('2 mitad Salame, mitad Peperoni = 95', () {
      expect(total(conCliente()..agregarPizza(pizza(salame, mitad: peperoni), 2)), bs(95));
    });

    test('1 Hawaiana con extra queso = 50 + 8 = 58', () {
      expect(pizza(hawaiana, extras: [extraQueso]).precioUnitario, bs(58));
    });

    test('3 Choclo iguales con extra choclo = 3 × (45 + 5) = 150', () {
      expect(total(conCliente()..agregarPizza(pizza(choclo, extras: [extraChoclo]), 3)), bs(150));
    });

    test('venta directa de 2 gaseosas = 36', () {
      expect((VentaDeBebidas(carta)..cambiar(gaseosa, 2)).total, bs(36));
    });

    test('mitades del mismo sabor: rechazada', () {
      expect(() => pizza(salame, mitad: salame), throwsA(isA<VentaInvalida>()));
    });

    test('la otra mitad no es una pizza: rechazada', () {
      expect(() => pizza(salame, mitad: gaseosa), throwsA(isA<VentaInvalida>()));
    });

    test('un extra que no es extra: rechazado', () {
      expect(() => pizza(salame, extras: [gaseosa]), throwsA(isA<VentaInvalida>()));
    });
  });

  group('las pizzas son iguales si tienen los mismos sabores y extras', () {
    test('mitad A / mitad B es la misma pizza que mitad B / mitad A', () {
      expect(pizza(salame, mitad: peperoni).esIgualA(pizza(peperoni, mitad: salame)), isTrue);
    });

    test('con distintos extras, son pizzas distintas', () {
      expect(pizza(salame, extras: [extraQueso]).esIgualA(pizza(salame)), isFalse);
    });

    test('un extra repetido cuenta una vez', () {
      expect(pizza(salame, extras: [extraQueso, extraQueso]).extras, [extraQueso]);
    });
  });

  group('el formulario (D-36)', () {
    test('empieza vacío y sin "para llevar" elegido: no hay una opción marcada de entrada', () {
      final f = FormularioVenta(carta);
      expect(f.vacia, isTrue);
      expect(f.paraLlevar, isNull);
      expect(f.total, 0);
    });

    test('la misma pizza agregada dos veces se junta en una línea, en cualquier orden de mitades', () {
      final f = conCliente()
        ..agregarPizza(pizza(salame, mitad: peperoni), 2)
        ..agregarPizza(pizza(peperoni, mitad: salame), 1);
      expect(f.grupos.single.cantidad, 3);
      expect(f.total, bs(47.5 * 3));
    });

    test('20 pizzas distintas en tres líneas: 8 Peperoni, 6 Hawaiana y 6 mitad y mitad', () {
      final f = conCliente()
        ..agregarPizza(pizza(peperoni), 8)
        ..agregarPizza(pizza(hawaiana), 6)
        ..agregarPizza(pizza(salame, mitad: choclo), 6);
      expect(f.grupos.map((g) => (g.pizza.titulo, g.cantidad)), [
        ('Peperoni', 8),
        ('Hawaiana', 6),
        ('Mitad Salame / mitad Choclo', 6),
      ]);
      expect(f.unidadesDePizza, 20);
      expect(f.total, bs(8 * 50 + 6 * 50 + 6 * 45));
    });

    test('− y + cambian la cantidad de una línea, y en cero la línea sale', () {
      final f = conCliente()
        ..agregarPizza(pizza(peperoni), 2)
        ..agregarPizza(pizza(salame), 1)
        ..cambiarCantidadDeGrupo(0, 5);
      expect(f.grupos.first.cantidad, 5);
      f.cambiarCantidadDeGrupo(1, 0);
      expect(f.grupos.map((g) => g.pizza.sabor), [peperoni]);
    });

    test('corregir una pizza la reemplaza en su lugar, y si quedó igual a otra, se juntan', () {
      final f = conCliente()
        ..agregarPizza(pizza(peperoni), 1)
        ..agregarPizza(pizza(salame), 2)
        ..agregarPizza(pizza(choclo), 1)
        ..reemplazarPizza(1, pizza(salame, extras: [extraQueso]), 2);
      expect(f.grupos.map((g) => g.pizza.titulo), ['Peperoni', 'Salame', 'Choclo']);
      expect(f.grupos[1].pizza.extras, [extraQueso]);
      f.reemplazarPizza(2, pizza(peperoni), 3);
      expect(f.grupos.map((g) => (g.pizza.titulo, g.cantidad)), [('Peperoni', 4), ('Salame', 2)]);
    });

    test('quitar una pizza', () {
      final f = conCliente()
        ..agregarPizza(pizza(peperoni), 1)
        ..agregarPizza(pizza(salame), 1)
        ..quitarPizza(0);
      expect(f.grupos.single.pizza.sabor, salame);
    });

    test('una línea admite hasta 999 unidades, como la base', () {
      final f = conCliente()..agregarPizza(pizza(peperoni), 999);
      expect(() => f.agregarPizza(pizza(peperoni), 1), throwsA(isA<VentaInvalida>()));
      expect(() => f.cambiarCantidadDeGrupo(0, 1000), throwsA(isA<VentaInvalida>()));
    });

    test('las bebidas se suman con + y −, y en cero salen', () {
      final f = conCliente()
        ..cambiarBebida(gaseosa, 2)
        ..cambiarBebida(agua, 1);
      expect(f.total, bs(2 * 18 + 6));
      f.cambiarBebida(gaseosa, 0);
      expect(f.bebidas.single.bebida, agua);
    });

    test('una bebida agotada no se suma, pero la que ya estaba se puede bajar', () {
      final f = conCliente();
      expect(() => f.cambiarBebida(jugoAgotado, 1), throwsA(isA<VentaInvalida>()));
      expect(() => f.cambiarBebida(peperoni, 1), throwsA(isA<VentaInvalida>()));
    });

    test('el nombre admite hasta 120 caracteres y la observación hasta 240, como la base', () {
      final f = FormularioVenta(carta);
      expect(() => f.escribirNombre('a' * 121), throwsA(isA<VentaInvalida>()));
      expect(() => f.escribirObservacion('a' * 241), throwsA(isA<VentaInvalida>()));
      f.escribirObservacion('a' * 240);
      expect(f.observacion.length, 240);
    });

    test('limpiar deja el formulario en blanco, sin "para llevar" elegido', () {
      final f = conCliente(celular: '70000001')
        ..agregarPizza(pizza(peperoni), 1)
        ..cambiarBebida(gaseosa, 1)
        ..escribirObservacion('sin cebolla')
        ..limpiar();
      expect(f.vacia, isTrue);
      expect(f.paraLlevar, isNull);
      expect(f.nombre, '');
      expect(f.celular, '');
      expect(f.total, 0);
    });

    test('avisa a quien escucha en cada cambio', () {
      final f = FormularioVenta(carta);
      var avisos = 0;
      f.addListener(() => avisos++);
      f
        ..escribirNombre('Ana')
        ..elegirParaLlevar(false)
        ..agregarPizza(pizza(peperoni), 1)
        ..cambiarBebida(gaseosa, 1)
        ..escribirObservacion('x');
      expect(avisos, 5);
    });
  });

  group('lo que falta para confirmar (las mismas reglas que el servidor)', () {
    test('vacío: el nombre, para llevar o no, y una pizza, en el orden del formulario', () {
      expect(FormularioVenta(carta).problemas, [
        'Escribe el nombre del cliente.',
        'Elige si es para comer aquí o para llevar.',
        'Agrega al menos una pizza.',
      ]);
    });

    test('completo: nada', () {
      expect((conCliente()..agregarPizza(pizza(peperoni), 1)).problemas, isEmpty);
    });

    test('un nombre de puros espacios no cuenta', () {
      final f = conCliente(nombre: '   ')..agregarPizza(pizza(peperoni), 1);
      expect(f.problemas, ['Escribe el nombre del cliente.']);
    });

    test('el celular es opcional, pero si se escribe tiene que ser boliviano', () {
      for (final malo in ['7000001', '50000001', '700000011']) {
        final f = conCliente(celular: malo)..agregarPizza(pizza(peperoni), 1);
        expect(f.problemas, ['El celular tiene 8 dígitos y empieza con 6 o 7.'], reason: malo);
      }
      for (final bueno in ['', '70000001', '60000001']) {
        expect((conCliente(celular: bueno)..agregarPizza(pizza(peperoni), 1)).problemas, isEmpty, reason: bueno);
      }
    });

    test('solo bebidas no es un pedido: se venden con "Vender bebidas" (D-38)', () {
      final f = conCliente()..cambiarBebida(gaseosa, 2);
      expect(f.problemas, ['Agrega al menos una pizza. Las bebidas solas se venden con «Vender bebidas».']);
      expect(f.aPedido, throwsA(isA<VentaInvalida>()));
    });
  });

  group('el pedido que se envía (POST /api/v1/pedidos)', () {
    test('las pizzas con su segunda mitad y sus extras, las bebidas y el total en bolivianos', () {
      final f = conCliente(celular: ' 70000001 ', nombre: '  Ana Prueba ')
        ..agregarPizza(pizza(salame, mitad: peperoni), 2)
        ..agregarPizza(pizza(hawaiana, extras: [extraQueso]), 1)
        ..cambiarBebida(gaseosa, 2)
        ..escribirObservacion('  sin cebolla ');
      expect(f.aPedido(), {
        'paraLlevar': true,
        'cliente': {'nombre': 'Ana Prueba', 'celular': '70000001'},
        'observacion': 'sin cebolla',
        'lineas': [
          {'productoId': salame.id, 'mitadId': peperoni.id, 'cantidad': 2},
          {
            'productoId': hawaiana.id,
            'cantidad': 1,
            'extras': [extraQueso.id],
          },
          {'productoId': gaseosa.id, 'cantidad': 2},
        ],
        'totalEsperado': 189,
      });
    });

    test('sin celular ni observación viajan como nulos; el total conserva los centavos', () {
      final f = conCliente(paraLlevar: false)..agregarPizza(pizza(salame, mitad: peperoni), 1);
      final pedido = f.aPedido();
      expect(pedido['paraLlevar'], false);
      expect(pedido['cliente'], {'nombre': 'Ana Prueba', 'celular': null});
      expect(pedido['observacion'], isNull);
      expect(pedido['totalEsperado'], 47.5);
    });
  });

  group('la pizza del modal (ArmadoDePizza)', () {
    test('empieza entera y sin sabor: falta elegirlo y no hay precio', () {
      final a = ArmadoDePizza(carta);
      expect(a.mitades, isFalse);
      expect(a.falta, 'Elige el sabor');
      expect(a.pizza, isNull);
      expect(a.subtotal, isNull);
    });

    test('entera: el sabor tocado es el sabor, y tocar otro lo cambia', () {
      final a = ArmadoDePizza(carta)..tocarSabor(salame);
      expect(a.pizza!.titulo, 'Salame');
      a.tocarSabor(peperoni);
      expect(a.pizza!.titulo, 'Peperoni');
      expect(a.lugarDe(peperoni), 1);
      expect(a.lugarDe(salame), isNull);
    });

    test('mitad y mitad: el primero que se toca es la primera mitad y el segundo, la segunda', () {
      final a = ArmadoDePizza(carta)..elegirMitades(true);
      expect(a.falta, 'Elige los dos sabores');
      a.tocarSabor(salame);
      expect(a.falta, 'Elige la segunda mitad');
      a.tocarSabor(peperoni);
      expect(a.falta, isNull);
      expect(a.pizza!.titulo, 'Mitad Salame / mitad Peperoni');
      expect((a.lugarDe(salame), a.lugarDe(peperoni)), (1, 2));
      expect(a.subtotal, bs(47.5));
    });

    test('tocar una mitad elegida la quita; la segunda pasa a ser la primera', () {
      final a = ArmadoDePizza(carta)
        ..elegirMitades(true)
        ..tocarSabor(salame)
        ..tocarSabor(peperoni)
        ..tocarSabor(salame);
      expect((a.primera, a.segunda), (peperoni, null));
      a.tocarSabor(peperoni);
      expect((a.primera, a.segunda), (null, null));
    });

    test('con las dos mitades elegidas, un tercer sabor reemplaza a la segunda', () {
      final a = ArmadoDePizza(carta)
        ..elegirMitades(true)
        ..tocarSabor(salame)
        ..tocarSabor(peperoni)
        ..tocarSabor(choclo);
      expect(a.pizza!.titulo, 'Mitad Salame / mitad Choclo');
    });

    test('en mitad y mitad, una pizza solo entera no se elige; y al pasar a mitades se suelta (D-39)', () {
      final a = ArmadoDePizza(carta)..elegirMitades(true);
      expect(a.sePuedeElegir(criollaEspanola), isFalse);
      expect(() => a.tocarSabor(criollaEspanola), throwsA(isA<VentaInvalida>()));
      final entera = ArmadoDePizza(carta)..tocarSabor(criollaEspanola);
      expect(entera.pizza!.titulo, 'Criolla española');
      entera.elegirMitades(true);
      expect(entera.primera, isNull);
      expect(entera.falta, 'Elige los dos sabores');
    });

    test('pasar de mitad y mitad a entera se queda con el primer sabor', () {
      final a = ArmadoDePizza(carta)
        ..elegirMitades(true)
        ..tocarSabor(salame)
        ..tocarSabor(peperoni)
        ..elegirMitades(false);
      expect(a.pizza!.titulo, 'Salame');
      a.elegirMitades(true);
      expect(a.falta, 'Elige la segunda mitad', reason: 'la segunda no vuelve sola');
    });

    test('los extras se marcan y se desmarcan, y el precio es el de todas las que se agregan', () {
      final a = ArmadoDePizza(carta)
        ..tocarSabor(hawaiana)
        ..alternarExtra(extraQueso)
        ..alternarExtra(extraChoclo)
        ..alternarExtra(extraChoclo)
        ..cambiarCantidad(3);
      expect(a.pizza!.extras, [extraQueso]);
      expect(a.subtotal, bs(3 * 58));
    });

    test('una pizza o un extra agotados no se eligen', () {
      final a = ArmadoDePizza(carta);
      expect(() => a.tocarSabor(agotada), throwsA(isA<VentaInvalida>()));
      expect(() => a.tocarSabor(gaseosa), throwsA(isA<VentaInvalida>()));
      expect(() => a.alternarExtra(extraAgotado), throwsA(isA<VentaInvalida>()));
    });

    test('la cantidad va de 1 a 50: solo ataja un error de tipeo', () {
      final a = ArmadoDePizza(carta);
      expect(() => a.cambiarCantidad(0), throwsA(isA<VentaInvalida>()));
      expect(() => a.cambiarCantidad(51), throwsA(isA<VentaInvalida>()));
      a.cambiarCantidad(50);
      expect(a.cantidad, 50);
    });

    test('para corregir, empieza con la pizza de la línea y su cantidad', () {
      final a = ArmadoDePizza(
        carta,
        desde: pizza(salame, mitad: choclo, extras: [extraQueso]),
        cantidad: 4,
      );
      expect(a.mitades, isTrue);
      expect((a.primera, a.segunda), (salame, choclo));
      expect(a.extras, {extraQueso});
      expect(a.cantidad, 4);
    });
  });

  group('la venta directa de bebidas (D-38)', () {
    test('sin cliente, sin "para llevar" y sin observación', () {
      final v = VentaDeBebidas(carta)
        ..cambiar(gaseosa, 2)
        ..cambiar(agua, 1);
      expect(v.aVentaDirecta(), {
        'ventaDirecta': true,
        'lineas': [
          {'productoId': gaseosa.id, 'cantidad': 2},
          {'productoId': agua.id, 'cantidad': 1},
        ],
        'totalEsperado': 42,
      });
    });

    test('vacía no se puede cobrar', () {
      expect(VentaDeBebidas(carta).aVentaDirecta, throwsA(isA<VentaInvalida>()));
    });

    test('solo bebidas: ni pizzas ni agotadas', () {
      final v = VentaDeBebidas(carta);
      expect(() => v.cambiar(peperoni, 1), throwsA(isA<VentaInvalida>()));
      expect(() => v.cambiar(jugoAgotado, 1), throwsA(isA<VentaInvalida>()));
    });
  });

  group('la carta', () {
    test('separa pizzas, extras y bebidas, en orden alfabético sin mirar tildes', () {
      expect(carta.pizzas.map((p) => p.nombre), [
        'Carnívora',
        'Choclo',
        'Criolla española',
        'Cuatro quesos',
        'Hawaiana',
        'Peperoni',
        'Salame',
      ]);
      expect(carta.extras.map((p) => p.nombre), ['Extra choclo', 'Extra jamón', 'Extra queso']);
      expect(carta.bebidas.map((p) => p.nombre), ['Agua mineral 600 ml', 'Gaseosa 2 L', 'Jugo natural 1 L']);
    });

    test('una categoría desconocida se rechaza al leer la carta', () {
      expect(() => producto('Combo', 'combo', 10), throwsFormatException);
    });

    test('la imagen solo se busca con un nombre simple, junto a la app', () {
      Producto con(String? imagen) => Producto.desdeJson({
        'id': 1,
        'nombre': 'x',
        'categoria': 'bebida',
        'precio': 1,
        'descripcion': null,
        'imagen': imagen,
        'disponible': true,
      });
      expect(rutaDeImagen(con('gaseosa.png')), 'carta/gaseosa.png');
      expect(rutaDeImagen(con(null)), isNull);
      expect(rutaDeImagen(con('https://otro.sitio/x.png')), isNull);
      expect(rutaDeImagen(con('../secreto.png')), isNull);
    });
  });
}
