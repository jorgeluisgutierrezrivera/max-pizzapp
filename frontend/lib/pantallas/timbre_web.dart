import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'timbre.dart';

/// El timbre del navegador: dos tonos cortos generados con la Web Audio API, sin archivos de
/// sonido. Solo se importa desde main.dart: las pruebas corren fuera del navegador.
///
/// Se activa solo (pedido del autor, 25-sep): al abrir la página lo intenta, y si el
/// navegador todavía no lo permite, lo vuelve a intentar con el primer toque o tecla en
/// cualquier parte de la pantalla, que sí cuenta como uso de la persona.
class TimbreWeb implements Timbre {
  TimbreWeb() {
    _intentar();
    _escucharPrimerToque();
  }

  web.AudioContext? _contexto;
  final _activo = ValueNotifier(false);
  JSFunction? _alTocar;

  static const _eventos = ['pointerdown', 'keydown', 'touchstart'];

  @override
  bool get habilitado => _contexto?.state == 'running';

  @override
  Listenable get cambios => _activo;

  /// Crea el contexto de audio y le pide que arranque. Si el navegador ya confía en el sitio,
  /// arranca en el momento; si no, queda en espera hasta un toque de la persona.
  void _intentar() {
    final contexto = _contexto ??= web.AudioContext();
    if (contexto.state == 'running') {
      _alActivarse();
      return;
    }
    contexto.resume().toDart.then((_) {
      if (habilitado) _alActivarse();
    }, onError: (_) {});
  }

  void _escucharPrimerToque() {
    _alTocar = ((web.Event _) => _intentar()).toJS;
    for (final evento in _eventos) {
      web.document.addEventListener(evento, _alTocar, web.AddEventListenerOptions(capture: true));
    }
  }

  void _alActivarse() {
    _activo.value = true;
    final alTocar = _alTocar;
    if (alTocar == null) return;
    for (final evento in _eventos) {
      web.document.removeEventListener(evento, alTocar, web.EventListenerOptions(capture: true));
    }
    _alTocar = null;
  }

  @override
  Future<void> habilitar() async {
    final contexto = _contexto ??= web.AudioContext();
    await contexto.resume().toDart;
    if (habilitado) _alActivarse();
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
