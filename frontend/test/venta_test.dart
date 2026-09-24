// La regla de precio (D-27, D-28) y el recorrido de la venta (D-30), sin pantalla. La tabla
// de la sección 6 del plan 05 es la misma que prueba el servidor en la tarjeta 06.
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/carta/venta.dart';

var _id = 0;
Producto producto(String nombre, String categoria, num precio, {bool disponible = true}) =>
    Producto.desdeJson({
      'id': ++_id, 'nombre': nombre, 'categoria': categoria, 'precio': precio,
      'descripcion': null, 'imagen': null, 'disponible': disponible,
    });

final salame = producto('Salame', 'pizza', 45);
final peperoni = producto('Peperoni', 'pizza', 50);
final hawaiana = producto('Hawaiana', 'pizza', 50);
final choclo = producto('Choclo', 'pizza', 45);
final carnivora = producto('Carnívora', 'pizza', 60);
final criollaEspanola = producto('Criolla española', 'pizza', 65);
final agotada = producto('Cuatro quesos', 'pizza', 55, disponible: false);
final extraQueso = producto('Extra queso', 'extra', 8);
final extraChoclo = producto('Extra choclo', 'extra', 5);
final gaseosa = producto('Gaseosa 2 L', 'bebida', 18);

final carta = Carta([peperoni, salame, hawaiana, choclo, carnivora, criollaEspanola, agotada,
    extraQueso, extraChoclo, gaseosa]);

int bs(num n) => (n * 100).round();

/// Una pizza completa, de principio a fin, dentro de una tanda ya empezada.
void definir(RecorridoVenta r, Producto sabor, {Producto? mitad, List<Producto> extras = const []}) {
  r.elegirTipo(mitades: mitad != null);
  if (mitad == null) {
    r.elegirSabor(sabor);
  } else {
    r.elegirPrimeraMitad(sabor);
    r.elegirSegundaMitad(mitad);
  }
  r.confirmarExtras(extras);
}

/// De la observación al resumen: para llevar, a nombre de Ana Prueba (D-31, D-34).
void cerrarVenta(RecorridoVenta r, {bool paraLlevar = true, String nombre = 'Ana Prueba', String celular = ''}) {
  r
    ..continuarDeObservacion()
    ..elegirParaLlevar(paraLlevar)
    ..escribirNombre(nombre)
    ..escribirCelular(celular)
    ..continuarDeCliente();
}

void main() {
  group('la tabla de la sección 6', () {
    test('1 Peperoni = 50', () {
      expect(PizzaElegida(sabor: peperoni).precioUnitario, bs(50));
    });

    test('1 mitad Salame, mitad Peperoni = (45 + 50) / 2 = 47,50', () {
      final p = PizzaElegida(sabor: salame, segundaMitad: peperoni);
      expect(p.precioUnitario, bs(47.50));
      expect(formatoBs(p.precioUnitario), 'Bs 47,50');
    });

    test('1 mitad Carnívora, mitad Criolla española = (60 + 65) / 2 = 62,50', () {
      expect(PizzaElegida(sabor: carnivora, segundaMitad: criollaEspanola).precioUnitario, bs(62.50));
    });

    test('2 mitad Salame, mitad Peperoni = 95', () {
      expect(GrupoPizzas(PizzaElegida(sabor: salame, segundaMitad: peperoni), 2).subtotal, bs(95));
    });

    test('1 Hawaiana con extra queso = 50 + 8 = 58', () {
      expect(PizzaElegida(sabor: hawaiana, extras: [extraQueso]).precioUnitario, bs(58));
    });

    test('3 Choclo iguales con extra choclo = 3 × (45 + 5) = 150', () {
      expect(GrupoPizzas(PizzaElegida(sabor: choclo, extras: [extraChoclo]), 3).subtotal, bs(150));
    });

    test('solo 2 gaseosas = 36', () {
      final r = RecorridoVenta(carta)..soloBebidas()..cambiarBebida(gaseosa, 2);
      expect(r.estado.total, bs(36));
    });

    test('mitades del mismo sabor: rechazada', () {
      expect(() => PizzaElegida(sabor: salame, segundaMitad: salame), throwsA(isA<VentaInvalida>()));
    });

    test('la otra mitad no es una pizza: rechazada', () {
      expect(() => PizzaElegida(sabor: salame, segundaMitad: gaseosa), throwsA(isA<VentaInvalida>()));
    });

    test('un extra que no es extra: rechazado', () {
      expect(() => PizzaElegida(sabor: salame, extras: [gaseosa]), throwsA(isA<VentaInvalida>()));
    });

    test('una venta sin ningún producto está vacía', () {
      final r = RecorridoVenta(carta)..soloBebidas();
      expect(r.estado.vacia, isTrue);
    });
  });

  group('las pizzas son iguales si tienen los mismos sabores y extras', () {
    test('mitad A / mitad B es la misma pizza que mitad B / mitad A', () {
      expect(PizzaElegida(sabor: salame, segundaMitad: peperoni)
          .esIgualA(PizzaElegida(sabor: peperoni, segundaMitad: salame)), isTrue);
    });

    test('con distintos extras, son pizzas distintas', () {
      expect(PizzaElegida(sabor: salame).esIgualA(PizzaElegida(sabor: salame, extras: [extraQueso])), isFalse);
    });

    test('un extra repetido cuenta una vez', () {
      expect(PizzaElegida(sabor: salame, extras: [extraQueso, extraQueso]).precioUnitario, bs(53));
    });
  });

  group('el recorrido', () {
    test('una sola pizza no pregunta si son iguales, y termina en bebidas', () {
      final r = RecorridoVenta(carta)..elegirCantidad(1);
      expect(r.estado.paso, Paso.tipo);
      definir(r, peperoni);
      expect(r.estado.paso, Paso.bebidas);
      expect(r.estado.grupos.single.cantidad, 1);
    });

    test('20 iguales se definen una sola vez', () {
      final r = RecorridoVenta(carta)
        ..elegirCantidad(20)
        ..elegirIguales(true);
      definir(r, choclo, extras: [extraChoclo]);
      expect(r.estado.paso, Paso.bebidas);
      expect(r.estado.grupos.single.cantidad, 20);
      expect(r.estado.total, bs(20 * 50));
    });

    test('20 distintas en tres grupos, repitiendo la anterior: 8 Peperoni, 6 Hawaiana, 6 mitad y mitad', () {
      final r = RecorridoVenta(carta)
        ..elegirCantidad(20)
        ..elegirIguales(false);
      expect(r.puedeRepetirAnterior, isFalse, reason: 'la primera pizza no tiene anterior');
      definir(r, peperoni);
      expect(r.estado.paso, Paso.tipo, reason: 'confirmar agrega UNA pizza y pasa a la siguiente');
      expect(r.estado.pizzaActual, 2);
      expect(r.puedeRepetirAnterior, isTrue);
      for (var i = 0; i < 7; i++) {
        r.repetirAnterior();
      }
      expect(r.estado.pendientes, 12);
      expect(r.estado.pizzaActual, 9);
      definir(r, hawaiana);
      for (var i = 0; i < 5; i++) {
        r.repetirAnterior();
      }
      definir(r, salame, mitad: peperoni);
      for (var i = 0; i < 5; i++) {
        r.repetirAnterior();
      }
      expect(r.estado.paso, Paso.bebidas);
      expect(r.estado.unidadesDePizza, 20);
      expect(r.estado.grupos.map((g) => g.cantidad), [8, 6, 6]);
      expect(r.estado.total, bs(8 * 50 + 6 * 50 + 6 * 47.50));
    });

    test('repetir la anterior copia también sus extras', () {
      final r = RecorridoVenta(carta)
        ..elegirCantidad(2)
        ..elegirIguales(false);
      definir(r, hawaiana, extras: [extraQueso]);
      r.repetirAnterior();
      expect(r.estado.grupos.single.cantidad, 2);
      expect(r.estado.total, bs(2 * 58));
    });

    test('volver deshace una pizza repetida', () {
      final r = RecorridoVenta(carta)
        ..elegirCantidad(3)
        ..elegirIguales(false);
      definir(r, peperoni);
      r.repetirAnterior();
      expect(r.estado.unidadesDePizza, 2);
      r.volver();
      expect(r.estado.unidadesDePizza, 1);
      expect(r.estado.pizzaActual, 2);
    });

    test('en pizzas iguales o de una sola no se ofrece repetir', () {
      final iguales = RecorridoVenta(carta)
        ..elegirCantidad(3)
        ..elegirIguales(true);
      expect(iguales.puedeRepetirAnterior, isFalse);
      expect(iguales.pizzasQueConfirma, 3, reason: 'el botón confirma las tres');
      final una = RecorridoVenta(carta)..elegirCantidad(1);
      expect(una.puedeRepetirAnterior, isFalse);
      expect(() => una.repetirAnterior(), throwsA(isA<VentaInvalida>()));
    });

    test('la misma pizza armada dos veces se junta en una línea', () {
      final r = RecorridoVenta(carta)
        ..elegirCantidad(3)
        ..elegirIguales(false);
      definir(r, salame, mitad: peperoni);
      definir(r, peperoni, mitad: salame);
      r.repetirAnterior();
      expect(r.estado.grupos, hasLength(1));
      expect(r.estado.grupos.single.cantidad, 3);
    });

    test('la segunda mitad no ofrece el sabor de la primera', () {
      final r = RecorridoVenta(carta)
        ..elegirCantidad(1)
        ..elegirTipo(mitades: true)
        ..elegirPrimeraMitad(salame);
      expect(r.opcionesSegundaMitad, isNot(contains(salame)));
      expect(() => r.elegirSegundaMitad(salame), throwsA(isA<VentaInvalida>()));
    });

    test('una pizza agotada no se puede elegir, ni como mitad', () {
      final r = RecorridoVenta(carta)..elegirCantidad(1)..elegirTipo(mitades: false);
      expect(() => r.elegirSabor(agotada), throwsA(isA<VentaInvalida>()));
      r
        ..volver()
        ..elegirTipo(mitades: true);
      expect(() => r.elegirPrimeraMitad(agotada), throwsA(isA<VentaInvalida>()));
    });

    test('la cantidad va de 1 a 50', () {
      final r = RecorridoVenta(carta);
      expect(() => r.elegirCantidad(0), throwsA(isA<VentaInvalida>()));
      expect(() => r.elegirCantidad(51), throwsA(isA<VentaInvalida>()));
      r.elegirCantidad(50);
      expect(r.estado.pendientes, 50);
    });

    test('solo bebidas salta directo a las bebidas', () {
      final r = RecorridoVenta(carta)..soloBebidas();
      expect(r.estado.paso, Paso.bebidas);
      r
        ..cambiarBebida(gaseosa, 2)
        ..continuarDeBebidas()
        ..escribirObservacion('  bien frías  ');
      cerrarVenta(r);
      expect(r.estado.paso, Paso.resumen);
      expect(r.estado.observacion, 'bien frías');
      expect(r.estado.total, bs(36));
    });

    test('la observación admite hasta 240 caracteres, como la base', () {
      final r = RecorridoVenta(carta)..soloBebidas()..continuarDeBebidas();
      r.escribirObservacion('a' * 240);
      expect(() => r.escribirObservacion('a' * 241), throwsA(isA<VentaInvalida>()));
    });
  });

  group('volver', () {
    test('deshace exactamente el último paso, incluida una pizza recién agregada', () {
      final r = RecorridoVenta(carta)..elegirCantidad(1);
      definir(r, peperoni, extras: [extraQueso]);
      expect(r.estado.paso, Paso.bebidas);
      expect(r.estado.grupos, hasLength(1));
      r.volver();
      expect(r.estado.paso, Paso.extras);
      expect(r.estado.grupos, isEmpty, reason: 'la pizza vuelve a estar en armado');
      r.volver();
      expect(r.estado.paso, Paso.sabor);
      r.volver();
      expect(r.estado.paso, Paso.tipo);
      r.volver();
      expect(r.estado.paso, Paso.cantidad);
      expect(r.puedeVolver, isFalse);
    });

    test('tocar + diez veces en bebidas no son diez pasos atrás', () {
      final r = RecorridoVenta(carta)..soloBebidas();
      for (var i = 1; i <= 10; i++) {
        r.cambiarBebida(gaseosa, i);
      }
      r.volver();
      expect(r.estado.paso, Paso.cantidad);
    });

    test('en el resumen no se vuelve: se edita', () {
      final r = RecorridoVenta(carta)..soloBebidas()..cambiarBebida(gaseosa, 1)..continuarDeBebidas();
      cerrarVenta(r);
      expect(r.puedeVolver, isFalse);
    });
  });

  group('el resumen', () {
    RecorridoVenta hastaElResumen() {
      final r = RecorridoVenta(carta)..elegirCantidad(2)..elegirIguales(true);
      definir(r, peperoni);
      r
        ..cambiarBebida(gaseosa, 1)
        ..continuarDeBebidas();
      cerrarVenta(r);
      return r;
    }

    test('se cambia la cantidad de un grupo, y en cero se quita', () {
      final r = hastaElResumen();
      r.cambiarCantidadDeGrupo(0, 3);
      expect(r.estado.total, bs(3 * 50 + 18));
      r.cambiarCantidadDeGrupo(0, 0);
      expect(r.estado.grupos, isEmpty);
      expect(r.estado.total, bs(18));
    });

    test('agregar más pizzas suma a la misma venta, y volver regresa al resumen', () {
      final r = hastaElResumen()..agregarMasPizzas();
      expect(r.estado.paso, Paso.cantidad);
      r.volver();
      expect(r.estado.paso, Paso.resumen);
      r
        ..agregarMasPizzas()
        ..elegirCantidad(1);
      definir(r, salame, mitad: peperoni);
      r
        ..continuarDeBebidas()
        ..continuarDeObservacion();
      // El cliente ya estaba: vuelve directo al resumen, sin preguntarlo otra vez.
      expect(r.estado.paso, Paso.resumen);
      expect(r.estado.nombreCliente, 'Ana Prueba');
      expect(r.estado.unidadesDePizza, 3);
      expect(r.estado.total, bs(2 * 50 + 47.50 + 18));
    });

    test('cancelar deja la venta en blanco', () {
      final r = hastaElResumen()..cancelar();
      expect(r.estado.vacia, isTrue);
      expect(r.estado.paso, Paso.cantidad);
      expect(r.empezada, isFalse);
    });
  });

  group('para llevar y el cliente (D-31, D-34)', () {
    RecorridoVenta hastaLaObservacion() => RecorridoVenta(carta)
      ..soloBebidas()
      ..cambiarBebida(gaseosa, 1)
      ..continuarDeBebidas();

    test('después de la observación: para llevar, el cliente y recién el resumen', () {
      final r = hastaLaObservacion()..continuarDeObservacion();
      expect(r.estado.paso, Paso.llevar);
      r.elegirParaLlevar(false);
      expect(r.estado.paso, Paso.cliente);
      expect(r.estado.paraLlevar, isFalse);
      r
        ..escribirNombre('  Ana Prueba ')
        ..escribirCelular(' 70000001 ')
        ..continuarDeCliente();
      expect(r.estado.paso, Paso.resumen);
      expect(r.estado.nombreCliente, 'Ana Prueba');
      expect(r.estado.celular, '70000001');
    });

    test('el nombre es obligatorio', () {
      final r = hastaLaObservacion()..continuarDeObservacion()..elegirParaLlevar(true);
      expect(r.problemaDelCliente, 'Escribe el nombre del cliente.');
      expect(r.continuarDeCliente, throwsA(isA<VentaInvalida>()));
      r.escribirNombre('   ');
      expect(r.continuarDeCliente, throwsA(isA<VentaInvalida>()));
      expect(r.estado.paso, Paso.cliente);
    });

    test('el celular es opcional, pero si se escribe tiene que ser boliviano', () {
      final r = hastaLaObservacion()..continuarDeObservacion()..elegirParaLlevar(true)..escribirNombre('Ana Prueba');
      for (final malo in ['7000001', '700000011', '50000001', '7000 001']) {
        r.escribirCelular(malo);
        expect(r.problemaDelCliente, 'El celular tiene 8 dígitos y empieza con 6 o 7.', reason: malo);
      }
      for (final bueno in ['', '70000001', '60000002']) {
        r.escribirCelular(bueno);
        expect(r.problemaDelCliente, isNull, reason: bueno);
      }
    });

    test('el nombre admite hasta 120 caracteres, como la base', () {
      final r = hastaLaObservacion()..continuarDeObservacion()..elegirParaLlevar(true);
      r.escribirNombre('a' * 120);
      expect(() => r.escribirNombre('a' * 121), throwsA(isA<VentaInvalida>()));
    });

    test('volver desde el cliente regresa a para llevar, y de ahí a la observación', () {
      final r = hastaLaObservacion()..continuarDeObservacion()..elegirParaLlevar(true);
      r.volver();
      expect(r.estado.paso, Paso.llevar);
      r.volver();
      expect(r.estado.paso, Paso.observacion);
    });

    test('desde el resumen se cambia el cliente con lo ya escrito', () {
      final r = hastaLaObservacion();
      cerrarVenta(r, celular: '70000001');
      r.cambiarCliente();
      expect(r.estado.paso, Paso.llevar);
      r.elegirParaLlevar(false);
      expect(r.estado.nombreCliente, 'Ana Prueba', reason: 'no se vuelve a escribir');
      r.continuarDeCliente();
      expect(r.estado.paso, Paso.resumen);
      expect(r.estado.paraLlevar, isFalse);
    });

    test('cambiar la observación desde el resumen vuelve directo al resumen', () {
      final r = hastaLaObservacion();
      cerrarVenta(r);
      r
        ..cambiarObservacion()
        ..escribirObservacion('sin hielo')
        ..continuarDeObservacion();
      expect(r.estado.paso, Paso.resumen);
      expect(r.estado.observacion, 'sin hielo');
    });
  });

  group('el pedido que se envía (POST /api/v1/pedidos)', () {
    test('las pizzas con su segunda mitad y sus extras, las bebidas y el total en bolivianos', () {
      final r = RecorridoVenta(carta)..elegirCantidad(3)..elegirIguales(false);
      definir(r, salame, mitad: peperoni); // 47,50
      r.repetirAnterior(); // 47,50
      definir(r, hawaiana, extras: [extraChoclo, extraQueso]); // 63
      r
        ..cambiarBebida(gaseosa, 2) // 36
        ..continuarDeBebidas()
        ..escribirObservacion(' sin cebolla ');
      cerrarVenta(r, celular: '70000001');
      expect(r.estado.aPedido(), {
        'paraLlevar': true,
        'cliente': {'nombre': 'Ana Prueba', 'celular': '70000001'},
        'observacion': 'sin cebolla',
        'lineas': [
          {'productoId': salame.id, 'mitadId': peperoni.id, 'cantidad': 2},
          {'productoId': hawaiana.id, 'cantidad': 1, 'extras': [extraQueso.id, extraChoclo.id]..sort()},
          {'productoId': gaseosa.id, 'cantidad': 2},
        ],
        'totalEsperado': 194.0,
      });
    });

    test('sin celular ni observación viajan como nulos; el total conserva los centavos', () {
      final r = RecorridoVenta(carta)..elegirCantidad(1);
      definir(r, salame, mitad: peperoni);
      r.continuarDeBebidas();
      cerrarVenta(r, paraLlevar: false);
      final pedido = r.estado.aPedido();
      expect(pedido['cliente'], {'nombre': 'Ana Prueba', 'celular': null});
      expect(pedido['observacion'], isNull);
      expect(pedido['paraLlevar'], isFalse);
      expect(pedido['totalEsperado'], 47.5);
    });
  });

  group('la carta', () {
    test('separa pizzas, extras y bebidas, en orden alfabético sin mirar tildes', () {
      expect(carta.pizzas.map((p) => p.nombre),
          ['Carnívora', 'Choclo', 'Criolla española', 'Cuatro quesos', 'Hawaiana', 'Peperoni', 'Salame']);
      expect(carta.extras.map((p) => p.nombre), ['Extra choclo', 'Extra queso']);
      expect(carta.bebidas.single, gaseosa);
    });

    test('sin extras disponibles, el paso de extras no aparece', () {
      final r = RecorridoVenta(Carta([peperoni, gaseosa]))..elegirCantidad(1)..elegirTipo(mitades: false)..elegirSabor(peperoni);
      expect(r.estado.paso, Paso.bebidas);
      r.volver();
      expect(r.estado.paso, Paso.sabor);
    });

    test('una categoría desconocida se rechaza al leer la carta', () {
      expect(() => producto('Combo', 'combo', 10), throwsFormatException);
    });

    test('la imagen solo se busca con un nombre simple, junto a la app', () {
      Producto con(String? imagen) => Producto.desdeJson({'id': 1, 'nombre': 'x', 'categoria': 'bebida',
          'precio': 1, 'descripcion': null, 'imagen': imagen, 'disponible': true});
      expect(rutaDeImagen(con('gaseosa.png')), 'carta/gaseosa.png');
      expect(rutaDeImagen(con(null)), isNull);
      expect(rutaDeImagen(con('https://otro.sitio/x.png')), isNull);
      expect(rutaDeImagen(con('../secreto.png')), isNull);
    });
  });
}
