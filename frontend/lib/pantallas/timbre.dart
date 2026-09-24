/// El aviso que suena: en cocina cuando llega un pedido nuevo, y en recepción cuando uno
/// queda listo (pedido del autor, 24-sep).
///
/// El navegador no deja que una página suene hasta que la persona la toca al menos una vez.
/// Por eso el sonido se "habilita" con un botón, una vez por jornada: después suena solo.
abstract class Timbre {
  bool get habilitado;

  /// Llamarlo desde un toque de la persona; si no, el navegador lo ignora.
  Future<void> habilitar();

  void sonar();
}

/// Un timbre mudo: para las pruebas y para donde no hay navegador.
class TimbreMudo implements Timbre {
  @override
  bool get habilitado => false;
  @override
  Future<void> habilitar() async {}
  @override
  void sonar() {}
}
