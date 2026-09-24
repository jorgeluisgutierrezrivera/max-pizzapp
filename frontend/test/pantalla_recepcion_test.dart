// La venta guiada en pantalla (D-30): ventas completas tocando botones, como la vendedora.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/pantallas/pantalla_recepcion.dart';
import 'package:maxpizzapp/pantallas/venta/comunes.dart';
import 'package:maxpizzapp/pantallas/venta/pasos.dart';
import 'package:maxpizzapp/pantallas/venta/resumen_venta.dart';
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

typedef Enviar = Future<Map<String, dynamic>> Function(Map<String, dynamic> pedido);

Widget app(Future<Carta> Function() cargar, {Enviar? enviar}) => MaterialApp(
      theme: temaMaxPizzas(),
      home: PantallaRecepcion(
        usuario: usuario,
        alCerrarSesion: () {},
        cargarCarta: cargar,
        imagen: (ruta, respaldo, ajuste) => respaldo,
        enviarPedido: enviar,
      ),
    );

/// Lo que devuelve el servidor al guardar: el número y el total son los suyos.
Map<String, dynamic> pedidoGuardado(Map<String, dynamic> enviado, {int id = 12, String estado = 'pendiente'}) => {
      'id': id,
      'estado': estado,
      'paraLlevar': enviado['paraLlevar'],
      'cliente': enviado['cliente'],
      'total': enviado['totalEsperado'],
      'lineas': const [],
    };

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

/// De la observación al resumen: "Continuar", para llevar o no, y a nombre de quién.
Future<void> cerrarVenta(WidgetTester t, {String nombre = 'Ana Prueba', String? celular, bool paraLlevar = true}) async {
  await tocarTexto(t, 'Continuar');
  expect(find.text('¿Para llevar o para comer aquí?'), findsOneWidget);
  await tocarTexto(t, paraLlevar ? 'Para llevar' : 'Para comer aquí');
  expect(find.text('¿A nombre de quién?'), findsOneWidget);
  await t.enterText(find.byKey(const Key('cliente-nombre')), nombre);
  if (celular != null) await t.enterText(find.byKey(const Key('cliente-celular')), celular);
  await t.pump();
  await tocarTexto(t, 'Ver resumen');
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
      await cerrarVenta(t);
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
      await cerrarVenta(t);
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
      await cerrarVenta(t);
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
      await cerrarVenta(t);
      await tocarTexto(t, 'Agregar pizzas');
      expect(find.text('¿Cuántas pizzas más?'), findsOneWidget);
      expect(find.text('Sin pizza, solo bebidas'), findsNothing);
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Hawaiana');
      await tocarTexto(t, 'Confirmar pizza · Bs 50');
      await tocarTexto(t, 'Sin bebidas');
      await tocarTexto(t, 'Continuar'); // el cliente ya estaba: directo al resumen
      expect(texto(t, 'total-resumen'), 'Bs 95');
      await tocar(t, find.byTooltip('Quitar').first);
      expect(texto(t, 'total-resumen'), 'Bs 50');
    });
  });

  group('terminar la venta', () {
    Future<void> hastaElResumen(WidgetTester t, {String? celular}) async {
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Un solo sabor');
      await tocarSabor(t, 'Peperoni');
      await tocarTexto(t, 'Confirmar pizza · Bs 50');
      await tocarTexto(t, 'Sin bebidas');
      await cerrarVenta(t, celular: celular);
    }

    Future<void> conEnvio(WidgetTester t, Enviar enviar) async {
      tamano(t, 1400, 1400);
      await t.pumpWidget(app(() async => carta, enviar: enviar));
      await t.pumpAndSettle();
    }

    testWidgets('sin el envío a cocina, el botón se ve deshabilitado y lo explica', (t) async {
      await empezar(t);
      await hastaElResumen(t);
      final boton = find.widgetWithText(FilledButton, 'Terminar venta');
      expect(t.widget<FilledButton>(boton).onPressed, isNull);
      expect(find.text('El envío a cocina todavía no está disponible.'), findsOneWidget);
    });

    testWidgets('el resumen dice si es para llevar y a nombre de quién, y se puede cambiar', (t) async {
      await empezar(t);
      await hastaElResumen(t, celular: '70000001');
      expect(texto(t, 'cliente-resumen'), 'Para llevar · Ana Prueba · 70000001');
      await tocar(t, find.descendant(of: find.widgetWithText(ListTile, 'Para llevar · Ana Prueba · 70000001'),
          matching: find.text('Cambiar')));
      await tocarTexto(t, 'Para comer aquí');
      expect(t.widget<TextField>(find.byKey(const Key('cliente-nombre'))).controller!.text, 'Ana Prueba',
          reason: 'lo ya escrito se conserva');
      await tocarTexto(t, 'Ver resumen');
      expect(texto(t, 'cliente-resumen'), 'Para comer aquí · Ana Prueba · 70000001');
    });

    testWidgets('envía la venta y muestra el número del pedido; "Nueva venta" empieza otra', (t) async {
      Map<String, dynamic>? enviado;
      await conEnvio(t, (pedido) async {
        enviado = pedido;
        return pedidoGuardado(pedido);
      });
      await hastaElResumen(t, celular: '70000001');
      await tocarTexto(t, 'Terminar venta');
      expect(enviado, {
        'paraLlevar': true,
        'cliente': {'nombre': 'Ana Prueba', 'celular': '70000001'},
        'observacion': null,
        'lineas': [
          {'productoId': carta.pizzas.firstWhere((p) => p.nombre == 'Peperoni').id, 'cantidad': 1},
        ],
        'totalEsperado': 50.0,
      });
      expect(texto(t, 'pedido-enviado'), 'Pedido #12 enviado a cocina');
      expect(find.text('Ana Prueba · Para llevar'), findsOneWidget);
      expect(texto(t, 'total-enviado'), 'Bs 50');
      await tocarTexto(t, 'Nueva venta');
      expect(find.text('¿Cuántas pizzas?'), findsOneWidget);
      expect(texto(t, 'total-panel'), 'Bs 0');
    });

    testWidgets('mientras viaja dice "Enviando" y no se puede tocar dos veces', (t) async {
      final respuesta = Completer<Map<String, dynamic>>();
      var envios = 0;
      await conEnvio(t, (pedido) {
        envios++;
        return respuesta.future;
      });
      await hastaElResumen(t);
      await t.tap(find.text('Terminar venta'));
      await t.pump();
      final boton = find.widgetWithText(FilledButton, 'Enviando a cocina…');
      expect(boton, findsOneWidget);
      expect(t.widget<FilledButton>(boton).onPressed, isNull);
      await t.tap(boton, warnIfMissed: false);
      expect(envios, 1);
      respuesta.complete({'id': 3, 'estado': 'pendiente', 'paraLlevar': true, 'cliente': {'nombre': 'Ana Prueba'}, 'total': 50});
      await t.pumpAndSettle();
      expect(texto(t, 'pedido-enviado'), 'Pedido #3 enviado a cocina');
    });

    testWidgets('un pedido de solo bebidas queda listo para entregar (D-32)', (t) async {
      await conEnvio(t, (pedido) async => pedidoGuardado(pedido, id: 7, estado: 'listo'));
      await tocarTexto(t, 'Sin pizza, solo bebidas');
      await tocar(t, find.byKey(Key('bebida-${carta.bebidas.last.id}-mas')));
      await tocarTexto(t, 'Continuar');
      await cerrarVenta(t);
      await tocarTexto(t, 'Terminar venta');
      expect(texto(t, 'pedido-enviado'), 'Pedido #7 listo para entregar');
      expect(find.text('Es solo de bebidas: no pasa por cocina.'), findsOneWidget);
    });

    testWidgets('un producto agotado: la venta queda como estaba y el mensaje dice cuál', (t) async {
      await conEnvio(t, (pedido) async => throw const ErrorApi(409, 'PRODUCTO_NO_DISPONIBLE',
          'Peperoni no esta disponible.', {'producto': {'id': 2, 'nombre': 'Peperoni'}}));
      await hastaElResumen(t);
      await tocarTexto(t, 'Terminar venta');
      expect(texto(t, 'error-envio'), 'Peperoni se agotó. Quítalo de la venta y vuelve a enviarla.');
      expect(texto(t, 'total-resumen'), 'Bs 50');
      expect(find.text('Resumen de la venta'), findsOneWidget);
    });

    testWidgets('sin conexión la venta sigue ahí, y al reintentar se envía', (t) async {
      var intentos = 0;
      await conEnvio(t, (pedido) async {
        intentos++;
        if (intentos == 1) {
          throw const ErrorApi(0, 'SIN_CONEXION', 'No hay conexión con el servidor.');
        }
        return pedidoGuardado(pedido);
      });
      await hastaElResumen(t);
      await tocarTexto(t, 'Terminar venta');
      expect(texto(t, 'error-envio'),
          'No se pudo enviar: no hay conexión con el servidor. La venta sigue aquí; vuelve a intentarlo.');
      await tocarTexto(t, 'Terminar venta');
      expect(intentos, 2);
      expect(texto(t, 'pedido-enviado'), 'Pedido #12 enviado a cocina');
    });

    testWidgets('si la carta cambió, dice el total correcto y que no se guardó nada', (t) async {
      await conEnvio(t, (pedido) async => throw const ErrorApi(
          409, 'PRECIO_CAMBIADO', 'La carta cambio.', {'totalCorrecto': 55}));
      await hastaElResumen(t);
      await tocarTexto(t, 'Terminar venta');
      expect(texto(t, 'error-envio'), 'La carta cambió mientras se armaba la venta y no se guardó nada. '
          'El total correcto es Bs 55. Cancela esta venta y ármala de nuevo.');
    });

    testWidgets('el cliente: sin nombre no avanza, y un celular mal escrito tampoco', (t) async {
      await empezar(t);
      await tocarTexto(t, 'Sin pizza, solo bebidas');
      await tocar(t, find.byKey(Key('bebida-${carta.bebidas.last.id}-mas')));
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Continuar');
      await tocarTexto(t, 'Para llevar');
      expect(find.text('Conviene pedirlo: para avisarle cuando esté listo.'), findsOneWidget);
      await tocarTexto(t, 'Ver resumen');
      expect(texto(t, 'cliente-error'), 'Escribe el nombre del cliente.');
      await t.enterText(find.byKey(const Key('cliente-nombre')), 'Ana Prueba');
      await t.enterText(find.byKey(const Key('cliente-celular')), '5000');
      await t.pump();
      await tocarTexto(t, 'Ver resumen');
      expect(texto(t, 'cliente-error'), 'El celular tiene 8 dígitos y empieza con 6 o 7.');
      expect(find.text('¿A nombre de quién?'), findsOneWidget);
    });
  });

  group('en pantallas anchas', () {
    testWidgets('las opciones de una pregunta van en fila, como fichas', (t) async {
      await empezar(t, ancho: 1440, alto: 900);
      await tocarTexto(t, 'Continuar');
      final fichas = t.widgetList<OpcionGrande>(find.byType(OpcionGrande));
      expect(fichas.map((o) => o.vertical), [true, true]);
      final (a, b) = (t.getCenter(find.text('Un solo sabor')), t.getCenter(find.text('Mitad y mitad')));
      expect((a.dy - b.dy).abs(), lessThan(1), reason: 'a la misma altura');
    });

    testWidgets('en el celular, una debajo de otra, como antes', (t) async {
      await empezar(t, ancho: 375, alto: 812);
      await tocarTexto(t, 'Continuar');
      expect(t.widgetList<OpcionGrande>(find.byType(OpcionGrande)).map((o) => o.vertical), [false, false]);
    });

    testWidgets('la venta es una tarjeta al lado de la pregunta, dentro de un ancho máximo', (t) async {
      await empezar(t, ancho: 2400, alto: 1000);
      final panel = t.getRect(find.byType(PanelVenta));
      expect(panel.right, lessThan(2400 - 500), reason: 'no queda pegada al borde derecho');
      expect(t.takeException(), isNull);
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
      await cerrarVenta(t);
      expect(t.takeException(), isNull);
      expect(texto(t, 'total-resumen'), 'Bs 117'); // 2 × (47,50 + 8) + 6
    });
  });
}
