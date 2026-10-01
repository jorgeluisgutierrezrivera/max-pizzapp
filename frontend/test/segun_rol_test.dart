import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/pantallas/pantalla_encendida.dart';
import 'package:maxpizzapp/pantallas/segun_rol.dart';

Usuario usuarioCon(List<String> roles, {String nombre = 'Persona de prueba'}) =>
    Usuario.desdeJson({'sub': 'x', 'nombre': nombre, 'usuario': 'cuenta', 'roles': roles});

Widget app(
  Future<Usuario> Function() cargar, {
  VoidCallback? alCerrar,
  Uri? webDeRecepcion,
  PantallaEncendida pantallaEncendida = const PantallaSegunElSistema(),
}) => MaterialApp(
  home: PantallaSegunRol(
    cargarUsuario: cargar,
    cargarCarta: () async => Carta(const []),
    alCerrarSesion: alCerrar ?? () {},
    webDeRecepcion: webDeRecepcion,
    pantallaEncendida: pantallaEncendida,
  ),
);

/// La pantalla siempre encendida del APK (D-50), contada.
class PantallaDePrueba implements PantallaEncendida {
  var mantenida = 0;
  @override
  void mantener() => mantenida++;
  @override
  void soltar() {}
}

void main() {
  testWidgets('mientras el servidor responde, muestra que esta verificando', (t) async {
    final pendiente = Completer<Usuario>();
    await t.pumpWidget(app(() => pendiente.future));
    expect(find.text('Verificando tu cuenta…'), findsOneWidget);
    pendiente.complete(usuarioCon(['recepcion']));
    await t.pumpAndSettle();
  });

  testWidgets('recepcion va a la pantalla de recepcion, con su nombre', (t) async {
    // En una pantalla de escritorio grande: en una tableta, o con las pestañas de recepción en
    // la barra, el nombre les cede el lugar.
    t.view.physicalSize = const Size(1440, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(() async => usuarioCon(['recepcion'], nombre: 'Ana Prueba')));
    await t.pumpAndSettle();
    expect(find.text('Recepción'), findsOneWidget);
    expect(find.text('Ana Prueba'), findsOneWidget);
    expect(find.text('Cocina'), findsNothing);
  });

  testWidgets('cocina va a la pantalla de cocina', (t) async {
    await t.pumpWidget(app(() async => usuarioCon(['cocina'])));
    await t.pumpAndSettle();
    expect(find.text('Cocina'), findsOneWidget);
    expect(find.text('Recepción'), findsNothing);
  });

  testWidgets('el error de la API se muestra con su mensaje y se puede reintentar', (t) async {
    var intentos = 0;
    await t.pumpWidget(
      app(() async {
        intentos++;
        if (intentos == 1) {
          throw const ErrorApi(0, 'SIN_CONEXION', 'No hay conexión con el servidor.');
        }
        return usuarioCon(['cocina']);
      }),
    );
    await t.pumpAndSettle();
    expect(find.text('No hay conexión con el servidor.'), findsOneWidget);

    await t.tap(find.text('Reintentar'));
    await t.pumpAndSettle();
    expect(intentos, 2);
    expect(find.text('Cocina'), findsOneWidget);
  });

  testWidgets('una cuenta sin rol del sistema no entra a ninguna pantalla', (t) async {
    await t.pumpWidget(app(() async => usuarioCon([])));
    await t.pumpAndSettle();
    expect(find.textContaining('no tiene un rol'), findsOneWidget);
    expect(find.text('Recepción'), findsNothing);
    expect(find.text('Cocina'), findsNothing);
  });

  testWidgets('cerrar sesion desde la pantalla del rol avisa a quien corresponde', (t) async {
    var cerro = false;
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(() async => usuarioCon(['recepcion']), alCerrar: () => cerro = true));
    await t.pumpAndSettle();
    await t.tap(find.text('Cerrar sesión'));
    expect(cerro, isTrue);
  });

  testWidgets('en el celular, salir queda como icono', (t) async {
    t.view.physicalSize = const Size(375, 812);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(() async => usuarioCon(['recepcion'])));
    await t.pumpAndSettle();
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsNothing);
  });

  group('en el APK de cocina (D-48)', () {
    final web = Uri.parse('https://maxpizzapp.tech');

    testWidgets('una cuenta de recepcion ve que la app es para cocina y puede salir', (t) async {
      var cerro = false;
      await t.pumpWidget(app(() async => usuarioCon(['recepcion']), alCerrar: () => cerro = true, webDeRecepcion: web));
      await t.pumpAndSettle();
      expect(find.text('Esta app es para cocina. Recepción trabaja en la web: maxpizzapp.tech'), findsOneWidget);
      expect(find.text('Recepción'), findsNothing);
      expect(find.text('Reintentar'), findsNothing, reason: 'reintentar no cambia nada');
      await t.tap(find.text('Cerrar sesión'));
      expect(cerro, isTrue);
    });

    testWidgets('cocina entra a su pantalla, igual que en la web', (t) async {
      await t.pumpWidget(app(() async => usuarioCon(['cocina']), webDeRecepcion: web));
      await t.pumpAndSettle();
      expect(find.text('Cocina'), findsOneWidget);
      expect(find.textContaining('Esta app es para cocina'), findsNothing);
    });

    testWidgets('la pantalla encendida es de la cola de cocina: el aviso de recepcion no la pide', (t) async {
      final pantalla = PantallaDePrueba();
      await t.pumpWidget(app(() async => usuarioCon(['cocina']), webDeRecepcion: web, pantallaEncendida: pantalla));
      await t.pumpAndSettle();
      expect(pantalla.mantenida, 1);

      final otra = PantallaDePrueba();
      await t.pumpWidget(app(() async => usuarioCon(['recepcion']), webDeRecepcion: web, pantallaEncendida: otra));
      await t.pumpAndSettle();
      expect(otra.mantenida, 0);
    });

    testWidgets('el aviso cabe en un celular angosto', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(() async => usuarioCon(['recepcion']), webDeRecepcion: web));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('Esta app es para cocina'), findsOneWidget);
    });
  });
}
