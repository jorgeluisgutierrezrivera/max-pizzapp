import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/configuracion.dart';

void main() {
  group('en produccion la direccion de Keycloak se deduce del dominio', () {
    final c = Configuracion.deducir(
      paginaActual: Uri.parse('https://maxpizzapp.tech/cualquier/ruta?code=x&state=y'),
    );

    test('origen sin ruta ni parametros', () {
      expect(c.origen.toString(), 'https://maxpizzapp.tech');
    });

    test('Keycloak en el subdominio auth.', () {
      expect(c.keycloak.toString(), 'https://auth.maxpizzapp.tech');
      expect(c.emisor.toString(), 'https://auth.maxpizzapp.tech/realms/maxpizzapp');
    });

    test('los tres endpoints de OpenID Connect', () {
      const base = 'https://auth.maxpizzapp.tech/realms/maxpizzapp/protocol/openid-connect';
      expect(c.urlAutorizacion.toString(), '$base/auth');
      expect(c.urlToken.toString(), '$base/token');
      expect(c.urlCierre.toString(), '$base/logout');
    });

    test('Keycloak devuelve a la raiz de la app', () {
      expect(c.urlRetorno.toString(), 'https://maxpizzapp.tech/');
    });
  });

  test('otro dominio da otro Keycloak: nada esta escrito a mano', () {
    final c = Configuracion.deducir(paginaActual: Uri.parse('https://otro-dominio.org/'));
    expect(c.keycloak.toString(), 'https://auth.otro-dominio.org');
  });

  test('en desarrollo se usa la direccion definida al compilar, conservando el puerto', () {
    final c = Configuracion.deducir(
      paginaActual: Uri.parse('http://localhost:8090/'),
      keycloakDefinido: 'http://localhost:8082/',
    );
    expect(c.origen.toString(), 'http://localhost:8090');
    expect(c.keycloak.toString(), 'http://localhost:8082');
    expect(c.urlRetorno.toString(), 'http://localhost:8090/');
    expect(c.emisor.toString(), 'http://localhost:8082/realms/maxpizzapp');
  });

  test('en localhost sin direccion definida, error claro en vez de adivinar', () {
    expect(
      () => Configuracion.deducir(paginaActual: Uri.parse('http://localhost:8090/')),
      throwsA(isA<ErrorDeConfiguracion>()),
    );
  });

  test('una direccion definida que no es http ni https se rechaza', () {
    expect(
      () => Configuracion.deducir(
        paginaActual: Uri.parse('http://localhost:8090/'),
        keycloakDefinido: 'javascript:alert(1)',
      ),
      throwsA(isA<ErrorDeConfiguracion>()),
    );
  });

  test('la API se llama por ruta relativa, en el mismo origen', () {
    expect(Configuracion.rutaApi, '/api/v1');
  });
}
