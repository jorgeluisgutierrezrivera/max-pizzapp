// Los pedidos en recepción (RF-03, RF-04, RF-05, RF-09, RF-14): la lista en vivo, lo que
// pasa cuando cocina marca uno listo, y Entregar, Cancelar, Llamar y Agregar, con un canal y
// un timbre de prueba y la API simulada.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/canal_en_vivo.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/pantallas/pantalla_recepcion.dart';
import 'package:maxpizzapp/pantallas/timbre.dart';
import 'package:maxpizzapp/pedidos/pedido.dart';
import 'package:maxpizzapp/pedidos/pedidos_en_vivo.dart';
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
  Future<void> habilitar() async {}
  @override
  void sonar() => sonidos++;
}

final ahora = DateTime.utc(2026, 9, 24, 20, 30);

var _idProducto = 0;
Producto producto(String nombre, String categoria, num precio) => Producto.desdeJson({
  'id': ++_idProducto,
  'nombre': nombre,
  'categoria': categoria,
  'precio': precio,
  'descripcion': null,
  'imagen': null,
  'disponible': true,
});

final carta = Carta([
  producto('Salame', 'pizza', 45),
  producto('Peperoni', 'pizza', 50),
  producto('Extra queso', 'extra', 8),
  producto('Gaseosa 2 L', 'bebida', 18),
]);
Producto de(String nombre) =>
    [...carta.pizzas, ...carta.extras, ...carta.bebidas].firstWhere((p) => p.nombre == nombre);

Map<String, dynamic> jsonPedido(
  int id, {
  String estado = 'pendiente',
  int minutos = 5,
  String cliente = 'Ana Prueba',
  String? celular = '70000001',
  bool paraLlevar = true,
  num total = 50,
  List<Map<String, dynamic>> agregadas = const [],
}) => {
  'id': id,
  'numero': id + 100,
  'version': 1 + agregadas.length,
  'estado': estado,
  'paraLlevar': paraLlevar,
  'cliente': {'nombre': cliente, 'celular': celular},
  'observacion': null,
  'total': total,
  'creadoEn': ahora.subtract(Duration(minutes: minutos)).toIso8601String(),
  'lineas': [
    {
      'producto': {'id': 2, 'nombre': 'Peperoni', 'categoria': 'pizza'},
      'mitad': null,
      'cantidad': 1,
      'agregadoEn': null,
      'extras': [],
    },
    ...agregadas,
  ],
};

final usuario = Usuario.desdeJson({
  'sub': 'x',
  'nombre': 'Recepcion Demo',
  'usuario': 'recepcion.demo',
  'roles': ['recepcion'],
});

/// La API simulada: guarda lo que se le pide y responde como el servidor.
class Escena {
  final canal = CanalDePrueba();
  final timbre = TimbreDePrueba();
  List<Map<String, dynamic>> pedidos = [];
  var lecturas = 0;
  final cambios = <(int, EstadoPedido, int)>[];
  final cancelaciones = <(int, String)>[];
  final agregados = <(int, Map<String, dynamic>)>[];
  final llamadas = <String>[];
  final titulos = <int>[];
  Future<Pedido> Function(Pedido, EstadoPedido)? responderCambio;
  Future<Pedido> Function(Pedido, Map<String, dynamic>)? responderAgregado;

  Widget app() => MaterialApp(
    theme: temaMaxPizzas(),
    home: PantallaRecepcion(
      usuario: usuario,
      alCerrarSesion: () {},
      cargarCarta: () async => carta,
      imagen: (ruta, respaldo, ajuste) => respaldo,
      enviarPedido: (p) async => {},
      cargarPedidos: () async {
        lecturas++;
        return [for (final p in pedidos) Pedido.desdeJson(p)];
      },
      cambiarEstado: (pedido, hacia) async {
        cambios.add((pedido.id, hacia, pedido.version));
        if (responderCambio != null) return responderCambio!(pedido, hacia);
        return pedido.conEstado(hacia);
      },
      cancelarPedido: (pedido, motivo) async {
        cancelaciones.add((pedido.id, motivo));
        return pedido.conEstado(EstadoPedido.cancelado);
      },
      agregarAlPedido: (pedido, cuerpo) async {
        agregados.add((pedido.id, cuerpo));
        if (responderAgregado != null) return responderAgregado!(pedido, cuerpo);
        final original = pedidos.firstWhere((p) => p['id'] == pedido.id);
        return Pedido.desdeJson({...original, 'total': (original['total'] as num) + (cuerpo['totalEsperado'] as num)});
      },
      crearCanal: () => canal,
      timbre: timbre,
      llamar: llamadas.add,
      ponerTitulo: titulos.add,
      reloj: () => ahora,
    ),
  );
}

void tamano(WidgetTester t, double ancho, double alto) {
  t.view.physicalSize = Size(ancho, alto);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Abre recepción y va a la pestaña Pedidos.
Future<Escena> abrir(
  WidgetTester t,
  List<Map<String, dynamic>> pedidos, {
  double ancho = 1400,
  double alto = 1000,
  bool irAPedidos = true,
}) async {
  tamano(t, ancho, alto);
  final e = Escena()..pedidos = pedidos;
  await t.pumpWidget(e.app());
  await t.pumpAndSettle();
  if (irAPedidos) {
    await t.tap(find.byKey(const Key('pestana-pedidos')));
    await t.pumpAndSettle();
  }
  return e;
}

Finder enTarjeta(int id, Finder f) => find.descendant(of: find.byKey(Key('recepcion-pedido-$id')), matching: f);

Future<void> tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  group('la lógica en vivo (PedidosEnVivo)', () {
    Future<(PedidosEnVivo, CanalDePrueba)> iniciar(List<Map<String, dynamic>> pedidos) async {
      final canal = CanalDePrueba();
      final vivos = PedidosEnVivo(cargar: () async => [for (final p in pedidos) Pedido.desdeJson(p)], canal: canal)
        ..iniciar();
      await Future<void>.delayed(Duration.zero);
      return (vivos, canal);
    }

    test('lee los activos: los listos primero, después los de cocina, cada grupo por llegada', () async {
      final (vivos, _) = await iniciar([
        jsonPedido(1, minutos: 20),
        jsonPedido(2, estado: 'listo', minutos: 10),
        jsonPedido(3, estado: 'en_preparacion', minutos: 15),
        jsonPedido(4, estado: 'listo', minutos: 12),
        jsonPedido(5, estado: 'entregado'),
      ]);
      expect(vivos.ordenados.map((p) => p.id), [4, 2, 1, 3]);
      expect(vivos.listos, 2);
    });

    test('un pedido nuevo entra; el mismo aviso dos veces no lo duplica; una venta directa no entra', () async {
      final (vivos, canal) = await iniciar([]);
      canal.nuevos
        ..add(jsonPedido(1))
        ..add(jsonPedido(1))
        ..add({...jsonPedido(2, estado: 'entregado'), 'cliente': null, 'numero': null});
      await Future<void>.delayed(Duration.zero);
      expect(vivos.ordenados.map((p) => p.id), [1]);
    });

    test('cuando cocina lo marca listo, lo avisa una vez; entregado o cancelado, sale', () async {
      final (vivos, canal) = await iniciar([jsonPedido(1, estado: 'en_preparacion'), jsonPedido(2)]);
      final listos = <int>[];
      vivos.quedaronListos.listen((p) => listos.add(p.id));
      canal.cambios
        ..add({'id': 1, 'anterior': 'en_preparacion', 'nuevo': 'listo', 'fechaHora': 'x'})
        ..add({'id': 1, 'anterior': 'en_preparacion', 'nuevo': 'listo', 'fechaHora': 'x'});
      await Future<void>.delayed(Duration.zero);
      expect(listos, [1]);
      expect(vivos.listos, 1);
      canal.cambios.add({'id': 2, 'anterior': 'pendiente', 'nuevo': 'cancelado', 'fechaHora': 'x'});
      await Future<void>.delayed(Duration.zero);
      expect(vivos.ordenados.map((p) => p.id), [1]);
    });

    test('lo agregado reemplaza al pedido, y al reconectarse relee la lista', () async {
      var lecturas = 0;
      final canal = CanalDePrueba();
      var pedidos = [jsonPedido(1)];
      final vivos = PedidosEnVivo(
        cargar: () async {
          lecturas++;
          return [for (final p in pedidos) Pedido.desdeJson(p)];
        },
        canal: canal,
      )..iniciar();
      await Future<void>.delayed(Duration.zero);
      canal.actualizados.add(jsonPedido(1, total: 68));
      await Future<void>.delayed(Duration.zero);
      expect(vivos.ordenados.single.total, 6800);
      pedidos = [jsonPedido(1), jsonPedido(9)];
      canal.estados.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(lecturas, 2);
      expect(vivos.conectado, isTrue);
      expect(vivos.ordenados.map((p) => p.id), [1, 9]);
      vivos.dispose();
      expect(canal.cerrado, isTrue);
    });
  });

  group('las dos pestañas', () {
    testWidgets('Nueva venta y Pedidos, con cuántos hay y cuántos están listos', (t) async {
      await abrir(t, [jsonPedido(1), jsonPedido(2, estado: 'listo')], irAPedidos: false);
      expect(find.text('Nueva venta'), findsOneWidget);
      expect(find.text('Pedidos (2)'), findsOneWidget);
      expect(find.text('1 listo'), findsOneWidget);
    });

    testWidgets('ir a Pedidos y volver no pierde la venta a medio armar', (t) async {
      await abrir(t, [], irAPedidos: false);
      await t.enterText(find.byKey(const Key('cliente-nombre')), 'Ana Prueba');
      await t.tap(find.byKey(const Key('pestana-pedidos')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pestana-venta')));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const Key('cliente-nombre'))).controller!.text, 'Ana Prueba');
    });

    testWidgets('la barra no desborda en ningún ancho, con las pestañas debajo o en la barra', (t) async {
      for (final ancho in [320.0, 360.0, 600.0, 800.0, 1024.0, 1100.0, 1280.0, 1366.0, 1920.0]) {
        await abrir(t, [jsonPedido(1, estado: 'listo'), jsonPedido(2)], ancho: ancho, alto: 800, irAPedidos: false);
        expect(t.takeException(), isNull, reason: '$ancho px');
        expect(find.byKey(const Key('pestana-pedidos')).hitTestable(), findsOneWidget, reason: '$ancho px');
        expect(find.byKey(const Key('pestana-venta')).hitTestable(), findsOneWidget, reason: '$ancho px');
      }
    });

    testWidgets('sin pedidos lo dice, en vez de una pantalla en blanco', (t) async {
      await abrir(t, []);
      expect(find.textContaining('No hay pedidos por atender.'), findsOneWidget);
    });
  });

  group('lo que muestra cada pedido', () {
    testWidgets('número del día, cliente, para llevar, celular, líneas, lo agregado con su hora, total y estado', (
      t,
    ) async {
      final hora = '2026-09-24T20:41:00.000Z';
      await abrir(t, [
        jsonPedido(
          12,
          estado: 'en_preparacion',
          total: 68,
          agregadas: [
            {
              'producto': {'id': 10, 'nombre': 'Gaseosa 2 L', 'categoria': 'bebida'},
              'mitad': null,
              'cantidad': 1,
              'agregadoEn': hora,
              'extras': [],
            },
          ],
        ),
      ]);
      expect(enTarjeta(12, find.text('112')), findsOneWidget);
      expect(enTarjeta(12, find.text('Ana Prueba')), findsOneWidget);
      expect(enTarjeta(12, find.text('– Para llevar')), findsOneWidget);
      expect(enTarjeta(12, find.text('hace 5 min · 70000001')), findsOneWidget);
      expect(enTarjeta(12, find.text('1 × Peperoni')), findsOneWidget);
      expect(
        enTarjeta(12, find.text('1 × Gaseosa 2 L  (agregada ${horaCorta(DateTime.parse(hora))})')),
        findsOneWidget,
      );
      expect(enTarjeta(12, find.text('Bs 68')), findsOneWidget);
      expect(enTarjeta(12, find.text('En preparación')), findsOneWidget);
    });

    testWidgets('el listo ofrece Entregar, Llamar y Agregar bebida; el de cocina, Agregar y Cancelar', (t) async {
      await abrir(t, [jsonPedido(1, estado: 'listo'), jsonPedido(2), jsonPedido(3, estado: 'listo', celular: null)]);
      for (final clave in ['entregar-1', 'llamar-1', 'agregar-1']) {
        expect(find.byKey(Key(clave)), findsOneWidget, reason: clave);
      }
      expect(find.byKey(const Key('cancelar-1')), findsNothing, reason: 'un listo ya no se cancela (RF-09)');
      expect(find.byKey(const Key('llamar-3')), findsNothing, reason: 'sin celular no hay a quién llamar');
      expect(find.byKey(const Key('entregar-2')), findsNothing);
      expect(find.byKey(const Key('cancelar-2')), findsOneWidget);
      expect(find.byKey(const Key('agregar-2')), findsOneWidget);
    });

    testWidgets('en el celular, una columna y sin desbordes', (t) async {
      await abrir(t, [jsonPedido(1, estado: 'listo'), jsonPedido(2)], ancho: 360, alto: 740);
      expect(
        t.getTopLeft(find.byKey(const Key('recepcion-pedido-1'))).dx,
        t.getTopLeft(find.byKey(const Key('recepcion-pedido-2'))).dx,
      );
      expect(t.takeException(), isNull);
    });
  });

  group('cuando cocina lo marca listo (RF-04)', () {
    testWidgets('suena, avisa quién, cuenta en la pestaña y lo dice el título del navegador', (t) async {
      final e = await abrir(t, [jsonPedido(1, estado: 'en_preparacion', cliente: 'Luis Prueba')], irAPedidos: false);
      e.canal.cambios.add({'id': 1, 'anterior': 'en_preparacion', 'nuevo': 'listo', 'fechaHora': 'x'});
      await t.pumpAndSettle();
      expect(e.timbre.sonidos, 1);
      expect(find.text('Pedido 101 de Luis Prueba está listo'), findsOneWidget);
      expect(find.text('1 listo'), findsOneWidget);
      expect(e.titulos.last, 1);
      // "Ver pedidos" lleva a la pestaña, con el listo primero.
      await t.tap(find.text('Ver pedidos'));
      await t.pumpAndSettle();
      expect(enTarjeta(1, find.text('Listo')), findsOneWidget);
    });
  });

  group('entregar (RF-05)', () {
    testWidgets('manda la versión que se ve, sale de la lista y el título vuelve', (t) async {
      final e = await abrir(t, [jsonPedido(1, estado: 'listo')]);
      expect(e.titulos.last, 1);
      await tocar(t, find.byKey(const Key('entregar-1')));
      expect(e.cambios.single, (1, EstadoPedido.entregado, 1));
      expect(find.byKey(const Key('recepcion-pedido-1')), findsNothing);
      expect(find.text('Pedido 101 de Ana Prueba entregado.'), findsOneWidget);
      expect(e.titulos.last, 0);
    });

    testWidgets('si se le agregó algo que no se veía (409 PEDIDO_CAMBIADO), avisa y relee', (t) async {
      final e = await abrir(t, [jsonPedido(1, estado: 'listo')]);
      e.responderCambio = (pedido, hacia) async {
        e.pedidos = [jsonPedido(1, estado: 'listo', total: 68)];
        throw const ErrorApi(409, 'PEDIDO_CAMBIADO', 'Al pedido #1 se le agrego algo.', {'version': 2});
      };
      final lecturas = e.lecturas;
      await tocar(t, find.byKey(const Key('entregar-1')));
      expect(find.text('Al Pedido 101 se le agregó algo. Revísalo antes de entregarlo.'), findsOneWidget);
      expect(e.lecturas, lecturas + 1);
      expect(enTarjeta(1, find.text('Bs 68')), findsOneWidget);
    });
  });

  group('cancelar, con motivo (RF-09, D-33)', () {
    testWidgets('con un motivo rápido', (t) async {
      final e = await abrir(t, [jsonPedido(2)]);
      await tocar(t, find.byKey(const Key('cancelar-2')));
      expect(
        t.widget<FilledButton>(find.byKey(const Key('confirmar-cancelacion'))).onPressed,
        isNull,
        reason: 'sin motivo no se cancela',
      );
      await tocar(t, find.byKey(const Key('motivo-0')));
      await tocar(t, find.byKey(const Key('confirmar-cancelacion')));
      expect(e.cancelaciones.single, (2, 'El cliente se fue'));
      expect(find.byKey(const Key('recepcion-pedido-2')), findsNothing);
    });

    testWidgets('con otro motivo escrito; y "Volver" no cancela nada', (t) async {
      final e = await abrir(t, [jsonPedido(2)]);
      await tocar(t, find.byKey(const Key('cancelar-2')));
      await tocar(t, find.text('Volver'));
      expect(e.cancelaciones, isEmpty);
      await tocar(t, find.byKey(const Key('cancelar-2')));
      await t.enterText(find.byKey(const Key('motivo-otro')), 'Pago rechazado');
      await t.pump();
      await tocar(t, find.byKey(const Key('confirmar-cancelacion')));
      expect(e.cancelaciones.single, (2, 'Pago rechazado'));
    });
  });

  group('llamar (D-31)', () {
    testWidgets('muestra el número grande, lo marca o lo copia', (t) async {
      final copiado = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (llamada) async {
        if (llamada.method == 'Clipboard.setData') copiado.add((llamada.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final e = await abrir(t, [jsonPedido(1, estado: 'listo')]);
      await tocar(t, find.byKey(const Key('llamar-1')));
      expect(find.text('Llamar a Ana Prueba'), findsOneWidget);
      expect(find.text('70000001'), findsWidgets);
      await tocar(t, find.byKey(const Key('marcar-numero')));
      expect(e.llamadas, ['70000001']);
      await tocar(t, find.byKey(const Key('llamar-1')));
      await tocar(t, find.byKey(const Key('copiar-numero')));
      expect(copiado, ['70000001']);
    });
  });

  group('agregar a un pedido ya enviado (RF-14, D-37)', () {
    testWidgets('a uno en cocina: una pizza y una bebida, con el cuerpo exacto y el total nuevo', (t) async {
      final e = await abrir(t, [jsonPedido(2, estado: 'en_preparacion')]);
      await tocar(t, find.byKey(const Key('agregar-2')));
      expect(find.text('Agregar al Pedido 102'), findsOneWidget);
      await tocar(t, find.byKey(const Key('agregar-pizza-al-pedido')));
      await tocar(t, find.byKey(const Key('sabor-Salame')));
      await tocar(t, find.byKey(const Key('listo-pizza')));
      await tocar(t, find.byKey(Key('agregar-bebida-${de('Gaseosa 2 L').id}-mas')));
      expect(find.text('Agregar al pedido · Bs 63'), findsOneWidget);
      await tocar(t, find.byKey(const Key('confirmar-agregado')));
      expect(e.agregados.single.$1, 2);
      expect(e.agregados.single.$2, {
        'lineas': [
          {'productoId': de('Salame').id, 'cantidad': 1},
          {'productoId': de('Gaseosa 2 L').id, 'cantidad': 1},
        ],
        'totalEsperado': 63.0,
      });
      expect(find.byKey(const Key('modal-agregar')), findsNothing);
      expect(enTarjeta(2, find.text('Bs 113')), findsOneWidget);
    });

    testWidgets('a uno listo: solo bebidas, y lo dice', (t) async {
      await abrir(t, [jsonPedido(1, estado: 'listo')]);
      await tocar(t, find.byKey(const Key('agregar-1')));
      expect(find.byKey(const Key('sin-pizzas')), findsOneWidget);
      expect(find.byKey(const Key('agregar-pizza-al-pedido')), findsNothing);
      expect(t.widget<FilledButton>(find.byKey(const Key('confirmar-agregado'))).onPressed, isNull);
    });

    testWidgets('si mientras tanto cocina lo marcó listo, lo explica y lo elegido queda', (t) async {
      final e = await abrir(t, [jsonPedido(2)]);
      e.responderAgregado = (pedido, cuerpo) async =>
          throw const ErrorApi(409, 'AGREGADO_NO_PERMITIDO', 'El pedido #2 ya esta listo.', {'estadoActual': 'listo'});
      await tocar(t, find.byKey(const Key('agregar-2')));
      await tocar(t, find.byKey(const Key('agregar-pizza-al-pedido')));
      await tocar(t, find.byKey(const Key('sabor-Peperoni')));
      await tocar(t, find.byKey(const Key('listo-pizza')));
      await tocar(t, find.byKey(const Key('confirmar-agregado')));
      expect(find.textContaining('cocina lo marcó listo'), findsOneWidget);
      expect(find.byKey(const Key('modal-agregar')), findsOneWidget);
      expect(find.text('Agregar al pedido · Bs 50'), findsOneWidget);
    });
  });
}
