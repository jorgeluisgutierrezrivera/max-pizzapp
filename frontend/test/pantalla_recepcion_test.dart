// La venta guiada en pantalla (D-30): ventas completas tocando botones, como la vendedora.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/carta/venta.dart';
import 'package:maxpizzapp/pantallas/pantalla_recepcion.dart';
import 'package:maxpizzapp/pantallas/venta/pasos.dart';
import 'package:maxpizzapp/tema.dart';

var _id = 0;
Producto producto(String nombre, String categoria, num precio, {bool disponible = true, String? descripcion}) =>
    Producto.desdeJson({
      'id': ++_id, 'nombre': nombre, 'categoria': categoria, 'precio': precio,
      'descripcion': descripcion, 'imagen': null, 'disponible': disponible,
    });

final carta = Carta([
  producto('Salame', 'pizza', 45, descripcion: 'Doble queso y salame'),
  producto('Peperoni', 'pizza', 50, descripcion: 'Doble queso, jamón y peperoni'),
  producto('Choclo', 'pizza', 45),
  producto('Hawaiana', 'pizza', 50),
  producto('Cuatro quesos', 'pizza', 55, disponible: false),
  producto('Extra choclo', 'extra', 5),
  producto('Extra queso', 'extra', 8),
  producto('Gaseosa 2 L', 'bebida', 18),
  producto('Agua mineral 600 ml', 'bebida', 6),
]);

final usuario = Usuario.desdeJson(
    {'sub': 'x', 'nombre': 'Ana Prueba', 'usuario': 'recepcion.demo', 'roles': ['recepcion']});

Widget app(Future<Carta> Function() cargar, {void Function(EstadoVenta)? alTerminar}) => MaterialApp(
      theme: temaMaxPizzas(),
      home: PantallaRecepcion(
        usuario: usuario,
        alCerrarSesion: () {},
        cargarCarta: cargar,
        imagen: (ruta, respaldo, ajuste) => respaldo,
        alTerminarVenta: alTerminar,
      ),
    );

void tamano(WidgetTester t, double ancho, double alto) {
  t.view.physicalSize = Size(ancho, alto);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// El texto de un widget por su clave, sea un Text o algo que lo contiene (una etiqueta).
String texto(WidgetTester t, String clave) {
  final f = find.byKey(Key(clave));
  final w = t.widget(f);
  if (w is Text) return w.data!;
  return t.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data!;
}

Future<void> tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> tocarTexto(WidgetTester t, String s) => tocar(t, find.text(s));
/// La grilla construye solo lo visible: en una pantalla angosta hay que desplazarse hasta
/// el sabor, como lo haría la vendedora.
Future<void> tocarSabor(WidgetTester t, String nombre) async {
  final sabor = find.widgetWithText(TarjetaSabor, nombre);
  await t.scrollUntilVisible(sabor, 150,
      scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
  await tocar(t, sabor);
}

Future<void> empezar(WidgetTester t, {double ancho = 1400, double alto = 1400}) async {
  tamano(t, ancho, alto);
  await t.pumpWidget(app(() async => carta));
  await t.pumpAndSettle();
}

Future<void> escribirCantidad(WidgetTester t, int n) async {
  await t.enterText(find.byKey(const Key('cantidad-texto')), '$n');
  await tocarTexto(t, 'Continuar');
}

void main() {
  group('los cuatro estados', () {
    testWidgets('cargando', (t) async {
      final pendiente = Completer<Carta>();
      await t.pumpWidget(app(() => pendiente.future));
      expect(find.text('Cargando la carta…'), findsOneWidget);
      pendiente.complete(carta);
      await t.pumpAndSettle();
      expect(find.text('¿Cuántas pizzas?'), findsOneWidget);
    });

    testWidgets('error: el mensaje del servidor, y reintentar vuelve a pedir', (t) async {
      var intentos = 0;
      await t.pumpWidget(app(() async {
        intentos++;
        if (intentos == 1) throw const ErrorApi(503, 'BASE_NO_DISPONIBLE', 'No se pueden leer los datos en este momento.');
        return carta;
      }));
      await t.pumpAndSettle();
      expect(find.text('No se pueden leer los datos en este momento.'), findsOneWidget);
      await tocarTexto(t, 'Reintentar');
      expect(intentos, 2);
      expect(find.text('¿Cuántas pizzas?'), findsOneWidget);
    });

    testWidgets('carta vacía: lo dice, en vez de una pantalla en blanco', (t) async {
      await t.pumpWidget(app(() async => Carta(const [])));
      await t.pumpAndSettle();
      expect(find.text('La carta todavía no tiene productos.'), findsOneWidget);
    });
  });

  group('ventas completas', () {
    testWidgets('una mitad y mitad con una gaseosa: (45 + 50) / 2 + 18 = Bs 65,50', (t) async {
      await empezar(t);
      await tocarTexto(t, 'Continuar'); // 1 pizza: no pregunta si son iguales
      expect(find.text('¿Un solo sabor o mitad y mitad?'), findsOneWidget);
      await tocarTexto(t, 'Mitad y mitad');
      final salame = find.widgetWithText(TarjetaSabor, 'Salame');
      expect(find.descendant(of: salame, matching: find.text('Bs 22,50')), findsOneWidget,
          reason: 'cada sabor muestra el precio de su mitad');
      expect(find.descendant(of: salame, matching: find.text('la mitad')), findsOneWidget);
      await tocarSabor(t, 'Salame');
      expect(find.widgetWithText(TarjetaSabor, 'Salame'), findsNothing, reason: 'la segunda mitad no ofrece el mismo sabor');
      expect(texto(t, 'miga'), 'Pizza · Mitad y mitad · Segunda mitad');
      await tocarSabor(t, 'Peperoni');
      expect(find.text('Mitad Salame / mitad Peperoni'), findsWidgets);
      await tocarTexto(t, 'Confirmar pizza · Bs 47,50');
      await tocar(t, find.byKey(Key('bebida-${carta.bebidas.last.id}-mas'))); // Gaseosa 2 L
      await tocarTexto(t, 'Continuar');
      await t.enterText(find.byKey(const Key('observacion')), 'Bien cocida');
      await t.pump();
      await tocarTexto(t, 'Ver resumen');
      expect(texto(t, 'total-resumen'), 'Bs 65,50');
      expect(find.text('Bien cocida'), findsOneWidget);
    });

    testWidgets('3 Choclo iguales con extra choclo: 3 × (45 + 5) = Bs 150', (t) async {
      await empezar(t);
      await escribirCantidad(t, 3);
      await tocarTexto(t, 'Sí, todas iguales');
      expect(texto(t, 'miga'), '3 pizzas iguales');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Choclo');
      await tocar(t, find.widgetWithText(FilterChip, 'Extra choclo · Bs 5'));
      await tocarTexto(t, 'Confirmar las 3 pizzas · Bs 150');
      expect(texto(t, 'total-panel'), 'Bs 150');
      await tocarTexto(t, 'Sin bebidas');
      await tocarTexto(t, 'Ver resumen');
      expect(texto(t, 'total-resumen'), 'Bs 150');
      expect(find.text('+ Extra choclo'), findsWidgets);
    });

    testWidgets('20 distintas: se confirma cada una, y "Igual a la pizza anterior" la repite', (t) async {
      await empezar(t);
      await escribirCantidad(t, 20);
      await tocarTexto(t, 'No, son distintas');
      expect(texto(t, 'faltan'), 'Faltan 20 de 20');
      expect(find.text('¿Cómo es la pizza 1?'), findsOneWidget);
      expect(find.text('Igual a la pizza anterior'), findsNothing, reason: 'la primera no tiene anterior');

      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Peperoni');
      await tocarTexto(t, 'Confirmar pizza 1 · Bs 50');
      expect(find.text('¿Cómo es la pizza 2?'), findsOneWidget);
      expect(find.text('Peperoni · Bs 50'), findsOneWidget, reason: 'la opción dice qué repite');
      for (var i = 0; i < 7; i++) {
        await tocarTexto(t, 'Igual a la pizza anterior');
      }
      expect(texto(t, 'faltan'), 'Faltan 12 de 20');
      expect(texto(t, 'miga'), 'Pizza 9 de 20');

      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Hawaiana');
      await tocarTexto(t, 'Confirmar pizza 9 · Bs 50');
      for (var i = 0; i < 5; i++) {
        await tocarTexto(t, 'Igual a la pizza anterior');
      }

      await tocarTexto(t, 'Mitad y mitad');
      await tocarSabor(t, 'Salame');
      await tocarSabor(t, 'Peperoni');
      await tocarTexto(t, 'Confirmar pizza 15 · Bs 47,50');
      for (var i = 0; i < 5; i++) {
        await tocarTexto(t, 'Igual a la pizza anterior');
      }

      expect(find.text('¿Alguna bebida?'), findsOneWidget);
      expect(texto(t, 'total-panel'), 'Bs 985'); // 8 × 50 + 6 × 50 + 6 × 47,50
    });

    testWidgets('solo bebidas: sin elegir una, no se puede seguir', (t) async {
      await empezar(t);
      await tocarTexto(t, 'Sin pizza, solo bebidas');
      final continuar = find.widgetWithText(FilledButton, 'Sin bebidas');
      expect(t.widget<FilledButton>(continuar).onPressed, isNull);
      expect(find.text('Elige al menos una bebida.'), findsOneWidget);
      final gaseosa = carta.bebidas.last;
      await tocar(t, find.byKey(Key('bebida-${gaseosa.id}-mas')));
      await tocar(t, find.byKey(Key('bebida-${gaseosa.id}-mas')));
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Ver resumen');
      expect(texto(t, 'total-resumen'), 'Bs 36');
    });
  });

  group('volver, cancelar y los límites', () {
    testWidgets('volver deshace el último paso', (t) async {
      await empezar(t);
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Mitad y mitad');
      await tocarSabor(t, 'Salame');
      await tocarTexto(t, 'Volver');
      expect(find.text('Primera mitad'), findsOneWidget);
      expect(find.widgetWithText(TarjetaSabor, 'Salame'), findsOneWidget);
    });

    testWidgets('cancelar la venta pide confirmación y deja todo en blanco', (t) async {
      await empezar(t);
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Peperoni');
      await tocarTexto(t, 'Confirmar pizza · Bs 50');
      expect(texto(t, 'total-panel'), 'Bs 50');

      await tocarTexto(t, 'Cancelar venta');
      await tocarTexto(t, 'Seguir con la venta');
      expect(texto(t, 'total-panel'), 'Bs 50');

      await tocarTexto(t, 'Cancelar venta');
      await tocar(t, find.widgetWithText(FilledButton, 'Cancelar venta'));
      expect(find.text('¿Cuántas pizzas?'), findsOneWidget);
      expect(texto(t, 'total-panel'), 'Bs 0');
    });

    testWidgets('una pizza agotada se ve marcada y no se puede elegir', (t) async {
      await empezar(t);
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      expect(find.text('Agotada'), findsOneWidget);
      await t.tap(find.widgetWithText(TarjetaSabor, 'Cuatro quesos'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text('¿Qué sabor?'), findsOneWidget, reason: 'sigue en el mismo paso');
    });

    testWidgets('una cantidad fuera de 1 a 50 no avanza, y lo dice', (t) async {
      await empezar(t);
      await escribirCantidad(t, 60);
      expect(find.text('Escribe un número de 1 a 50.'), findsOneWidget);
      expect(find.text('¿Cuántas pizzas?'), findsOneWidget);
      await escribirCantidad(t, 0);
      expect(find.text('Escribe un número de 1 a 50.'), findsOneWidget);
    });

    testWidgets('en el resumen se quita un grupo y se agregan más pizzas', (t) async {
      await empezar(t);
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Salame');
      await tocarTexto(t, 'Confirmar pizza · Bs 45');
      await tocarTexto(t, 'Sin bebidas');
      await tocarTexto(t, 'Ver resumen');
      await tocarTexto(t, 'Agregar pizzas');
      expect(find.text('¿Cuántas pizzas más?'), findsOneWidget);
      expect(find.text('Sin pizza, solo bebidas'), findsNothing);
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Hawaiana');
      await tocarTexto(t, 'Confirmar pizza · Bs 50');
      await tocarTexto(t, 'Sin bebidas');
      await tocarTexto(t, 'Ver resumen');
      expect(texto(t, 'total-resumen'), 'Bs 95');
      await tocar(t, find.byTooltip('Quitar').first);
      expect(texto(t, 'total-resumen'), 'Bs 50');
    });
  });

  group('terminar la venta', () {
    Future<void> hastaElResumen(WidgetTester t) async {
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Peperoni');
      await tocarTexto(t, 'Confirmar pizza · Bs 50');
      await tocarTexto(t, 'Sin bebidas');
      await tocarTexto(t, 'Ver resumen');
    }

    testWidgets('sin el envío a cocina, el botón se ve deshabilitado y lo explica', (t) async {
      await empezar(t);
      await hastaElResumen(t);
      final boton = find.widgetWithText(FilledButton, 'Terminar venta');
      expect(t.widget<FilledButton>(boton).onPressed, isNull);
      expect(find.text('El envío a cocina todavía no está disponible.'), findsOneWidget);
    });

    testWidgets('con el envío conectado, entrega la venta armada', (t) async {
      tamano(t, 1400, 1400);
      EstadoVenta? enviada;
      await t.pumpWidget(app(() async => carta, alTerminar: (v) => enviada = v));
      await t.pumpAndSettle();
      await hastaElResumen(t);
      await tocarTexto(t, 'Terminar venta');
      expect(enviada?.total, 5000);
      expect(enviada?.grupos.single.pizza.titulo, 'Peperoni');
    });
  });

  group('en pantallas angostas', () {
    testWidgets('la venta va en una barra abajo, sin panel lateral', (t) async {
      await empezar(t, ancho: 375, alto: 812);
      expect(find.byKey(const Key('total-panel')), findsNothing);
      expect(texto(t, 'resumen-barra'), 'Venta vacía');
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Peperoni');
      await tocarTexto(t, 'Confirmar pizza · Bs 50');
      expect(texto(t, 'resumen-barra'), '1 pizza · Bs 50');
      await tocarTexto(t, 'Ver venta');
      expect(texto(t, 'total-panel'), 'Bs 50');
    });

    testWidgets('a 320 px, volver y cancelar quedan como íconos con su descripción', (t) async {
      await empezar(t, ancho: 320, alto: 640);
      await tocarTexto(t, 'Continuar');
      expect(find.byTooltip('Volver'), findsOneWidget);
      expect(find.byTooltip('Cancelar venta'), findsOneWidget);
      await tocar(t, find.byTooltip('Volver'));
      expect(find.text('¿Cuántas pizzas?'), findsOneWidget);
    });

    testWidgets('una venta entera a 320 px, sin desbordes', (t) async {
      await empezar(t, ancho: 320, alto: 640);
      await escribirCantidad(t, 2);
      expect(t.takeException(), isNull);
      await tocarTexto(t, 'No, son distintas');
      await tocarTexto(t, 'Mitad y mitad');
      await tocarSabor(t, 'Salame');
      await tocarSabor(t, 'Peperoni');
      expect(t.takeException(), isNull);
      await tocar(t, find.widgetWithText(FilterChip, 'Extra queso · Bs 8'));
      await tocarTexto(t, 'Confirmar pizza 1 · Bs 55,50');
      expect(t.takeException(), isNull);
      await tocarTexto(t, 'Igual a la pizza anterior');
      await tocar(t, find.byKey(Key('bebida-${carta.bebidas.first.id}-mas')));
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Ver resumen');
      expect(t.takeException(), isNull);
      expect(texto(t, 'total-resumen'), 'Bs 117'); // 2 × (47,50 + 8) + 6
    });
  });
}
