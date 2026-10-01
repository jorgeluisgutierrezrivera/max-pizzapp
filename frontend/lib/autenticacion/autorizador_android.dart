import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

import '../configuracion.dart';
import 'autorizador.dart';

/// El acceso en el APK de cocina (D-49). AppAuth abre la página de Keycloak en el navegador
/// del sistema, que la app no controla: la app nunca ve la contraseña (RFC 8252). Vuelve por
/// la dirección propia de la app con el código y el verificador de PKCE, y el canje lo hace
/// ServicioSesion, igual que en la web.
class AutorizadorAndroid implements Autorizador {
  AutorizadorAndroid({required this.configuracion, this.appAuth = const FlutterAppAuth()});

  /// La dirección de retorno de la app. Tiene que estar, exacta, en el cliente de Keycloak, y
  /// su esquema en android/app/build.gradle.kts (appAuthRedirectScheme).
  static const retorno = 'tech.maxpizzapp.cocina:/callback';

  final Configuracion configuracion;
  final FlutterAppAuth appAuth;

  AuthorizationServiceConfiguration get _servicio => AuthorizationServiceConfiguration(
        authorizationEndpoint: configuracion.urlAutorizacion.toString(),
        tokenEndpoint: configuracion.urlToken.toString(),
        endSessionEndpoint: configuracion.urlCierre.toString(),
      );

  /// AppAuth rechaza direcciones http. Se permiten solo en desarrollo, contra el Keycloak
  /// local; en producción Keycloak es https.
  bool get _httpPermitido => kDebugMode && configuracion.keycloak.isScheme('http');

  /// Al abrir no se pregunta nada: la persona toca "Iniciar sesión". Si su sesión de Keycloak
  /// sigue abierta en el navegador, entra sin volver a escribir la contraseña.
  @override
  Future<Paso> alArrancar() async => const SinCodigo();

  @override
  Future<Paso> pedirCodigo() async {
    try {
      final respuesta = await appAuth.authorize(AuthorizationRequest(
        configuracion.clienteId,
        retorno,
        serviceConfiguration: _servicio,
        scopes: const ['openid'],
        allowInsecureConnections: _httpPermitido,
      ));
      final codigo = respuesta.authorizationCode;
      final verificador = respuesta.codeVerifier;
      if (codigo == null || verificador == null) {
        return const SinCodigo('Keycloak no completó el inicio de sesión. Intenta de nuevo.');
      }
      return CodigoRecibido(codigo: codigo, verificador: verificador, retorno: retorno);
    } on FlutterAppAuthUserCancelledException {
      return const SinCodigo(); // se volvió atrás: no es un error
    } on PlatformException {
      return const SinCodigo('No se pudo completar el inicio de sesión. Revisa la red e intenta de nuevo.');
    }
  }

  @override
  Future<Paso> cerrarSesion(String tokenIdentidad) async {
    try {
      await appAuth.endSession(EndSessionRequest(
        idTokenHint: tokenIdentidad,
        postLogoutRedirectUrl: retorno,
        serviceConfiguration: _servicio,
        allowInsecureConnections: _httpPermitido,
      ));
      return const SinCodigo();
    } on PlatformException {
      // La app ya olvidó los tokens, pero Keycloak puede seguir con la sesión abierta.
      return const SinCodigo(
        'Saliste de la app, pero no se pudo cerrar la sesión en el servidor de identidad: '
        'al volver a entrar, puede que no te pida la contraseña.',
      );
    }
  }
}
