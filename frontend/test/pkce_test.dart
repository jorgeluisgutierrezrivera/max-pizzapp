import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/autenticacion/pkce.dart';

void main() {
  // Vector de prueba oficial: RFC 7636, apendice B.
  const bytesDelRfc = [
    116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173, 187, 186, //
    22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83, 132, 141, 121,
  ];
  const verificadorDelRfc = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  const desafioDelRfc = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

  test('RFC 7636: los 32 bytes del apendice B dan su verificador', () {
    expect(base64UrlSinRelleno(bytesDelRfc), verificadorDelRfc);
  });

  test('RFC 7636: el verificador del apendice B da su desafio S256', () {
    expect(desafioS256(verificadorDelRfc), desafioDelRfc);
  });

  test('el verificador mide 43 caracteres y solo usa el alfabeto base64url', () {
    final v = generarVerificador();
    expect(v.length, 43);
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v), isTrue);
  });

  test('dos verificadores seguidos nunca son iguales', () {
    expect(generarVerificador(), isNot(generarVerificador()));
    expect(generarEstado(), isNot(generarEstado()));
  });

  test('con el mismo generador se obtiene lo mismo: las pruebas son reproducibles', () {
    expect(generarVerificador(Random(7)), generarVerificador(Random(7)));
  });
}
