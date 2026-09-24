import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/pantallas/segun_rol.dart';

Usuario usuarioCon(List<String> roles, {String nombre = 'Persona de prueba'}) =>
    Usuario.desdeJson({'sub': 'x', 'nombre': nombre, 'usuario': 'cuenta', 'roles': roles});

Widget app(Future<Usuario> Function() cargar, {VoidCallback? alCerrar}) => MaterialApp(
      home: PantallaSegunRol(
        cargarUsuario: cargar,
        cargarCarta: () async => Carta(const []),
        alCerrarSesion: alCerrar ?? () {},
      ),
    );

void main() {
  testWidgets('mientras el servidor responde, muestra que esta verificando', (t) async {
    final pendiente = Completer<Usuario>();
    await t.pumpWidget(app(() => pendiente.future));
    expect(find.text('Verificando tu cuenta…'), findsOneWidget);
    pendiente.complete(usuarioCon(['recepcion']));
    await t.pumpAndSettle();
  });

  testWidgets('recepcion va a la pantalla de recepcion, con su nombre', (t) async {
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
    await t.pumpWidget(app(() async {
      intentos++;
      if (intentos == 1) {
        throw const ErrorApi(0, 'SIN_CONEXION', 'No hay conexión con el servidor.');
      }
      return usuarioCon(['cocina']);
    }));
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
}
