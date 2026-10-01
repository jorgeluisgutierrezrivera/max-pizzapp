// El timbre del APK de cocina (D-50): suena desde que se abre, sin esperar un toque, así que
// la franja de sonido apagado de la web nunca aparece. El reproductor real (audioplayers, por
// el canal de alarma) se reemplaza por uno que la prueba cuenta.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/pantallas/aviso_sin_sonido.dart';
import 'package:maxpizzapp/pantallas/boton_de_sonido.dart';
import 'package:maxpizzapp/pantallas/sonido_del_timbre.dart';
import 'package:maxpizzapp/pantallas/timbre_android.dart';
import 'package:maxpizzapp/tema.dart';

class ReproductorDePrueba implements ReproductorDelTimbre {
  final preparados = <Uint8List>[];
  final sonados = <Uint8List>[];
  var falla = false;
  @override
  Future<void> preparar(Uint8List wav) async {
    if (falla) throw Exception('sin audio');
    preparados.add(wav);
  }

  @override
  Future<void> reproducir(Uint8List wav) async {
    if (falla) throw Exception('sin audio');
    sonados.add(wav);
  }
}

void main() {
  late ReproductorDePrueba reproductor;
  late TimbreAndroid timbre;

  setUp(() {
    reproductor = ReproductorDePrueba();
    timbre = TimbreAndroid(reproductor: reproductor);
  });

  test('suena desde el arranque: siempre habilitado y nunca pendiente de un toque', () {
    expect(timbre.habilitado, isTrue);
    expect(timbre.pendienteDeActivar, isFalse);
  });

  test('cada aviso reproduce las dos notas de la web', () async {
    timbre
      ..sonar()
      ..sonar();
    await Future<void>.delayed(Duration.zero);
    expect(reproductor.sonados, hasLength(2));
    expect(reproductor.sonados.first, SonidoDelTimbre.wav());
  });

  test('las dos notas se arman una sola vez: lo que se prepara al abrir es lo que suena', () async {
    timbre
      ..preparar()
      ..sonar()
      ..sonar();
    await Future<void>.delayed(Duration.zero);
    expect(identical(reproductor.preparados.single, reproductor.sonados[0]), isTrue);
    expect(identical(reproductor.sonados[0], reproductor.sonados[1]), isTrue);
  });

  test('si el teléfono no puede sonar, no se cae nada: la cola sigue', () async {
    reproductor.falla = true;
    expect(timbre.preparar, returnsNormally);
    expect(timbre.sonar, returnsNormally);
    // Un error sin atender, al llegar, haría fallar la prueba.
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('no hay franja de sonido apagado y la barra muestra que suena, sin botón', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: temaMaxPizzas(),
        home: Scaffold(
          appBar: AppBar(actions: [BotonDeSonido(timbre: timbre)]),
          body: AvisoSinSonido(timbre: timbre),
        ),
      ),
    );
    expect(find.byKey(const Key('aviso-sin-sonido')), findsNothing);
    expect(find.byTooltip('Sonido activado'), findsOneWidget);
    expect(find.text('Activar sonido'), findsNothing);
    expect(find.byIcon(Icons.volume_off), findsNothing);
  });
}
