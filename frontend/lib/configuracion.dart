/// Configuracion de la app. Ninguna direccion esta escrita a mano en el codigo: todas se
/// deducen de la pagina en la que corre la app o llegan al compilar con --dart-define.
class Configuracion {
  const Configuracion({
    required this.origen,
    required this.keycloak,
    this.realm = 'maxpizzapp',
    this.clienteId = 'frontend-web',
  });

  /// Donde corre la app, por ejemplo https://maxpizzapp.tech.
  final Uri origen;

  /// Raiz de Keycloak, por ejemplo https://auth.maxpizzapp.tech.
  final Uri keycloak;

  final String realm;
  final String clienteId;

  /// La API vive en el mismo origen que la app: no hace falta CORS ni una direccion aparte.
  static const rutaApi = '/api/v1';

  Uri get emisor => keycloak.replace(path: '/realms/$realm');
  Uri get urlAutorizacion => _oidc('auth');
  Uri get urlToken => _oidc('token');
  Uri get urlCierre => _oidc('logout');

  /// A donde vuelve Keycloak despues de iniciar o cerrar sesion.
  Uri get urlRetorno => origen.replace(path: '/');

  Uri _oidc(String accion) =>
      keycloak.replace(path: '/realms/$realm/protocol/openid-connect/$accion');

  /// Deduce la configuracion a partir de la pagina actual.
  ///
  /// En produccion Keycloak esta en el subdominio "auth." del mismo dominio. En desarrollo la
  /// app corre en localhost, donde no hay nada que deducir: la direccion llega por
  /// --dart-define=KEYCLOAK_URL=http://localhost:8082.
  factory Configuracion.deducir({
    required Uri paginaActual,
    String keycloakDefinido = '',
  }) {
    final origen = Uri(
      scheme: paginaActual.scheme,
      host: paginaActual.host,
      port: paginaActual.hasPort ? paginaActual.port : null,
    );

    final definido = keycloakDefinido.trim();
    if (definido.isNotEmpty) {
      final uri = Uri.tryParse(definido.replaceAll(RegExp(r'/+$'), ''));
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
        throw ErrorDeConfiguracion('KEYCLOAK_URL no es una direccion valida: "$definido".');
      }
      return Configuracion(origen: origen, keycloak: uri.replace(path: ''));
    }

    if (_esLocal(origen.host)) {
      throw const ErrorDeConfiguracion(
        'En desarrollo hay que indicar la direccion de Keycloak al ejecutar la app: '
        '--dart-define=KEYCLOAK_URL=http://localhost:8082',
      );
    }

    return Configuracion(
      origen: origen,
      keycloak: Uri(scheme: 'https', host: 'auth.${origen.host}'),
    );
  }

  static bool _esLocal(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '[::1]';
}

class ErrorDeConfiguracion implements Exception {
  const ErrorDeConfiguracion(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}
