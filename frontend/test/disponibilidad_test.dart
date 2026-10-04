// La disponibilidad de los productos (RF-13, tarjeta 08): la carta que cambia en el lugar, sin
// reemplazarse (D-67), y la venta que no confirma con un producto que se agotó mientras se
// armaba (D-69). Lógica pura, sin pantalla.
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
final extraQueso = producto('Extra queso', 'extra', 8);
final gaseosa = producto('Gaseosa 2 L', 'bebida', 18);
final jugo = producto('Jugo natural 1 L', 'bebida', 15, disponible: false);

/// Una carta nueva en cada prueba: cambia en el lugar.
Carta cartaNueva() => Carta([salame, peperoni, extraQueso, gaseosa, jugo]);

void main() {
  group('la carta cambia en el lugar (D-67)', () {
    test('agotar un producto lo cambia en su lista, avisa una vez y dice que cambió', () {
      final carta = cartaNueva();
      var avisos = 0;
      carta.addListener(() => avisos++);
      expect(carta.marcarDisponibilidad(gaseosa.id, false), isTrue);
      expect(carta.bebidas.firstWhere((p) => p.id == gaseosa.id).disponible, isFalse);
      expect(carta.estaDisponible(gaseosa), isFalse, reason: 'el producto viejo se consulta en la carta');
      expect(avisos, 1);
    });

    test('un aviso repetido, o de un producto que no está, no cambia nada ni avisa', () {
      final carta = cartaNueva();
      var avisos = 0;
      carta.addListener(() => avisos++);
      expect(carta.marcarDisponibilidad(gaseosa.id, true), isFalse);
      expect(carta.marcarDisponibilidad(9999, false), isFalse);
      expect(avisos, 0);
    });

    test('reponer lo vuelve a ofrecer', () {
      final carta = cartaNueva();
      expect(carta.marcarDisponibilidad(jugo.id, true), isTrue);
      expect(carta.porId(jugo.id)!.disponible, isTrue);
    });

    test('la disponibilidad de una carta recién leída se aplica toda junta, con un solo aviso', () {
      final carta = cartaNueva();
      var avisos = 0;
      carta.addListener(() => avisos++);
      final leida = Carta([salame, peperoni.conDisponible(false), extraQueso.conDisponible(false), gaseosa, jugo]);
      carta.aplicarDisponibilidadDe(leida);
      expect(carta.estaDisponible(peperoni), isFalse);
      expect(carta.estaDisponible(extraQueso), isFalse);
      expect(carta.estaDisponible(salame), isTrue);
      expect(avisos, 1);
    });

    test('el producto cambia solo en su disponibilidad', () {
      final agotada = peperoni.conDisponible(false);
      expect((agotada.id, agotada.nombre, agotada.precio, agotada.categoria), (peperoni.id, 'Peperoni', 5000, Categoria.pizza));
      expect(agotada.disponible, isFalse);
    });
  });

  group('la venta en curso con un producto que se agota (D-69)', () {
    FormularioVenta ventaLista(Carta carta) => FormularioVenta(carta)
      ..escribirNombre('Ana Prueba')
      ..elegirParaLlevar(true)
      ..agregarPizza(PizzaElegida(sabor: salame, segundaMitad: peperoni, extras: [extraQueso]), 1)
      ..cambiarBebida(gaseosa, 2);

    test('la venta se vuelve a dibujar cuando la carta cambia, sin perder lo que tiene', () {
      final carta = cartaNueva();
      final venta = ventaLista(carta);
      var avisos = 0;
      venta.addListener(() => avisos++);
      carta.marcarDisponibilidad(gaseosa.id, false);
      expect(avisos, 1);
      expect((venta.nombre, venta.grupos.length, venta.cantidadDeBebida(gaseosa)), ('Ana Prueba', 1, 2));
    });

    test('lo agotado se lista, se señala y no deja confirmar, con lo que hay que quitar', () {
      final carta = cartaNueva();
      final venta = ventaLista(carta);
      carta
        ..marcarDisponibilidad(peperoni.id, false)
        ..marcarDisponibilidad(gaseosa.id, false);
      expect(venta.agotados.map((p) => p.nombre), ['Peperoni', 'Gaseosa 2 L']);
      expect(venta.estaAgotado(peperoni), isTrue);
      expect(venta.problemas, [
        'Peperoni se agotó: quítalo de la venta.',
        'Gaseosa 2 L se agotó: quítalo de la venta.',
      ]);
      expect(venta.aPedido, throwsA(isA<VentaInvalida>()));
    });

    test('un extra que se agota también cuenta', () {
      final carta = cartaNueva();
      final venta = ventaLista(carta);
      carta.marcarDisponibilidad(extraQueso.id, false);
      expect(venta.problemas, ['Extra queso se agotó: quítalo de la venta.']);
    });

    test('quitado lo agotado, la venta se confirma', () {
      final carta = cartaNueva();
      final venta = ventaLista(carta);
      carta.marcarDisponibilidad(gaseosa.id, false);
      venta.cambiarBebida(carta.porId(gaseosa.id)!, 0); // quitar se puede: no suma unidades
      expect(venta.problemas, isEmpty);
      expect(venta.aPedido()['lineas'], hasLength(1));
    });

    test('si se repone antes de confirmar, la venta vuelve a estar lista', () {
      final carta = cartaNueva();
      final venta = ventaLista(carta);
      carta.marcarDisponibilidad(gaseosa.id, false);
      expect(venta.problemas, isNotEmpty);
      carta.marcarDisponibilidad(gaseosa.id, true);
      expect(venta.problemas, isEmpty);
    });

    test('la venta deja de escuchar a la carta al cerrarse', () {
      final carta = cartaNueva();
      ventaLista(carta).dispose();
      expect(() => carta.marcarDisponibilidad(gaseosa.id, false), returnsNormally);
    });
  });

  group('las ventanas abiertas también se enteran', () {
    test('la pizza a medio armar: un sabor elegido que se agota no deja agregarla', () {
      final carta = cartaNueva();
      final armado = ArmadoDePizza(carta)..tocarSabor(peperoni);
      expect(armado.pizza, isNotNull);
      var avisos = 0;
      armado.addListener(() => avisos++);
      carta.marcarDisponibilidad(peperoni.id, false);
      expect(avisos, 1);
      expect(armado.falta, 'Peperoni se agotó: elige otro sabor');
      expect(armado.pizza, isNull);
    });

    test('un extra elegido que se agota pide quitarlo', () {
      final carta = cartaNueva();
      final armado = ArmadoDePizza(carta)
        ..tocarSabor(salame)
        ..alternarExtra(extraQueso);
      carta.marcarDisponibilidad(extraQueso.id, false);
      expect(armado.falta, 'Extra queso se agotó: quítalo');
    });

    test('la venta directa de bebidas no cobra una bebida que se agotó', () {
      final carta = cartaNueva();
      final venta = VentaDeBebidas(carta)..cambiar(gaseosa, 1);
      carta.marcarDisponibilidad(gaseosa.id, false);
      expect(
        venta.aVentaDirecta,
        throwsA(isA<VentaInvalida>().having((e) => e.mensaje, 'mensaje', 'Gaseosa 2 L se agotó: quítalo de la venta.')),
      );
    });

    test('lo que se agrega a un pedido tampoco', () {
      final carta = cartaNueva();
      final agregado = AgregadoAPedido(carta, permitePizzas: true)..agregarPizza(PizzaElegida(sabor: salame), 1);
      carta.marcarDisponibilidad(salame.id, false);
      expect(agregado.aCuerpo, throwsA(isA<VentaInvalida>()));
    });
  });
}
