import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

// PKCE (RFC 7636): la app inventa un secreto de un solo uso, el verificador, y a Keycloak
// solo le manda su huella SHA-256, el desafio. Al canjear el codigo entrega el verificador:
// si alguien intercepto el codigo en la redireccion, no le sirve sin el verificador, que
// nunca viajo por la barra de direcciones.

/// Base64url sin el relleno "=", como exige el RFC 7636.
String base64UrlSinRelleno(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// [bytes] aleatorios de un generador criptograficamente seguro, en base64url.
String generarAleatorio(int bytes, [Random? azar]) {
  final generador = azar ?? Random.secure();
  return base64UrlSinRelleno(List<int>.generate(bytes, (_) => generador.nextInt(256)));
}

/// 32 bytes dan un verificador de 43 caracteres, el minimo que admite el RFC.
String generarVerificador([Random? azar]) => generarAleatorio(32, azar);

/// Valor que sale con la redireccion y tiene que volver identico: protege contra el
/// inicio de sesion forzado (CSRF).
String generarEstado([Random? azar]) => generarAleatorio(16, azar);

/// El desafio S256: base64url(SHA-256(verificador)).
String desafioS256(String verificador) =>
    base64UrlSinRelleno(sha256.convert(ascii.encode(verificador)).bytes);
