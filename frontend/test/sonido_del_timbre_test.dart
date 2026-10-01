// Las dos notas del timbre del APK (D-50), armadas en memoria: que el WAV sea válido, que
// dure lo que dura en la web, que suene fuerte sin recortarse y que sean las notas de la web.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/pantallas/sonido_del_timbre.dart';

String texto(ByteData b, int desde) => String.fromCharCodes(List.generate(4, (i) => b.getUint8(desde + i)));

/// Cuánto pesa una frecuencia en un tramo del sonido (algoritmo de Goertzel).
double peso(List<double> sonido, double frecuencia, {required double desde, required double hasta}) {
  const muestreo = SonidoDelTimbre.muestreo;
  final coeficiente = 2 * math.cos(2 * math.pi * frecuencia / muestreo);
  var a = 0.0, b = 0.0;
  for (var n = (desde * muestreo).round(); n < (hasta * muestreo).round(); n++) {
    final c = sonido[n] + coeficiente * a - b;
    b = a;
    a = c;
  }
  return a * a + b * b - coeficiente * a * b;
}

void main() {
  final wav = SonidoDelTimbre.wav();
  final b = ByteData.sublistView(wav);
  final muestras = [for (var i = 44; i < wav.length; i += 2) b.getInt16(i, Endian.little) / 32767];

  group('el archivo WAV', () {
    test('tiene la cabecera de un WAV PCM de 16 bits, un canal, a 44 100 Hz', () {
      expect(texto(b, 0), 'RIFF');
      expect(b.getUint32(4, Endian.little), wav.length - 8);
      expect(texto(b, 8), 'WAVE');
      expect(texto(b, 12), 'fmt ');
      expect(b.getUint16(20, Endian.little), 1, reason: 'PCM, sin compresión');
      expect(b.getUint16(22, Endian.little), 1, reason: 'un canal');
      expect(b.getUint32(24, Endian.little), 44100);
      expect(b.getUint32(28, Endian.little), 44100 * 2);
      expect(b.getUint16(32, Endian.little), 2);
      expect(b.getUint16(34, Endian.little), 16);
      expect(texto(b, 36), 'data');
      expect(b.getUint32(40, Endian.little), wav.length - 44);
    });

    test('dura 0,58 s, como en la web: la segunda nota a los 0,18 s y cada una de 0,4 s', () {
      expect(SonidoDelTimbre.duracion, closeTo(0.58, 1e-9));
      expect(muestras.length, (0.58 * 44100).round());
    });

    test('pesa poco: se arma una sola vez y se guarda en memoria', () {
      expect(wav.length, lessThan(60 * 1024));
    });
  });

  group('el sonido', () {
    final pico = muestras.map((m) => m.abs()).reduce(math.max);

    test('suena fuerte y no se recorta: el pico queda entre 0,6 y 0,8', () {
      expect(pico, greaterThan(0.6));
      expect(pico, lessThan(0.8));
      expect(muestras.where((m) => m.abs() >= 0.999), isEmpty, reason: 'ninguna muestra en el tope');
    });

    test('empieza y termina en silencio, sin chasquidos', () {
      expect(muestras.first, 0);
      expect(muestras.take(10).map((m) => m.abs()).reduce(math.max), lessThan(0.05));
      expect(muestras.skip(muestras.length - 100).map((m) => m.abs()).reduce(math.max), lessThan(0.01));
    });

    test('son las notas de la web: primero 880 Hz y después 1318,5 Hz', () {
      final primera = (desde: 0.02, hasta: 0.17);
      final segunda = (desde: 0.20, hasta: 0.35);
      expect(
        peso(muestras, 880, desde: primera.desde, hasta: primera.hasta),
        greaterThan(20 * peso(muestras, 1318.5, desde: primera.desde, hasta: primera.hasta)),
      );
      expect(
        peso(muestras, 1318.5, desde: segunda.desde, hasta: segunda.hasta),
        greaterThan(20 * peso(muestras, 880, desde: segunda.desde, hasta: segunda.hasta)),
      );
    });

    test('cada nota sube rápido y se apaga: a los 0,15 s la primera ya bajó a menos de un octavo', () {
      double fuerza(double desde, double hasta) =>
          muestras.sublist((desde * 44100).round(), (hasta * 44100).round()).map((m) => m.abs()).reduce(math.max);
      expect(fuerza(0.015, 0.025), greaterThan(0.6));
      expect(fuerza(0.15, 0.17), lessThan(SonidoDelTimbre.volumen / 8));
    });
  });
}
