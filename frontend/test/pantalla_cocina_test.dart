// La cola de cocina (RF-06, RF-07): lo que ve y lo que hace el cocinero, con un canal en
// vivo y un timbre de mentira que la prueba controla.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/canal_en_vivo.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/pantallas/pantalla_cocina.dart';
import 'package:maxpizzapp/pantallas/timbre.dart';
import 'package:maxpizzapp/pedidos/pedido.dart';
import 'package:maxpizzapp/tema.dart';

class CanalDePrueba implements CanalEnVivo {
  final nuevos = StreamController<Map<String, dynamic>>.broadcast();
  final cambios = StreamController<Map<String, dynamic>>.broadcast();
  final actualizados = StreamController<Map<String, dynamic>>.broadcast();
  final estados = StreamController<bool>.broadcast();
  var conexiones = 0;
  var cerrado = false;
  @override
  Stream<Map<String, dynamic>> get pedidosNuevos => nuevos.stream;
  @override
  Stream<Map<String, dynamic>> get cambiosDeEstado => cambios.stream;
  @override
  Stream<Map<String, dynamic>> get pedidosActualizados => actualizados.stream;
  @override
  Stream<bool> get conexion => estados.stream;
  @override
  bool get conectado => false;
  @override
  void conectar() => conexiones++;
  @override
  void cerrar() => cerrado = true;
}

class TimbreDePrueba implements Timbre {
  var sonidos = 0;
  final activo = ValueNotifier(false);
  @override
  bool get habilitado => activo.value;
  @override
  Listenable get cambios => activo;
  @override
  Future<void> habilitar() async => activo.value = true;
  @override
  void sonar() => sonidos++;
}

final ahora = DateTime.utc(2026, 9, 24, 20, 30);

Map<String, dynamic> json(
  int id, {
  String estado = 'pendiente',
  int minutos = 5,
  String cliente = 'Ana Prueba',
  String? observacion,
  int? numero = -1,
  List<Map<String, dynamic>> agregadas = const [],
}) => {
  'id': id,
  // El número del día (D-35): por omisión, el id más 100, para que no se confundan.
  'numero': numero == -1 ? id + 100 : numero,
  'version': 3 + agregadas.length,
  'estado': estado,
  'paraLlevar': id.isEven,
  'cliente': {'nombre': cliente},
  'observacion': observacion,
  'total': 95,
  'creadoEn': ahora.subtract(Duration(minutes: minutos)).toIso8601String(),
  'lineas': [
    {
      'producto': {'id': 1, 'nombre': 'Salame', 'categoria': 'pizza'},
      'mitad': {'id': 2, 'nombre': 'Peperoni'},
      'cantidad': 2,
      'extras': [
        {
          'producto': {'id': 20, 'nombre': 'Extra queso'},
          'cantidad': 2,
        },
      ],
    },
    {
      'producto': {'id': 10, 'nombre': 'Gaseosa 2 L', 'categoria': 'bebida'},
      'mitad': null,
      'cantidad': 2,
      'extras': [],
    },
    ...agregadas,
  ],
};

/// Una pizza agregada después de enviar el pedido (D-37), a las 20:41 UTC.
final pizzaAgregada = {
  'producto': {'id': 3, 'nombre': 'Hawaiana', 'categoria': 'pizza'},
  'mitad': null,
  'cantidad': 1,
  'agregadoEn': '2026-09-24T20:41:00.000Z',
  'extras': [],
};

final usuario = Usuario.desdeJson({
  'sub': 'x',
  'nombre': 'Cocina Demo',
  'usuario': 'cocina.demo',
  'roles': ['cocina'],
});

class Escena {
  final canal = CanalDePrueba();
  final timbre = TimbreDePrueba();
  final cambios = <(int, EstadoPedido)>[];
  final versiones = <int>[];
  var lecturas = 0;
  List<Map<String, dynamic>> cola = [];
  Future<Pedido> Function(int, EstadoPedido)? responder;

  Widget app() => MaterialApp(
    theme: temaMaxPizzas(),
    home: PantallaCocina(
      usuario: usuario,
      alCerrarSesion: () {},
      cargarCola: () async {
        lecturas++;
        return [for (final p in cola) Pedido.desdeJson(p)];
      },
      cambiarEstado: (pedido, hacia) async {
        final id = pedido.id;
        cambios.add((id, hacia));
        versiones.add(pedido.version);
        if (responder != null) return responder!(id, hacia);
        final original = cola.firstWhere((p) => p['id'] == id);
        return Pedido.desdeJson({...original, 'estado': hacia.nombreApi});
      },
      crearCanal: () => canal,
      timbre: timbre,
      reloj: () => ahora,
    ),
  );
}

void tamano(WidgetTester t, double ancho, double alto) {
  t.view.physicalSize = Size(ancho, alto);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<Escena> abrir(WidgetTester t, List<Map<String, dynamic>> cola, {double ancho = 1400, double alto = 900}) async {
  tamano(t, ancho, alto);
  final e = Escena()..cola = cola;
  await t.pumpWidget(e.app());
  await t.pumpAndSettle();
  return e;
}

Finder enTarjeta(int id, Finder f) => find.descendant(of: find.byKey(Key('pedido-$id')), matching: f);

void main() {
  group('los estados de la pantalla', () {
    testWidgets('cargando, y luego la cola', (t) async {
      tamano(t, 1400, 900);
      final e = Escena()..cola = [json(1)];
      await t.pumpWidget(e.app());
      expect(find.text('Cargando la cola…'), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pedido-1')), findsOneWidget);
    });

    testWidgets('sin pedidos lo dice, en vez de una pantalla en blanco', (t) async {
      await abrir(t, []);
      expect(
        find.text('No hay pedidos en cocina.\nLos nuevos aparecen aquí solos, en orden de llegada.'),
        findsOneWidget,
      );
      expect(find.text('0 pedidos en cocina'), findsOneWidget);
    });

    testWidgets('si la API falla, el mensaje y Reintentar', (t) async {
      tamano(t, 1400, 900);
      var intentos = 0;
      final canal = CanalDePrueba();
      await t.pumpWidget(
        MaterialApp(
          theme: temaMaxPizzas(),
          home: PantallaCocina(
            usuario: usuario,
            alCerrarSesion: () {},
            cargarCola: () async {
              intentos++;
              if (intentos == 1) {
                throw const ErrorApi(503, 'BASE_NO_DISPONIBLE', 'No se pueden leer los datos en este momento.');
              }
              return const [];
            },
            cambiarEstado: (pedido, hacia) => throw UnimplementedError(),
            crearCanal: () => canal,
            timbre: TimbreDePrueba(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('No se pueden leer los datos en este momento.'), findsOneWidget);
      await t.tap(find.text('Reintentar'));
      await t.pumpAndSettle();
      expect(find.text('0 pedidos en cocina'), findsOneWidget);
    });

    testWidgets('se conecta al canal al abrir y lo cierra al salir', (t) async {
      final e = await abrir(t, []);
      expect(e.canal.conexiones, 1);
      await t.pumpWidget(const SizedBox());
      expect(e.canal.cerrado, isTrue);
    });
  });

  group('lo que muestra cada pedido', () {
    testWidgets('número, cliente, para llevar, las pizzas con mitades y extras, las bebidas aparte y la observación', (
      t,
    ) async {
      await abrir(t, [json(12, observacion: 'Sin cebolla')]);
      // El número del día, grande: el que se canta (D-35).
      expect(t.widget<Text>(find.byKey(const Key('numero-12'))).data, '112');
      expect(enTarjeta(12, find.text('Ana Prueba')), findsOneWidget);
      expect(enTarjeta(12, find.text('Para llevar')), findsOneWidget);
      expect(enTarjeta(12, find.text('2 × Mitad Salame / mitad Peperoni', findRichText: true)), findsOneWidget);
      expect(enTarjeta(12, find.text('+ Extra queso')), findsOneWidget);
      expect(enTarjeta(12, find.text('2 × Gaseosa 2 L')), findsOneWidget);
      expect(enTarjeta(12, find.text('Sin cebolla')), findsOneWidget);
      expect(enTarjeta(12, find.text('hace 5 min')), findsOneWidget);
    });

    testWidgets('en orden de llegada: el que más espera va primero', (t) async {
      await abrir(t, [json(3, minutos: 2), json(1, minutos: 9), json(2, minutos: 5)]);
      final x = [
        for (final id in [1, 2, 3]) t.getTopLeft(find.byKey(Key('pedido-$id'))).dx,
      ];
      expect(x, orderedEquals([...x]..sort()), reason: '#1, #2 y #3, de izquierda a derecha');
      expect(find.text('3 pedidos en cocina'), findsOneWidget);
    });

    testWidgets('en la computadora van varias columnas; en el celular, una, sin desbordes', (t) async {
      await abrir(t, [json(1), json(2), json(3)]);
      expect(t.getTopLeft(find.byKey(const Key('pedido-1'))).dy, t.getTopLeft(find.byKey(const Key('pedido-3'))).dy);
      await abrir(t, [json(1), json(2)], ancho: 320, alto: 640);
      expect(t.getTopLeft(find.byKey(const Key('pedido-1'))).dx, t.getTopLeft(find.byKey(const Key('pedido-2'))).dx);
      expect(t.takeException(), isNull);
    });
  });

  group('empezar y marcar listo', () {
    testWidgets('Empezar lo pasa a en preparación; Listo lo saca de la cola', (t) async {
      final e = await abrir(t, [json(7)]);
      await t.tap(enTarjeta(7, find.text('Empezar')));
      await t.pumpAndSettle();
      expect(e.cambios.single, (7, EstadoPedido.enPreparacion));
      expect(enTarjeta(7, find.text('En preparación')), findsOneWidget);
      e.cola = [json(7, estado: 'en_preparacion')];
      await t.tap(enTarjeta(7, find.text('Listo')));
      await t.pumpAndSettle();
      expect(e.cambios.last, (7, EstadoPedido.listo));
      expect(find.byKey(const Key('pedido-7')), findsNothing, reason: 'lo entrega recepción');
    });

    testWidgets('mientras el cambio viaja, el botón espera: dos toques no son dos cambios', (t) async {
      final e = await abrir(t, [json(7)]);
      final respuesta = Completer<Pedido>();
      e.responder = (id, hacia) => respuesta.future;
      await t.tap(enTarjeta(7, find.text('Empezar')));
      await t.pump();
      await t.tap(enTarjeta(7, find.text('Empezar')), warnIfMissed: false);
      await t.pump();
      expect(e.cambios, hasLength(1));
      respuesta.complete(Pedido.desdeJson(json(7, estado: 'en_preparacion')));
      await t.pumpAndSettle();
      expect(enTarjeta(7, find.text('Listo')), findsOneWidget);
    });

    testWidgets('si otro lo cambió antes (409), avisa y relee la cola', (t) async {
      final e = await abrir(t, [json(7)]);
      e.responder = (id, hacia) async {
        e.cola = [];
        throw const ErrorApi(409, 'TRANSICION_NO_PERMITIDA', 'El pedido #7 esta cancelado.');
      };
      final lecturas = e.lecturas;
      await t.tap(enTarjeta(7, find.text('Empezar')));
      await t.pumpAndSettle();
      expect(find.text('El Pedido 107 ya había cambiado. La cola se actualizó.'), findsOneWidget);
      expect(e.lecturas, lecturas + 1);
      expect(find.byKey(const Key('pedido-7')), findsNothing);
    });
  });

  group('en vivo', () {
    testWidgets('un pedido nuevo aparece solo, al final, marcado "Nuevo", y suena el timbre', (t) async {
      final e = await abrir(t, [json(1, minutos: 8)]);
      e.canal.nuevos.add(json(2, minutos: 0));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pedido-2')), findsOneWidget);
      expect(enTarjeta(2, find.text('Nuevo')), findsOneWidget);
      expect(enTarjeta(2, find.text('recién llegado')), findsOneWidget);
      expect(e.timbre.sonidos, 1);
      expect(find.text('2 pedidos en cocina'), findsOneWidget);
      // Pasado el minuto, la marca se va.
      await t.pump(const Duration(minutes: 1, seconds: 1));
      expect(enTarjeta(2, find.text('Nuevo')), findsNothing);
    });

    testWidgets('el mismo aviso dos veces no duplica el pedido ni suena dos veces', (t) async {
      final e = await abrir(t, []);
      e.canal.nuevos
        ..add(json(2))
        ..add(json(2));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pedido-2')), findsOneWidget);
      expect(e.timbre.sonidos, 1);
    });

    testWidgets('un pedido que ya nace listo (solo bebidas) no entra a la cola', (t) async {
      final e = await abrir(t, []);
      e.canal.nuevos.add(json(5, estado: 'listo'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pedido-5')), findsNothing);
      expect(e.timbre.sonidos, 0);
    });

    testWidgets('si otro dispositivo lo empieza, la tarjeta se actualiza sola', (t) async {
      final e = await abrir(t, [json(3)]);
      e.canal.cambios.add({'id': 3, 'anterior': 'pendiente', 'nuevo': 'en_preparacion', 'fechaHora': 'x'});
      await t.pumpAndSettle();
      expect(enTarjeta(3, find.text('Listo')), findsOneWidget);
    });

    testWidgets('si recepción lo cancela, sale de la cola y cocina se entera', (t) async {
      final e = await abrir(t, [json(3, cliente: 'Luis Prueba')]);
      e.canal.cambios.add({'id': 3, 'anterior': 'pendiente', 'nuevo': 'cancelado', 'fechaHora': 'x'});
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pedido-3')), findsNothing);
      expect(find.text('Recepción canceló el Pedido 103 de Luis Prueba.'), findsOneWidget);
      await t.tap(find.byTooltip('Cerrar aviso'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('aviso-cocina')), findsNothing);
    });

    testWidgets('al reconectarse, relee la cola: pudo perderse algún aviso', (t) async {
      final e = await abrir(t, [json(1)]);
      expect(find.text('Conectando…'), findsOneWidget);
      e.cola = [json(1), json(4)];
      final lecturas = e.lecturas;
      e.canal.estados.add(true);
      await t.pumpAndSettle();
      expect(find.text('En vivo'), findsOneWidget);
      expect(e.lecturas, lecturas + 1);
      expect(find.byKey(const Key('pedido-4')), findsOneWidget);
    });
  });

  group('el número del día y lo agregado (D-35, D-37)', () {
    testWidgets('un pedido anterior al número del día muestra su identificador', (t) async {
      await abrir(t, [json(9, numero: null)]);
      expect(t.widget<Text>(find.byKey(const Key('numero-9'))).data, '#9');
    });

    testWidgets('Empezar y Listo mandan la versión del pedido que se ve', (t) async {
      final e = await abrir(t, [json(7)]);
      await t.tap(enTarjeta(7, find.text('Empezar')));
      await t.pumpAndSettle();
      expect(e.versiones, [3]);
    });

    testWidgets('si recepción le agregó algo que no se veía (409 PEDIDO_CAMBIADO), avisa y relee', (t) async {
      final e = await abrir(t, [json(7, estado: 'en_preparacion')]);
      e.responder = (id, hacia) async {
        e.cola = [
          json(7, estado: 'en_preparacion', agregadas: [pizzaAgregada]),
        ];
        throw const ErrorApi(409, 'PEDIDO_CAMBIADO', 'Al pedido #7 se le agrego algo.', {'version': 4});
      };
      await t.tap(enTarjeta(7, find.text('Listo')));
      await t.pumpAndSettle();
      expect(find.text('Al Pedido 107 se le agregó algo. Revísalo antes de marcarlo listo.'), findsOneWidget);
      expect(find.byKey(const Key('pedido-7')), findsOneWidget, reason: 'sigue en la cola');
      expect(enTarjeta(7, find.text('1 × Hawaiana', findRichText: true)), findsOneWidget);
    });

    testWidgets('lo agregado llega en vivo: la tarjeta se actualiza, se marca y suena', (t) async {
      final e = await abrir(t, [json(4, estado: 'en_preparacion')]);
      e.canal.actualizados.add(json(4, estado: 'en_preparacion', agregadas: [pizzaAgregada]));
      await t.pumpAndSettle();
      expect(e.timbre.sonidos, 1);
      expect(enTarjeta(4, find.text('Se agregó algo')), findsOneWidget);
      expect(enTarjeta(4, find.text('1 × Hawaiana', findRichText: true)), findsOneWidget);
      final hora = horaCorta(DateTime.parse('2026-09-24T20:41:00.000Z'));
      expect(enTarjeta(4, find.text('Agregada $hora')), findsOneWidget);
      // La marca de la tarjeta se va al minuto; la de la línea queda.
      await t.pump(const Duration(minutes: 1, seconds: 1));
      expect(enTarjeta(4, find.text('Se agregó algo')), findsNothing);
      expect(enTarjeta(4, find.text('Agregada $hora')), findsOneWidget);
    });

    testWidgets('lo agregado a un pedido que no está en la cola no hace nada', (t) async {
      final e = await abrir(t, [json(4)]);
      e.canal.actualizados.add(json(8, estado: 'listo', agregadas: [pizzaAgregada]));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pedido-8')), findsNothing);
      expect(e.timbre.sonidos, 0);
    });
  });

  group('el sonido', () {
    testWidgets('en una tableta la barra no desborda: el sonido queda como ícono', (t) async {
      for (final ancho in [600.0, 800.0, 999.0]) {
        await abrir(t, [], ancho: ancho, alto: 800);
        expect(t.takeException(), isNull, reason: '$ancho px');
        expect(find.byTooltip('Activar sonido: se activa al tocar la pantalla'), findsOneWidget);
      }
    });

    testWidgets('viene activado: se enciende solo con el primer toque en la pantalla, y la barra lo muestra', (
      t,
    ) async {
      final e = await abrir(t, []);
      expect(find.text('Activar sonido'), findsOneWidget);
      // El timbre del navegador se activa con el primer toque en cualquier parte y avisa.
      e.timbre.activo.value = true;
      await t.pump();
      expect(find.text('Activar sonido'), findsNothing);
      expect(find.byTooltip('Sonido activado'), findsOneWidget);
    });

    testWidgets('"Activar sonido" lo habilita con un toque, y después queda el ícono', (t) async {
      final e = await abrir(t, []);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Activar sonido'));
      await t.pumpAndSettle();
      expect(e.timbre.habilitado, isTrue);
      expect(find.text('Activar sonido'), findsNothing);
      expect(find.byTooltip('Sonido activado'), findsOneWidget);
    });
  });
}
