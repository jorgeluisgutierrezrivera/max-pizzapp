/// Cómo obtiene la app el código de autorización de Keycloak. Es lo único del acceso que
/// depende de la plataforma (D-49): la web lleva la página entera a Keycloak y vuelve con el
/// código en la dirección; el APK abre Keycloak en el navegador del sistema con AppAuth.
///
/// Lo que se hace con el código (canjearlo, renovar el token, cerrar la sesión rechazada) es
/// común y vive en ServicioSesion.
abstract interface class Autorizador {
  /// Al abrir la app.
  Future<Paso> alArrancar();

  /// La persona tocó "Iniciar sesión".
  Future<Paso> pedirCodigo();

  /// Cierra también la sesión de Keycloak, no solo la de la app (RF-08).
  Future<Paso> cerrarSesion(String tokenIdentidad);
}

/// Lo que devuelve cada paso del acceso.
sealed class Paso {
  const Paso();
}

/// La página se fue a Keycloak: el resultado llega cuando vuelva, en otra carga (solo web).
class Saliendo extends Paso {
  const Saliendo();
}

/// Keycloak devolvió un código para canjear por los tokens.
class CodigoRecibido extends Paso {
  const CodigoRecibido({required this.codigo, required this.verificador, required this.retorno});

  final String codigo;

  /// El verificador de PKCE: solo quien lo tiene puede canjear el código.
  final String verificador;

  /// La dirección de retorno usada al pedirlo: el canje tiene que repetirla.
  final String retorno;
}

/// No hay sesión. Con un mensaje si algo falló; sin mensaje si solo no había sesión abierta
/// o la persona se volvió atrás.
class SinCodigo extends Paso {
  const SinCodigo([this.mensaje]);

  final String? mensaje;
}
