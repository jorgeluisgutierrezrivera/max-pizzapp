import 'dart:math';

import '../configuracion.dart';
import 'autorizador.dart';
import 'navegador.dart';
import 'pkce.dart';

/// El acceso en la web: Authorization Code + PKCE llevando la página entera a Keycloak.
///
/// Solo el verificador y el state pasan por sessionStorage, y unicamente durante la ida y
/// vuelta a Keycloak. Al abrir la app sin codigo en la direccion, pregunta en silencio
/// (prompt=none): si Keycloak ya tiene la sesion abierta, vuelve con un codigo sin pedir la
/// contrasena.
class AutorizadorWeb implements Autorizador {
  AutorizadorWeb({required this.configuracion, required this.navegador, Random? azar})
      : _azar = azar ?? Random.secure();

  static const claveVerificador = 'maxpizzapp.pkce.verificador';
  static const claveEstado = 'maxpizzapp.pkce.estado';

  /// Errores de prompt=none que solo significan "no hay sesion abierta": no son fallos.
  static const _sinSesionEnKeycloak = {'login_required', 'interaction_required', 'consent_required'};

  final Configuracion configuracion;
  final Navegador navegador;
  final Random _azar;

  @override
  Future<Paso> alArrancar() async {
    final parametros = navegador.direccionActual.queryParameters;
    if (parametros.containsKey('code') || parametros.containsKey('error')) {
      return _procesarRegreso(parametros);
    }
    // Primera visita o recarga: si Keycloak ya tiene la sesion abierta, entra sin pedir nada.
    return _irAKeycloak(silencioso: true);
  }

  @override
  Future<Paso> pedirCodigo() async => _irAKeycloak(silencioso: false);

  @override
  Future<Paso> cerrarSesion(String tokenIdentidad) async {
    navegador.irA(configuracion.urlCierre.replace(queryParameters: {
      'client_id': configuracion.clienteId,
      'id_token_hint': tokenIdentidad,
      'post_logout_redirect_uri': configuracion.urlRetorno.toString(),
    }));
    return const Saliendo();
  }

  Paso _irAKeycloak({required bool silencioso}) {
    final verificador = generarVerificador(_azar);
    final estado = generarEstado(_azar);
    navegador.guardar(claveVerificador, verificador);
    navegador.guardar(claveEstado, estado);

    navegador.irA(configuracion.urlAutorizacion.replace(queryParameters: {
      'client_id': configuracion.clienteId,
      'response_type': 'code',
      'scope': 'openid',
      'redirect_uri': configuracion.urlRetorno.toString(),
      'code_challenge': desafioS256(verificador),
      'code_challenge_method': 'S256',
      'state': estado,
      if (silencioso) 'prompt': 'none',
    }));
    return const Saliendo();
  }

  Paso _procesarRegreso(Map<String, String> parametros) {
    final estadoGuardado = navegador.leer(claveEstado);
    final verificador = navegador.leer(claveVerificador);
    // Un solo uso: se borran pase lo que pase, y el codigo desaparece de la barra.
    navegador.borrar(claveEstado);
    navegador.borrar(claveVerificador);
    navegador.reemplazarDireccion(configuracion.urlRetorno);

    final error = parametros['error'];
    if (error != null) {
      return SinCodigo(_sinSesionEnKeycloak.contains(error)
          ? null
          : 'Keycloak no completó el inicio de sesión ($error). Intenta de nuevo.');
    }

    if (estadoGuardado == null || verificador == null || parametros['state'] != estadoGuardado) {
      return const SinCodigo('No se pudo verificar el regreso desde Keycloak. Intenta de nuevo.');
    }

    return CodigoRecibido(
      codigo: parametros['code']!,
      verificador: verificador,
      retorno: configuracion.urlRetorno.toString(),
    );
  }
}
