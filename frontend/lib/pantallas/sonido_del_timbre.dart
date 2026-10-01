import 'dart:math' as math;
import 'dart:typed_data';

/// Las dos notas del timbre como un archivo WAV armado en memoria, para el APK de cocina
/// (D-50). Son las mismas de la web (`timbre_web.dart`): 880 Hz y, 0,18 s después, 1318,5 Hz;
/// cada una sube en 20 ms y se apaga en 0,35 s. Así no hay archivos de sonido en el
/// repositorio y las dos plataformas suenan igual.
///
/// Solo cambia el volumen de cada nota: la web usa 0,3 y el APK, 0,7, porque suena por el
/// canal de alarma de una cocina con ruido. Las notas casi no se pisan, así que la suma no
/// pasa de 0,75 y la onda no se recorta.
abstract final class SonidoDelTimbre {
  static const notas = [880.0, 1318.5];

  /// Cuándo empieza la segunda nota, en segundos.
  static const separacion = 0.18;

  /// Cuánto dura cada nota, en segundos.
  static const duracionDeNota = 0.4;
  static const subida = 0.02;
  static const caida = 0.35;

  /// La calidad de un CD: de sobra para dos notas de menos de 1400 Hz.
  static const muestreo = 44100;
  static const volumen = 0.7;

  static double get duracion => separacion * (notas.length - 1) + duracionDeNota;

  /// El sonido, de -1 a 1, una muestra por cada 1/[muestreo] s.
  static Float64List muestras({int muestreo = muestreo, double volumen = volumen}) {
    final total = (duracion * muestreo).round();
    final salida = Float64List(total);
    for (final (i, frecuencia) in notas.indexed) {
      final desde = (i * separacion * muestreo).round();
      final largo = math.min((duracionDeNota * muestreo).round(), total - desde);
      for (var n = 0; n < largo; n++) {
        final t = n / muestreo;
        salida[desde + n] += volumen * _envolvente(t) * math.sin(2 * math.pi * frecuencia * t);
      }
    }
    return salida;
  }

  /// Igual que en la web: sube en línea recta hasta el volumen, baja en curva hasta una
  /// milésima de su punto más alto y se queda ahí hasta el final de la nota.
  static double _envolvente(double t) {
    if (t < subida) return t / subida;
    if (t < caida) return math.pow(0.001 / 0.3, (t - subida) / (caida - subida)).toDouble();
    return 0.001 / 0.3;
  }

  /// El WAV completo: cabecera RIFF y las muestras en 16 bits, un canal.
  static Uint8List wav({int muestreo = muestreo, double volumen = volumen}) {
    final sonido = muestras(muestreo: muestreo, volumen: volumen);
    const bytesPorMuestra = 2;
    final datos = sonido.length * bytesPorMuestra;
    final b = ByteData(44 + datos);
    void texto(int en, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(en + i, s.codeUnitAt(i));
      }
    }

    texto(0, 'RIFF');
    b.setUint32(4, 36 + datos, Endian.little);
    texto(8, 'WAVE');
    texto(12, 'fmt ');
    b.setUint32(16, 16, Endian.little); // largo de esta parte
    b.setUint16(20, 1, Endian.little); // PCM, sin compresión
    b.setUint16(22, 1, Endian.little); // un canal
    b.setUint32(24, muestreo, Endian.little);
    b.setUint32(28, muestreo * bytesPorMuestra, Endian.little); // bytes por segundo
    b.setUint16(32, bytesPorMuestra, Endian.little);
    b.setUint16(34, 16, Endian.little); // bits por muestra
    texto(36, 'data');
    b.setUint32(40, datos, Endian.little);
    for (final (i, valor) in sonido.indexed) {
      b.setInt16(44 + i * bytesPorMuestra, (valor.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }
}
