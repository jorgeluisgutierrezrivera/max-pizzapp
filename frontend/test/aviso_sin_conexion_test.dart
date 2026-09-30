// El aviso de canal caído (CA-03.2, D-45): cuándo aparece y qué hace Recargar. Los tiempos
// son los del reloj de prueba de Flutter, que la prueba adelanta a mano.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/pantallas/aviso_sin_conexion.dart';
import 'package:maxpizzapp/pantallas/red.dart';
import 'package:maxpizzapp/tema.dart';

class RedDePrueba implements Red {
  final _cambios = StreamController<bool>.broadcast();
  bool _enLinea = true;
  @override
  bool get enLinea => _enLinea;
  @override
  Stream<bool> get cambios => _cambios.stream;
  void cambiar(bool enLinea) {
    _enLinea = enLinea;
    _cambios.add(enLinea);
  }
}

void main() {
  group('cuándo avisar (VigiaDelCanal)', () {
    late StreamController<bool> conexion;
    late RedDePrueba red;

    VigiaDelCanal vigia(WidgetTester t, {bool conectado = false}) {
      conexion = StreamController<bool>.broadcast();
      red = RedDePrueba();
      final v = VigiaDelCanal(conexion: conexion.stream, conectado: conectado, red: red);
      addTearDown(v.dispose);
      return v;
    }

    testWidgets('al abrir espera 5 s a la primera conexión; si no llega, avisa', (t) async {
      final v = vigia(t);
      await t.pump(const Duration(milliseconds: 4900));
      expect(v.mostrar, isFalse);
      await t.pump(const Duration(milliseconds: 200));
      expect(v.mostrar, isTrue);
    });

    testWidgets('si conecta antes de los 5 s, no avisa nunca', (t) async {
      final v = vigia(t);
      await t.pump(const Duration(seconds: 2));
      conexion.add(true);
      await t.pump(const Duration(seconds: 10));
      expect(v.mostrar, isFalse);
    });

    testWidgets('si ya estaba conectado al abrir, no espera ni avisa', (t) async {
      final v = vigia(t, conectado: true);
      await t.pump(const Duration(seconds: 10));
      expect(v.mostrar, isFalse);
    });

    testWidgets('un corte en vivo se avisa al segundo, y el aviso se va cuando vuelve', (t) async {
      final v = vigia(t, conectado: true);
      conexion.add(false);
      await t.pump(const Duration(milliseconds: 900));
      expect(v.mostrar, isFalse);
      await t.pump(const Duration(milliseconds: 200));
      expect(v.mostrar, isTrue);
      conexion.add(true);
      await t.pump();
      expect(v.mostrar, isFalse);
    });

    testWidgets('el corte por vencimiento del token vuelve en milisegundos: no parpadea (D-47)', (t) async {
      final v = vigia(t, conectado: true);
      var avisos = 0;
      v.addListener(() => avisos++);
      conexion.add(false);
      await t.pump(const Duration(milliseconds: 20));
      conexion.add(true);
      await t.pump(const Duration(seconds: 5));
      expect(v.mostrar, isFalse);
      expect(avisos, 0);
    });

    testWidgets('sin red del dispositivo avisa en el acto, aunque el canal figure conectado', (t) async {
      final v = vigia(t, conectado: true);
      red.cambiar(false);
      await t.pump();
      expect(v.mostrar, isTrue);
      red.cambiar(true);
      await t.pump();
      expect(v.mostrar, isFalse);
    });

    testWidgets('con la red de vuelta pero el canal todavía caído, el aviso sigue', (t) async {
      final v = vigia(t, conectado: true);
      red.cambiar(false);
      conexion.add(false);
      await t.pump(const Duration(seconds: 2));
      red.cambiar(true);
      await t.pump();
      expect(v.mostrar, isTrue);
      conexion.add(true);
      await t.pump();
      expect(v.mostrar, isFalse);
    });
  });

  group('la banda (AvisoSinConexion)', () {
    Future<void> mostrar(WidgetTester t, Future<void> Function() alRecargar, {double ancho = 1366}) async {
      t.view.physicalSize = Size(ancho, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: temaMaxPizzas(),
        home: Scaffold(body: Column(children: [AvisoSinConexion(alRecargar: alRecargar)])),
      ));
    }

    testWidgets('dice qué pasa y ofrece Recargar', (t) async {
      await mostrar(t, () async {});
      expect(find.text('Sin conexión en vivo. Lo que ves puede no estar al día.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Recargar'), findsOneWidget);
    });

    testWidgets('Recargar lee de nuevo, dice "Recargando…" y no se puede tocar dos veces', (t) async {
      final lectura = Completer<void>();
      var lecturas = 0;
      await mostrar(t, () {
        lecturas++;
        return lectura.future;
      });
      await t.tap(find.byKey(const Key('boton-recargar')));
      await t.pump();
      expect(find.text('Recargando…'), findsOneWidget);
      await t.tap(find.byKey(const Key('boton-recargar')), warnIfMissed: false);
      await t.pump();
      expect(lecturas, 1);
      lectura.complete();
      await t.pumpAndSettle();
      expect(find.text('Recargar'), findsOneWidget);
    });

    testWidgets('si la lectura falla, el botón vuelve a estar disponible', (t) async {
      await mostrar(t, () async => throw Exception('sin red'));
      await t.tap(find.byKey(const Key('boton-recargar')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Recargar'), findsOneWidget);
    });

    for (final ancho in [320.0, 360.0, 768.0, 1366.0]) {
      testWidgets('a $ancho px no se desborda y el botón queda a la vista', (t) async {
        await mostrar(t, () async {}, ancho: ancho);
        expect(t.takeException(), isNull);
        final boton = t.getRect(find.byKey(const Key('boton-recargar')));
        expect(boton.left, greaterThanOrEqualTo(0));
        expect(boton.right, lessThanOrEqualTo(ancho));
      });
    }
  });
}
