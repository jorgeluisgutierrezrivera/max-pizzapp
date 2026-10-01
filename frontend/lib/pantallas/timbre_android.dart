import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sonido_del_timbre.dart';
import 'timbre.dart';

/// El timbre del APK de cocina (D-50): las mismas dos notas de la web, armadas en memoria
/// (`SonidoDelTimbre`). Solo se importa desde main_cocina.dart.
///
/// En Android ninguna regla exige un toque antes de sonar, como en el navegador: suena desde
/// que se abre la app, así que nunca está pendiente de activar y la franja de sonido apagado
/// no aparece.
///
/// Suena por el **canal de alarma**, no por el multimedia: en una cocina el volumen
/// multimedia suele estar bajo y el teléfono, en silencio, y la alarma suena igual. Se regula
/// con el volumen de las alarmas del teléfono.
class TimbreAndroid implements Timbre {
  /// [reproductor] es para las pruebas; sin él, suena con `audioplayers`.
  TimbreAndroid({ReproductorDelTimbre? reproductor}) : _reproductor = reproductor ?? ReproductorPorAlarma();

  final ReproductorDelTimbre _reproductor;
  late final Uint8List _wav = SonidoDelTimbre.wav();

  @override
  bool get habilitado => true;

  @override
  bool get pendienteDeActivar => false;

  @override
  Listenable get cambios => sinCambios;

  @override
  Future<void> habilitar() async => sonar();

  /// Deja el sonido cargado al abrir la app: el primer pedido de la noche suena en el acto,
  /// sin esperar a que el teléfono prepare el reproductor. Medido en el emulador: el primer
  /// sonido sin preparar llegó 2,4 s después del aviso; los siguientes, a 0,4 s.
  void preparar() => _reproductor.preparar(_wav).catchError(_anotar);

  @override
  void sonar() {
    // Un sonido que falla no puede tumbar la cola: se anota y se sigue.
    _reproductor.reproducir(_wav).catchError(_anotar);
  }

  static void _anotar(Object error) => debugPrint('El timbre no pudo sonar: $error');
}

/// Quién hace sonar las dos notas: en el teléfono, [ReproductorPorAlarma]; en las pruebas,
/// uno que solo cuenta.
abstract class ReproductorDelTimbre {
  Future<void> preparar(Uint8List wav);
  Future<void> reproducir(Uint8List wav);
}

/// Un solo reproductor para toda la app, por el canal de alarma, con el sonido ya cargado.
/// Al terminar vuelve al principio y queda listo para el aviso siguiente.
class ReproductorPorAlarma implements ReproductorDelTimbre {
  Future<AudioPlayer>? _listo;

  @override
  Future<void> preparar(Uint8List wav) => _preparado(wav);

  @override
  Future<void> reproducir(Uint8List wav) async {
    final reproductor = await _preparado(wav);
    // Si dos pedidos llegan juntos, el segundo vuelve a empezar el sonido.
    await reproductor.stop();
    await reproductor.resume();
  }

  Future<AudioPlayer> _preparado(Uint8List wav) => _listo ??= _crear(wav).catchError((Object error, StackTrace pila) {
    _listo = null; // el aviso siguiente lo vuelve a intentar
    Error.throwWithStackTrace(error, pila);
  });

  static Future<AudioPlayer> _crear(Uint8List wav) async {
    final reproductor = AudioPlayer(playerId: 'timbre-de-cocina');
    await reproductor.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          // Baja un momento lo que esté sonando en el teléfono, sin cortarlo.
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
    // Al terminar, el sonido queda cargado y vuelve al principio.
    await reproductor.setReleaseMode(ReleaseMode.stop);
    await reproductor.setSource(BytesSource(wav, mimeType: 'audio/wav'));
    return reproductor;
  }
}
