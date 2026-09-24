import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'timbre.dart';

/// El timbre del navegador: dos tonos cortos generados con la Web Audio API, sin archivos de
/// sonido. Solo se importa desde main.dart: las pruebas corren fuera del navegador.
class TimbreWeb implements Timbre {
  web.AudioContext? _contexto;

  @override
  bool get habilitado => _contexto?.state == 'running';

  @override
  Future<void> habilitar() async {
    final contexto = _contexto ??= web.AudioContext();
    await contexto.resume().toDart;
    sonar(); // para que la persona sepa cómo suena
  }

  @override
  void sonar() {
    final contexto = _contexto;
    if (contexto == null || contexto.state != 'running') return;
    final inicio = contexto.currentTime;
    // Dos notas, la segunda más aguda: se distingue de los sonidos del sistema.
    for (final (i, frecuencia) in const [880.0, 1318.5].indexed) {
      final desde = inicio + i * 0.18;
      final oscilador = contexto.createOscillator()
        ..type = 'sine'
        ..frequency.value = frecuencia;
      final volumen = contexto.createGain();
      volumen.gain
        ..setValueAtTime(0, desde)
        ..linearRampToValueAtTime(0.3, desde + 0.02)
        ..exponentialRampToValueAtTime(0.001, desde + 0.35);
      oscilador.connect(volumen);
      volumen.connect(contexto.destination);
      oscilador
        ..start(desde)
        ..stop(desde + 0.4);
    }
  }
}
