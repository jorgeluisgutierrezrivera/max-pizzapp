/// Si el dispositivo tiene red. Cuando la pierde (Wi-Fi apagado, modo avión) el aviso de canal
/// caído aparece en el acto, sin esperar a que el latido lo note (D-44).
abstract class Red {
  bool get enLinea;

  /// Cada vez que el dispositivo gana o pierde la red.
  Stream<bool> get cambios;
}

/// Una red que nunca se cae: para las pruebas y para donde no hay navegador.
class RedSiempreEnLinea implements Red {
  const RedSiempreEnLinea();
  @override
  bool get enLinea => true;
  @override
  Stream<bool> get cambios => const Stream.empty();
}
