import 'package:flutter/foundation.dart';

/// El aviso que suena: en cocina cuando llega un pedido nuevo o se le agrega algo a uno, y en
/// recepción cuando uno queda listo (pedido del autor, 24-sep).
///
/// Viene activado (pedido del autor, 25-sep): intenta sonar desde que se abre la página y,
/// si el navegador no lo deja todavía, se activa solo con el primer toque o tecla en
/// cualquier parte de la pantalla. El navegador no deja que una página suene hasta que la
/// persona la usa al menos una vez; eso no lo puede saltar ninguna página.
abstract class Timbre {
  bool get habilitado;

  /// Avisa cuando el sonido se activa solo, para que la barra lo muestre.
  Listenable get cambios;

  /// Llamarlo desde un toque de la persona; si no, el navegador lo ignora. Suena una vez,
  /// para que se sepa cómo suena.
  Future<void> habilitar();

  void sonar();
}

/// Un timbre mudo: para las pruebas y para donde no hay navegador.
class TimbreMudo implements Timbre {
  @override
  bool get habilitado => false;
  @override
  Listenable get cambios => const _SinCambios();
  @override
  Future<void> habilitar() async {}
  @override
  void sonar() {}
}

class _SinCambios implements Listenable {
  const _SinCambios();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
