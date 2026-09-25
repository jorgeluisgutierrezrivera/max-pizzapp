// La venta en una sola pantalla (D-36): ventas completas tocando botones, como la vendedora,
// con el modal de cada pizza y la venta directa de bebidas (D-38).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/pantallas/pantalla_recepcion.dart';
import 'package:maxpizzapp/pantallas/venta/comunes.dart';
import 'package:maxpizzapp/pantallas/venta/formulario_de_venta.dart';
import 'package:maxpizzapp/pantallas/venta/pedido_enviado.dart';
import 'package:maxpizzapp/tema.dart';

var _id = 0;
Producto producto(String nombre, String categoria, num precio, {bool disponible = true, String? descripcion}) =>
    Producto.desdeJson({
      'id': ++_id,
      'nombre': nombre,
      'categoria': categoria,
      'precio': precio,
      'descripcion': descripcion,
      'imagen': null,
      'disponible': disponible,
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

Producto de(String nombre) =>
    [...carta.pizzas, ...carta.extras, ...carta.bebidas].firstWhere((p) => p.nombre == nombre);

final usuario = Usuario.desdeJson({
  'sub': 'x',
  'nombre': 'Ana Prueba',
  'usuario': 'recepcion.demo',
  'roles': ['recepcion'],
});

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
Map<String, dynamic> pedidoGuardado(Map<String, dynamic> enviado, {int id = 40, int? numero = 12}) {
  final directa = enviado['ventaDirecta'] == true;
  return {
    'id': id,
    'numero': directa ? null : numero,
    'estado': directa ? 'entregado' : 'pendiente',
    'paraLlevar': enviado['paraLlevar'],
    'cliente': enviado['cliente'],
    'total': enviado['totalEsperado'],
    'lineas': const [],
  };
}

void tamano(WidgetTester t, double ancho, double alto) {
  t.view.physicalSize = Size(ancho, alto);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// El texto de un widget por su clave, sea un Text o algo que lo contiene (un botón).
String texto(WidgetTester t, String clave) {
  final f = find.byKey(Key(clave));
  final w = t.widget(f);
  if (w is Text) return w.data!;
  return t.widget<Text>(find.descendant(of: f, matching: find.byType(Text)).first).data!;
}

/// Lo que se desplaza en el formulario: todo el formulario en el celular, o solo la lista de
/// pizzas en la computadora.
Finder? desplazable(WidgetTester t) {
  final formulario = find.byKey(const Key('formulario-venta'));
  if (formulario.evaluate().isNotEmpty && t.widget(formulario) is ListView) {
    return find.descendant(of: formulario, matching: find.byType(Scrollable)).first;
  }
  final pizzas = find.byKey(const Key('lista-pizzas'));
  if (pizzas.evaluate().isNotEmpty) return find.descendant(of: pizzas, matching: find.byType(Scrollable)).first;
  return null;
}

Future<void> tocar(WidgetTester t, Finder f) async {
  // Lo que se desplaza construye solo lo que está cerca de la vista: si el botón todavía no
  // existe, se desplaza hasta él, como lo haría la vendedora.
  final lista = desplazable(t);
  if (f.evaluate().isEmpty && lista != null) {
    t.state<ScrollableState>(lista).position.jumpTo(0);
    await t.pump();
    await t.scrollUntilVisible(f, 200, scrollable: lista);
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> tocarClave(WidgetTester t, String clave) => tocar(t, find.byKey(Key(clave)));

Future<void> empezar(WidgetTester t, {double ancho = 1400, double alto = 1400, Enviar? enviar}) async {
  tamano(t, ancho, alto);
  await t.pumpWidget(app(() async => carta, enviar: enviar));
  await t.pumpAndSettle();
}

Future<void> escribirCliente(
  WidgetTester t, {
  String nombre = 'Ana Prueba',
  String? celular,
  bool paraLlevar = true,
}) async {
  await t.enterText(find.byKey(const Key('cliente-nombre')), nombre);
  if (celular != null) await t.enterText(find.byKey(const Key('cliente-celular')), celular);
  await tocarClave(t, paraLlevar ? 'para-llevar' : 'comer-aqui');
}

/// La grilla construye solo lo visible: se desplaza hasta el sabor, como lo haría la vendedora.
Future<void> tocarSabor(WidgetTester t, String nombre) async {
  final sabor = find.byKey(Key('sabor-$nombre'));
  final grilla = find.descendant(of: find.byKey(const Key('grilla-sabores')), matching: find.byType(Scrollable)).first;
  if (sabor.evaluate().isEmpty) {
    t.state<ScrollableState>(grilla).position.jumpTo(0);
    await t.pump();
  }
  await t.scrollUntilVisible(sabor, 150, scrollable: grilla);
  await tocar(t, sabor);
}

/// Abre el modal, arma la pizza y la agrega.
Future<void> agregarPizza(
  WidgetTester t,
  String sabor, {
  String? mitad,
  List<String> extras = const [],
  int cantidad = 1,
}) async {
  await tocarClave(t, 'agregar-pizza');
  if (mitad != null) await tocarClave(t, 'tipo-mitades');
  await tocarSabor(t, sabor);
  if (mitad != null) await tocarSabor(t, mitad);
  for (final extra in extras) {
    await tocarClave(t, 'extra-$extra');
  }
  for (var i = 1; i < cantidad; i++) {
    await tocarClave(t, 'cantidad-pizza-mas');
  }
  await tocarClave(t, 'listo-pizza');
}

bool elegido(WidgetTester t, String clave) => t.widget<BotonEleccion>(find.byKey(Key(clave))).elegido;

void main() {
  group('los cuatro estados', () {
    testWidgets('cargando', (t) async {
      final pendiente = Completer<Carta>();
      await t.pumpWidget(app(() => pendiente.future));
      expect(find.text('Cargando la carta…'), findsOneWidget);
      pendiente.complete(carta);
      await t.pumpAndSettle();
      expect(find.text('1 · Cliente'), findsOneWidget);
    });

    testWidgets('error: el mensaje del servidor, y reintentar vuelve a pedir', (t) async {
      var intentos = 0;
      await t.pumpWidget(
        app(() async {
          intentos++;
          if (intentos == 1) {
            throw const ErrorApi(503, 'BASE_NO_DISPONIBLE', 'No se pueden leer los datos en este momento.');
          }
          return carta;
        }),
      );
      await t.pumpAndSettle();
      expect(find.text('No se pueden leer los datos en este momento.'), findsOneWidget);
      await tocar(t, find.text('Reintentar'));
      expect(intentos, 2);
      expect(find.text('1 · Cliente'), findsOneWidget);
    });

    testWidgets('carta vacía: lo dice, en vez de una pantalla en blanco', (t) async {
      await t.pumpWidget(app(() async => Carta(const [])));
      await t.pumpAndSettle();
      expect(find.text('La carta todavía no tiene productos.'), findsOneWidget);
    });
  });

  group('el formulario en una sola pantalla', () {
    testWidgets('todo a la vista: el cliente, las pizzas, las bebidas y el pedido con la observación y el total', (
      t,
    ) async {
      await empezar(t);
      for (final titulo in ['1 · Cliente', '2 · Pizzas', '3 · Bebidas']) {
        expect(find.text(titulo), findsOneWidget, reason: titulo);
      }
      expect(find.byType(PanelPedido), findsOneWidget);
      // En la computadora, la observación va en el pedido, justo antes de confirmar.
      expect(
        find.descendant(of: find.byType(PanelPedido), matching: find.byKey(const Key('observacion'))),
        findsOneWidget,
      );
      expect(texto(t, 'total-venta'), 'Bs 0');
      expect(texto(t, 'cliente-resumen'), 'Sin nombre todavía');
      expect(texto(t, 'llevar-resumen'), '– Sin elegir si es para comer aquí o para llevar');
      // Vender bebidas está en la primera línea: es la primera decisión del mostrador.
      expect(
        find.descendant(
          of: find.widgetWithText(Seccion, '1 · Cliente'),
          matching: find.byKey(const Key('vender-bebidas')),
        ),
        findsOneWidget,
      );
    });

    for (final (ancho, alto) in [(1366.0, 630.0), (1536.0, 730.0), (1920.0, 950.0), (1024.0, 600.0)]) {
      testWidgets(
        'en la computadora (${ancho.round()} × ${alto.round()}), el formulario ocupa la pantalla sin desplazarse',
        (t) async {
          await empezar(t, ancho: ancho, alto: alto);
          // No es una lista que se desplaza: es la pantalla entera, con las bebidas al fondo.
          expect(t.widget(find.byKey(const Key('formulario-venta'))), isNot(isA<ListView>()));
          final bebidas = t.getRect(find.widgetWithText(Seccion, '3 · Bebidas'));
          expect(bebidas.bottom, lessThanOrEqualTo(alto));
          expect(alto - bebidas.bottom, lessThan(40), reason: 'llega hasta abajo: no queda un vacío');
          final pizzas = t.getRect(find.widgetWithText(Seccion, '2 · Pizzas'));
          expect(pizzas.height, greaterThan(120), reason: 'las pizzas ocupan el alto que sobra');
          final panel = t.getRect(find.byType(PanelPedido));
          expect(panel.bottom, lessThanOrEqualTo(alto));
        },
      );
    }

    testWidgets('con muchas pizzas se desplaza solo su lista; "Agregar otra pizza" y las bebidas siguen a la vista', (
      t,
    ) async {
      await empezar(t, ancho: 1366, alto: 630, enviar: (p) async => pedidoGuardado(p));
      await escribirCliente(t);
      for (final sabor in ['Salame', 'Peperoni', 'Choclo', 'Hawaiana']) {
        await agregarPizza(t, sabor);
      }
      await agregarPizza(t, 'Salame', mitad: 'Choclo');
      final lista = find.descendant(of: find.byKey(const Key('lista-pizzas')), matching: find.byType(Scrollable)).first;
      expect(t.state<ScrollableState>(lista).position.maxScrollExtent, greaterThan(0));
      expect(t.getRect(find.byKey(const Key('agregar-pizza'))).bottom, lessThanOrEqualTo(630));
      expect(t.getRect(find.widgetWithText(Seccion, '3 · Bebidas')).bottom, lessThanOrEqualTo(630));
      await tocarClave(t, 'confirmar-venta');
      expect(find.byKey(const Key('lista-pizzas')), findsNothing);
      expect(find.text('Todavía no hay pizzas.'), findsOneWidget);
    });

    testWidgets('en el celular, al enviar, el formulario vuelve arriba', (t) async {
      await empezar(t, ancho: 360, alto: 740, enviar: (p) async => pedidoGuardado(p));
      await escribirCliente(t);
      for (final sabor in ['Salame', 'Peperoni', 'Choclo']) {
        await agregarPizza(t, sabor);
      }
      final lista = desplazable(t)!;
      final posicion = t.state<ScrollableState>(lista).position;
      posicion.jumpTo(posicion.maxScrollExtent);
      await t.pump();
      expect(posicion.pixels, greaterThan(0));
      await tocarClave(t, 'confirmar-venta');
      expect(t.state<ScrollableState>(lista).position.pixels, 0);
    });

    testWidgets('en el modal, los extras están a la vista sin bajar hasta después de las pizzas', (t) async {
      await empezar(t, ancho: 1366, alto: 630);
      await tocarClave(t, 'agregar-pizza');
      final extra = t.getRect(find.byKey(const Key('extra-Extra queso')));
      expect(extra.bottom, lessThanOrEqualTo(630));
      // Y en el celular, en el pie, siempre visible.
      await tocarClave(t, 'cerrar-modal');
      tamano(t, 360, 740);
      await t.pumpAndSettle();
      await tocarClave(t, 'agregar-pizza');
      expect(t.getRect(find.byKey(const Key('fila-extras'))).bottom, lessThanOrEqualTo(740));
      final grilla = find
          .descendant(of: find.byKey(const Key('grilla-sabores')), matching: find.byType(Scrollable))
          .first;
      expect(t.state<ScrollableState>(grilla).position.pixels, 0, reason: 'sin desplazar nada');
    });

    testWidgets('"comer aquí o para llevar" no trae una opción marcada; se marca una sola', (t) async {
      await empezar(t);
      expect((elegido(t, 'comer-aqui'), elegido(t, 'para-llevar')), (false, false));
      await tocarClave(t, 'para-llevar');
      expect((elegido(t, 'comer-aqui'), elegido(t, 'para-llevar')), (false, true));
      await tocarClave(t, 'comer-aqui');
      expect((elegido(t, 'comer-aqui'), elegido(t, 'para-llevar')), (true, false));
    });

    testWidgets('para llevar sugiere pedir el celular', (t) async {
      await empezar(t);
      await tocarClave(t, 'para-llevar');
      expect(find.text('Conviene pedirlo, para avisarle.'), findsOneWidget);
    });

    testWidgets('una venta completa: el cuerpo exacto que se envía, el aviso con el número y el formulario limpio', (
      t,
    ) async {
      Map<String, dynamic>? enviado;
      await empezar(
        t,
        enviar: (pedido) async {
          enviado = pedido;
          return pedidoGuardado(pedido);
        },
      );
      await escribirCliente(t, celular: '70000001');
      await agregarPizza(t, 'Salame', mitad: 'Peperoni', extras: ['Extra queso'], cantidad: 2);
      await tocarClave(t, 'bebida-${de('Gaseosa 2 L').id}-mas');
      await t.enterText(find.byKey(const Key('observacion')), 'sin cebolla');
      await t.pump();
      expect(texto(t, 'total-venta'), 'Bs 129');
      // En el pedido: el nombre con su celular al lado y, debajo, si es para llevar.
      expect(texto(t, 'cliente-resumen'), 'Ana Prueba · 70000001');
      expect(texto(t, 'llevar-resumen'), '– Para llevar');

      await tocarClave(t, 'confirmar-venta');
      expect(enviado, {
        'paraLlevar': true,
        'cliente': {'nombre': 'Ana Prueba', 'celular': '70000001'},
        'observacion': 'sin cebolla',
        'lineas': [
          {
            'productoId': de('Salame').id,
            'mitadId': de('Peperoni').id,
            'cantidad': 2,
            'extras': [de('Extra queso').id],
          },
          {'productoId': de('Gaseosa 2 L').id, 'cantidad': 1},
        ],
        'totalEsperado': 129.0,
      });
      expect(texto(t, 'pedido-enviado'), 'Pedido 12 de Ana Prueba enviado a cocina');
      expect(find.text('Para llevar · Bs 129'), findsOneWidget);
      // Listo para el siguiente cliente.
      expect(t.widget<TextField>(find.byKey(const Key('cliente-nombre'))).controller!.text, '');
      expect(t.widget<TextField>(find.byKey(const Key('observacion'))).controller!.text, '');
      expect((elegido(t, 'comer-aqui'), elegido(t, 'para-llevar')), (false, false));
      expect(texto(t, 'total-venta'), 'Bs 0');
      expect(texto(t, 'cliente-resumen'), 'Sin nombre todavía');
    });

    testWidgets('el aviso de la venta se cierra solo, o antes con la X', (t) async {
      await empezar(t, enviar: (p) async => pedidoGuardado(p));
      await escribirCliente(t, paraLlevar: false);
      await agregarPizza(t, 'Peperoni');
      await tocarClave(t, 'confirmar-venta');
      expect(texto(t, 'pedido-enviado'), 'Pedido 12 de Ana Prueba enviado a cocina');
      expect(find.text('Para comer aquí · Bs 50'), findsOneWidget);
      await t.pump(duracionDelAviso + const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('aviso-enviado')), findsNothing);

      await escribirCliente(t);
      await agregarPizza(t, 'Salame');
      await tocarClave(t, 'confirmar-venta');
      expect(find.byKey(const Key('aviso-enviado')), findsOneWidget);
      await t.tap(find.descendant(of: find.byType(SnackBar), matching: find.byIcon(Icons.close)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('aviso-enviado')), findsNothing);
    });

    testWidgets('confirmar sin lo necesario dice qué falta y no envía nada', (t) async {
      var envios = 0;
      await empezar(
        t,
        enviar: (p) async {
          envios++;
          return pedidoGuardado(p);
        },
      );
      expect(find.byKey(const Key('problemas')), findsNothing, reason: 'antes de intentar, no se regaña');
      await tocarClave(t, 'confirmar-venta');
      expect(envios, 0);
      for (final p in [
        '• Escribe el nombre del cliente.',
        '• Elige si es para comer aquí o para llevar.',
        '• Agrega al menos una pizza.',
      ]) {
        expect(find.text(p), findsOneWidget, reason: p);
      }
      expect(find.text('Con este nombre se anuncia el pedido.'), findsOneWidget);
      expect(find.text('Un pedido lleva al menos una pizza.'), findsOneWidget);
      // A medida que se completa, lo que falta se va.
      await escribirCliente(t);
      expect(find.text('• Escribe el nombre del cliente.'), findsNothing);
      expect(find.text('• Agrega al menos una pizza.'), findsOneWidget);
    });

    testWidgets('solo bebidas no es un pedido: sugiere "Vender bebidas" (D-38)', (t) async {
      await empezar(t, enviar: (p) async => pedidoGuardado(p));
      await escribirCliente(t);
      await tocarClave(t, 'bebida-${de('Gaseosa 2 L').id}-mas');
      await tocarClave(t, 'confirmar-venta');
      expect(
        find.text('• Agrega al menos una pizza. Las bebidas solas se venden con «Vender bebidas».'),
        findsOneWidget,
      );
    });

    testWidgets('un celular que no es boliviano se marca en el campo y no se envía', (t) async {
      var envios = 0;
      await empezar(
        t,
        enviar: (p) async {
          envios++;
          return pedidoGuardado(p);
        },
      );
      await escribirCliente(t, celular: '50000001');
      await agregarPizza(t, 'Peperoni');
      expect(find.text('Empieza con 6 o 7.'), findsOneWidget);
      await tocarClave(t, 'confirmar-venta');
      expect(envios, 0);
      expect(find.text('• El celular tiene 8 dígitos y empieza con 6 o 7.'), findsOneWidget);
    });

    testWidgets('cancelar la venta pregunta antes de borrar', (t) async {
      await empezar(t, enviar: (p) async => pedidoGuardado(p));
      expect(find.byKey(const Key('cancelar-venta')), findsNothing, reason: 'vacía, no hay nada que cancelar');
      await escribirCliente(t);
      await agregarPizza(t, 'Peperoni');
      await tocarClave(t, 'cancelar-venta');
      await tocar(t, find.text('Seguir con la venta'));
      expect(texto(t, 'total-venta'), 'Bs 50');
      await tocarClave(t, 'cancelar-venta');
      await tocarClave(t, 'confirmar-cancelar');
      expect(texto(t, 'total-venta'), 'Bs 0');
      expect(t.widget<TextField>(find.byKey(const Key('cliente-nombre'))).controller!.text, '');
    });

    testWidgets('sin el envío a cocina, Confirmar y Vender bebidas se ven deshabilitados', (t) async {
      await empezar(t);
      expect(t.widget<FilledButton>(find.byKey(const Key('confirmar-venta'))).onPressed, isNull);
      expect(t.widget<OutlinedButton>(find.byKey(const Key('vender-bebidas'))).onPressed, isNull);
    });
  });

  group('las pizzas y su modal', () {
    testWidgets('entera por defecto; el botón dice qué falta y después tiene un solo precio', (t) async {
      await empezar(t);
      await tocarClave(t, 'agregar-pizza');
      expect(find.text('Agregar pizza'), findsWidgets);
      expect((elegido(t, 'tipo-entera'), elegido(t, 'tipo-mitades')), (true, false));
      expect(texto(t, 'listo-pizza'), 'Elige el sabor');
      expect(t.widget<FilledButton>(find.byKey(const Key('listo-pizza'))).onPressed, isNull);
      await tocarSabor(t, 'Peperoni');
      expect(texto(t, 'listo-pizza'), 'Agregar 1 pizza · Bs 50');
      await tocarClave(t, 'cantidad-pizza-mas');
      expect(texto(t, 'listo-pizza'), 'Agregar 2 pizzas · Bs 100');
      await tocarClave(t, 'extra-Extra queso');
      expect(texto(t, 'listo-pizza'), 'Agregar 2 pizzas · Bs 116');
      expect(texto(t, 'pizza-armada'), 'Peperoni  + Extra queso');
      await tocarClave(t, 'listo-pizza');
      expect(find.byKey(const Key('modal-pizza')), findsNothing);
      expect(find.text('Peperoni'), findsWidgets);
      expect(texto(t, 'pizza-0-valor'), '2');
      expect(texto(t, 'total-venta'), 'Bs 116');
    });

    testWidgets('mitad y mitad: cada sabor muestra la mitad de su precio y las mitades se marcan 1 y 2', (t) async {
      await empezar(t);
      await tocarClave(t, 'agregar-pizza');
      await tocarClave(t, 'tipo-mitades');
      expect(find.text('la mitad'), findsWidgets);
      expect(texto(t, 'listo-pizza'), 'Elige los dos sabores');
      await tocarSabor(t, 'Salame');
      expect(texto(t, 'mitad-1'), 'Mitad 1: Salame');
      expect(texto(t, 'listo-pizza'), 'Elige la segunda mitad');
      await tocarSabor(t, 'Peperoni');
      expect(texto(t, 'mitad-2'), 'Mitad 2: Peperoni');
      expect(texto(t, 'listo-pizza'), 'Agregar 1 pizza · Bs 47,50');
      await tocarClave(t, 'listo-pizza');
      expect(find.text('Mitad Salame / mitad Peperoni'), findsWidgets);
    });

    testWidgets('una pizza agotada no responde', (t) async {
      await empezar(t);
      await tocarClave(t, 'agregar-pizza');
      final agotada = find.byKey(const Key('sabor-Cuatro quesos'));
      await t.scrollUntilVisible(
        agotada,
        150,
        scrollable: find.descendant(of: find.byKey(const Key('modal-pizza')), matching: find.byType(Scrollable)).first,
      );
      await t.tap(agotada, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(texto(t, 'listo-pizza'), 'Elige el sabor');
    });

    testWidgets('cerrar el modal no agrega nada', (t) async {
      await empezar(t);
      await tocarClave(t, 'agregar-pizza');
      await tocarSabor(t, 'Peperoni');
      await tocarClave(t, 'cerrar-modal');
      expect(find.byKey(const Key('pizza-0')), findsNothing);
      expect(texto(t, 'total-venta'), 'Bs 0');
    });

    testWidgets('tocar una línea la abre para corregirla, y "Quitar esta pizza" la saca', (t) async {
      await empezar(t);
      await agregarPizza(t, 'Peperoni', cantidad: 2);
      await tocarClave(t, 'corregir-pizza-0');
      expect(find.text('Cambiar pizza'), findsOneWidget);
      expect(texto(t, 'listo-pizza'), 'Guardar 2 pizzas · Bs 100');
      await tocarSabor(t, 'Salame');
      await tocarClave(t, 'listo-pizza');
      expect(find.text('Salame'), findsWidgets);
      expect(texto(t, 'total-venta'), 'Bs 90');
      await tocarClave(t, 'corregir-pizza-0');
      await tocarClave(t, 'quitar-pizza');
      expect(find.byKey(const Key('pizza-0')), findsNothing);
      expect(texto(t, 'total-venta'), 'Bs 0');
    });

    testWidgets('− y + de una línea cambian su cantidad, y en cero la línea sale', (t) async {
      await empezar(t);
      await agregarPizza(t, 'Peperoni');
      await tocarClave(t, 'pizza-0-mas');
      expect(texto(t, 'total-venta'), 'Bs 100');
      await tocarClave(t, 'pizza-0-menos');
      await tocarClave(t, 'pizza-0-menos');
      expect(find.byKey(const Key('pizza-0')), findsNothing);
    });

    testWidgets('la misma pizza agregada dos veces queda en una sola línea', (t) async {
      await empezar(t);
      await agregarPizza(t, 'Salame', mitad: 'Peperoni');
      await agregarPizza(t, 'Peperoni', mitad: 'Salame');
      expect(find.byKey(const Key('pizza-1')), findsNothing);
      expect(texto(t, 'pizza-0-valor'), '2');
    });
  });

  group('enviar la venta', () {
    Future<void> lista(WidgetTester t, Enviar enviar) async {
      await empezar(t, enviar: enviar);
      await escribirCliente(t);
      await agregarPizza(t, 'Peperoni');
    }

    testWidgets('mientras viaja dice "Enviando" y no se puede tocar dos veces', (t) async {
      final respuesta = Completer<Map<String, dynamic>>();
      var envios = 0;
      await lista(t, (pedido) {
        envios++;
        return respuesta.future;
      });
      await t.tap(find.byKey(const Key('confirmar-venta')));
      await t.pump();
      expect(texto(t, 'confirmar-venta'), 'Enviando a cocina…');
      expect(t.widget<FilledButton>(find.byKey(const Key('confirmar-venta'))).onPressed, isNull);
      await t.tap(find.byKey(const Key('confirmar-venta')), warnIfMissed: false);
      expect(envios, 1);
      respuesta.complete({
        'id': 3,
        'numero': 5,
        'estado': 'pendiente',
        'paraLlevar': true,
        'cliente': {'nombre': 'Ana Prueba'},
        'total': 50,
      });
      await t.pumpAndSettle();
      expect(texto(t, 'pedido-enviado'), 'Pedido 5 de Ana Prueba enviado a cocina');
    });

    testWidgets('un producto agotado: la venta queda como estaba y el mensaje dice cuál', (t) async {
      await lista(
        t,
        (pedido) async => throw const ErrorApi(409, 'PRODUCTO_NO_DISPONIBLE', 'Peperoni no esta disponible.', {
          'producto': {'id': 2, 'nombre': 'Peperoni'},
        }),
      );
      await tocarClave(t, 'confirmar-venta');
      expect(texto(t, 'error-envio'), 'Peperoni se agotó. Quítalo de la venta y vuelve a enviarla.');
      expect(texto(t, 'total-venta'), 'Bs 50');
      expect(t.widget<TextField>(find.byKey(const Key('cliente-nombre'))).controller!.text, 'Ana Prueba');
    });

    testWidgets('sin conexión la venta sigue ahí, y al reintentar se envía', (t) async {
      var intentos = 0;
      await lista(t, (pedido) async {
        intentos++;
        if (intentos == 1) throw const ErrorApi(0, 'SIN_CONEXION', 'No hay conexión con el servidor.');
        return pedidoGuardado(pedido);
      });
      await tocarClave(t, 'confirmar-venta');
      expect(
        texto(t, 'error-envio'),
        'No se pudo enviar: no hay conexión con el servidor. La venta sigue aquí; vuelve a intentarlo.',
      );
      await tocarClave(t, 'confirmar-venta');
      expect(intentos, 2);
      expect(texto(t, 'pedido-enviado'), 'Pedido 12 de Ana Prueba enviado a cocina');
      expect(find.byKey(const Key('error-envio')), findsNothing);
    });

    testWidgets('si la carta cambió, dice el total correcto y que no se guardó nada', (t) async {
      await lista(
        t,
        (pedido) async => throw const ErrorApi(409, 'PRECIO_CAMBIADO', 'La carta cambio.', {'totalCorrecto': 55}),
      );
      await tocarClave(t, 'confirmar-venta');
      expect(
        texto(t, 'error-envio'),
        'La carta cambió mientras se armaba la venta y no se guardó nada. '
        'El total correcto es Bs 55. Cancela esta venta y vuelve a armarla.',
      );
    });
  });

  group('la venta directa de bebidas (D-38)', () {
    testWidgets('sin nombre ni preguntas: cobra, y el aviso dice que se registró', (t) async {
      Map<String, dynamic>? enviado;
      await empezar(
        t,
        enviar: (p) async {
          enviado = p;
          return pedidoGuardado(p);
        },
      );
      await tocarClave(t, 'vender-bebidas');
      expect(texto(t, 'cobrar-bebidas'), 'Elige al menos una bebida');
      expect(t.widget<FilledButton>(find.byKey(const Key('cobrar-bebidas'))).onPressed, isNull);
      await tocarClave(t, 'directa-${de('Gaseosa 2 L').id}-mas');
      await tocarClave(t, 'directa-${de('Gaseosa 2 L').id}-mas');
      expect(texto(t, 'cobrar-bebidas'), 'Cobrar · Bs 36');
      await tocarClave(t, 'cobrar-bebidas');
      expect(enviado, {
        'ventaDirecta': true,
        'lineas': [
          {'productoId': de('Gaseosa 2 L').id, 'cantidad': 2},
        ],
        'totalEsperado': 36.0,
      });
      expect(find.byKey(const Key('modal-bebidas')), findsNothing);
      expect(texto(t, 'pedido-enviado'), 'Venta de bebidas registrada · Bs 36');
    });

    testWidgets('no toca la venta que se estaba armando', (t) async {
      await empezar(t, enviar: (p) async => pedidoGuardado(p));
      await escribirCliente(t);
      await agregarPizza(t, 'Peperoni');
      await tocarClave(t, 'vender-bebidas');
      await tocarClave(t, 'directa-${de('Agua mineral 600 ml').id}-mas');
      await tocarClave(t, 'cobrar-bebidas');
      expect(texto(t, 'total-venta'), 'Bs 50');
      expect(t.widget<TextField>(find.byKey(const Key('cliente-nombre'))).controller!.text, 'Ana Prueba');
    });

    testWidgets('si falla, las bebidas quedan elegidas y dice por qué', (t) async {
      await empezar(
        t,
        enviar: (p) async => throw const ErrorApi(0, 'SIN_CONEXION', 'No hay conexión con el servidor.'),
      );
      await tocarClave(t, 'vender-bebidas');
      await tocarClave(t, 'directa-${de('Gaseosa 2 L').id}-mas');
      await tocarClave(t, 'cobrar-bebidas');
      expect(find.byKey(const Key('modal-bebidas')), findsOneWidget);
      expect(texto(t, 'error-bebidas'), startsWith('No se pudo enviar'));
      expect(texto(t, 'cobrar-bebidas'), 'Cobrar · Bs 18');
    });

    testWidgets('cerrarla no vende nada', (t) async {
      var envios = 0;
      await empezar(
        t,
        enviar: (p) async {
          envios++;
          return pedidoGuardado(p);
        },
      );
      await tocarClave(t, 'vender-bebidas');
      await tocarClave(t, 'directa-${de('Gaseosa 2 L').id}-mas');
      await tocarClave(t, 'cerrar-bebidas');
      expect(envios, 0);
      expect(find.byKey(const Key('aviso-enviado')), findsNothing);
    });
  });

  group('según el ancho', () {
    testWidgets('en la computadora, el pedido va a la derecha y la venta no pasa de 1280 px', (t) async {
      await empezar(t, ancho: 1920, alto: 1080);
      final formulario = t.getRect(find.byKey(const Key('formulario-venta')));
      final panel = t.getRect(find.byType(PanelPedido));
      expect(panel.left, greaterThan(formulario.right));
      expect(panel.right - formulario.left, lessThanOrEqualTo(anchoMaximoDeVenta));
      expect(find.byType(Dialog), findsNothing);
      await tocarClave(t, 'agregar-pizza');
      expect(t.getSize(find.byKey(const Key('modal-pizza'))).width, lessThanOrEqualTo(1000));
    });

    testWidgets('en el celular: el total y Confirmar quedan abajo, y el modal ocupa toda la pantalla', (t) async {
      await empezar(t, ancho: 360, alto: 740, enviar: (p) async => pedidoGuardado(p));
      expect(find.byType(PanelPedido), findsNothing);
      final confirmar = t.getRect(find.byKey(const Key('confirmar-venta')));
      expect(confirmar.bottom, greaterThan(640));
      await tocarClave(t, 'agregar-pizza');
      expect(t.getSize(find.byKey(const Key('modal-pizza'))), const Size(360, 740));
      await tocarSabor(t, 'Hawaiana');
      await tocarClave(t, 'listo-pizza');
      expect(texto(t, 'total-venta'), 'Bs 50');
      await tocarClave(t, 'vender-bebidas');
      expect(t.getSize(find.byKey(const Key('modal-bebidas'))), const Size(360, 740));
    });

    testWidgets('en 320 px, el más angosto, nada se desborda', (t) async {
      await empezar(t, ancho: 320, alto: 640, enviar: (p) async => pedidoGuardado(p));
      await escribirCliente(t);
      await agregarPizza(t, 'Salame', mitad: 'Peperoni', extras: ['Extra queso', 'Extra choclo'], cantidad: 3);
      await tocarClave(t, 'confirmar-venta');
      expect(texto(t, 'pedido-enviado'), 'Pedido 12 de Ana Prueba enviado a cocina');
    });
  });
}
