/// Que la pantalla no se apague mientras la cola de cocina está abierta (D-50): en el APK, el
/// teléfono de la cocina queda a la vista toda la noche, cargando.
///
/// La cola la pide al abrirse y la suelta al cerrarse, que es también lo que pasa al cerrar
/// sesión. En la web no hace nada: la computadora o la tableta tienen su propia
/// configuración, y la web no cambia con el APK.
abstract class PantallaEncendida {
  void mantener();
  void soltar();
}

/// La de la web y las pruebas: la pantalla se apaga cuando el sistema lo decida.
class PantallaSegunElSistema implements PantallaEncendida {
  const PantallaSegunElSistema();
  @override
  void mantener() {}
  @override
  void soltar() {}
}
