import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/autenticacion/autorizador.dart';
import 'package:maxpizzapp/autenticacion/autorizador_android.dart';
import 'package:maxpizzapp/configuracion.dart';

/// AppAuth sin el navegador del sistema: anota lo que se le pidió y responde lo que se le
/// indique.
class AppAuthFalso implements FlutterAppAuth {
  AuthorizationRequest? pedido;
  EndSessionRequest? salida;
  AuthorizationResponse respuesta =
      const AuthorizationResponse(authorizationCode: 'codigo-1', codeVerifier: 'verificador-1');
  Object? falla;

  @override
  Future<AuthorizationResponse> authorize(AuthorizationRequest request) async {
    pedido = request;
    if (falla != null) throw falla!;
    return respuesta;
  }

  @override
  Future<EndSessionResponse> endSession(EndSessionRequest request) async {
    salida = request;
    if (falla != null) throw falla!;
    return EndSessionResponse(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final produccion = Configuracion.paraApp(origenDefinido: 'https://maxpizzapp.tech');

FlutterAppAuthPlatformErrorDetails get _detalles => FlutterAppAuthPlatformErrorDetails();

void main() {
  late AppAuthFalso appAuth;
  late AutorizadorAndroid autorizador;

  setUp(() {
    appAuth = AppAuthFalso();
    autorizador = AutorizadorAndroid(configuracion: produccion, appAuth: appAuth);
  });

  test('al abrir no abre nada: espera a que la persona toque "Iniciar sesión"', () async {
    final paso = await autorizador.alArrancar();
    expect(paso, isA<SinCodigo>().having((p) => p.mensaje, 'mensaje', isNull));
    expect(appAuth.pedido, isNull);
  });

  test('pide el código al cliente público, con la dirección propia de la app y por https', () async {
    await autorizador.pedirCodigo();
    final pedido = appAuth.pedido!;
    expect(pedido.clientId, 'frontend-web');
    expect(pedido.redirectUrl, 'tech.maxpizzapp.cocina:/callback');
    expect(pedido.scopes, ['openid']);
    expect(pedido.serviceConfiguration!.authorizationEndpoint,
        'https://auth.maxpizzapp.tech/realms/maxpizzapp/protocol/openid-connect/auth');
    expect(pedido.serviceConfiguration!.tokenEndpoint,
        'https://auth.maxpizzapp.tech/realms/maxpizzapp/protocol/openid-connect/token');
    expect(pedido.allowInsecureConnections, isFalse);
  });

  test('devuelve el código y el verificador de PKCE para que ServicioSesion los canjee', () async {
    final paso = await autorizador.pedirCodigo();
    expect(paso, isA<CodigoRecibido>());
    final codigo = paso as CodigoRecibido;
    expect(codigo.codigo, 'codigo-1');
    expect(codigo.verificador, 'verificador-1');
    expect(codigo.retorno, 'tech.maxpizzapp.cocina:/callback');
  });

  test('si la persona se vuelve atrás, no es un error: sin mensaje', () async {
    appAuth.falla = FlutterAppAuthUserCancelledException(code: 'cancelado', platformErrorDetails: _detalles);
    final paso = await autorizador.pedirCodigo();
    expect(paso, isA<SinCodigo>().having((p) => p.mensaje, 'mensaje', isNull));
  });

  test('si AppAuth falla (sin red, por ejemplo), lo dice', () async {
    appAuth.falla = FlutterAppAuthPlatformException(code: 'error', platformErrorDetails: _detalles);
    final paso = await autorizador.pedirCodigo();
    expect(paso, isA<SinCodigo>().having((p) => p.mensaje, 'mensaje', contains('Revisa la red')));
  });

  test('una respuesta sin código no se canjea', () async {
    appAuth.respuesta = const AuthorizationResponse(codeVerifier: 'verificador-1');
    final paso = await autorizador.pedirCodigo();
    expect(paso, isA<SinCodigo>().having((p) => p.mensaje, 'mensaje', isNotNull));
  });

  test('cerrar sesión cierra la de Keycloak y vuelve a la app', () async {
    final paso = await autorizador.cerrarSesion('identidad-1');
    final salida = appAuth.salida!;
    expect(salida.idTokenHint, 'identidad-1');
    expect(salida.postLogoutRedirectUrl, 'tech.maxpizzapp.cocina:/callback');
    expect(salida.serviceConfiguration!.endSessionEndpoint,
        'https://auth.maxpizzapp.tech/realms/maxpizzapp/protocol/openid-connect/logout');
    expect(paso, isA<SinCodigo>().having((p) => p.mensaje, 'mensaje', isNull));
  });

  test('si Keycloak no llega a cerrar, avisa que puede no pedir la contraseña', () async {
    appAuth.falla = FlutterAppAuthPlatformException(code: 'error', platformErrorDetails: _detalles);
    final paso = await autorizador.cerrarSesion('identidad-1');
    expect(paso, isA<SinCodigo>().having((p) => p.mensaje, 'mensaje', contains('contraseña')));
  });

  test('http solo se permite en desarrollo, contra el Keycloak local', () async {
    final local = Configuracion.paraApp(
      origenDefinido: 'http://localhost:3001',
      keycloakDefinido: 'http://localhost:8082',
    );
    await AutorizadorAndroid(configuracion: local, appAuth: appAuth).pedirCodigo();
    // Las pruebas corren en modo de desarrollo (kDebugMode).
    expect(appAuth.pedido!.allowInsecureConnections, isTrue);
  });

  test('los errores de la plataforma se capturan como PlatformException', () {
    // La cancelación también es una PlatformException: por eso se captura primero.
    expect(
      FlutterAppAuthUserCancelledException(code: 'c', platformErrorDetails: _detalles),
      isA<PlatformException>(),
    );
  });
}
