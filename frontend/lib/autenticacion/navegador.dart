/// Lo unico que el acceso necesita del navegador. Existe como interfaz para que el servicio
/// de sesion se pueda probar sin un navegador de verdad.
abstract interface class Navegador {
  /// La direccion completa de la pagina, con sus parametros.
  Uri get direccionActual;

  /// Sale de la app hacia otra pagina (Keycloak).
  void irA(Uri destino);

  /// Cambia la direccion visible sin recargar: sirve para borrar el codigo de la barra.
  void reemplazarDireccion(Uri destino);

  // sessionStorage: sobrevive a la ida y vuelta a Keycloak y muere al cerrar la pestana.
  String? leer(String clave);
  void guardar(String clave, String valor);
  void borrar(String clave);
}
