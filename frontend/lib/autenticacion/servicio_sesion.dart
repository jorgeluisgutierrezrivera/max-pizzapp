import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../configuracion.dart';
import 'navegador.dart';
import 'pkce.dart';

enum EstadoSesion { iniciando, sinSesion, conSesion }

/// Inicio de sesion con Authorization Code + PKCE contra Keycloak.
///
/// Los tokens viven SOLO en memoria. Al recargar la pagina se pierden, y la app los recupera
/// preguntandole a Keycloak con prompt=none: si su sesion sigue abierta, vuelve con un codigo
/// nuevo sin pedir la contrasena. Solo el verificador y el state pasan por sessionStorage, y
/// unicamente durante la ida y vuelta a Keycloak.
class ServicioSesion extends ChangeNotifier {
  ServicioSesion({
    required this.configuracion,
    required this.navegador,
    http.Client? cliente,
    Random? azar,
  })  : _cliente = cliente ?? http.Client(),
        _clientePropio = cliente == null,
        _azar = azar ?? Random.secure();

  static const claveVerificador = 'maxpizzapp.pkce.verificador';
  static const claveEstado = 'maxpizzapp.pkce.estado';

  /// Errores de prompt=none que solo significan "no hay sesion abierta": no son fallos.
  static const _sinSesionEnKeycloak = {'login_required', 'interaction_required', 'consent_required'};

  final Configuracion configuracion;
  final Navegador navegador;
  final http.Client _cliente;
  final bool _clientePropio;
  final Random _azar;

  EstadoSesion _estado = EstadoSesion.iniciando;
  String? _mensaje;
  String? _tokenAcceso;
  String? _tokenRenovacion;
  String? _tokenIdentidad;
  Timer? _temporizadorRenovacion;

  EstadoSesion get estado => _estado;

  /// Aviso para la pantalla de acceso (sesion vencida, error de conexion...).
  String? get mensaje => _mensaje;

  /// El token para llamar a la API, o null si no hay sesion.
  String? get tokenAcceso => _estado == EstadoSesion.conSesion ? _tokenAcceso : null;

  /// Punto de entrada al cargar la pagina.
  Future<void> arrancar() async {
    final parametros = navegador.direccionActual.queryParameters;
    if (parametros.containsKey('code') || parametros.containsKey('error')) {
      await _procesarRegreso(parametros);
    } else {
      // Primera visita o recarga: si Keycloak ya tiene la sesion abierta, entra sin pedir nada.
      _irAKeycloak(silencioso: true);
    }
  }

  void iniciarSesion() => _irAKeycloak(silencioso: false);

  void _irAKeycloak({required bool silencioso}) {
    final verificador = generarVerificador(_azar);
    final estado = generarEstado(_azar);
    navegador.guardar(claveVerificador, verificador);
    navegador.guardar(claveEstado, estado);

    _cambiar(EstadoSesion.iniciando);
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
  }

  Future<void> _procesarRegreso(Map<String, String> parametros) async {
    final estadoGuardado = navegador.leer(claveEstado);
    final verificador = navegador.leer(claveVerificador);
    // Un solo uso: se borran pase lo que pase, y el codigo desaparece de la barra.
    navegador.borrar(claveEstado);
    navegador.borrar(claveVerificador);
    navegador.reemplazarDireccion(configuracion.urlRetorno);

    final error = parametros['error'];
    if (error != null) {
      _quedarSinSesion(_sinSesionEnKeycloak.contains(error)
          ? null
          : 'Keycloak no completó el inicio de sesión ($error). Intenta de nuevo.');
      return;
    }

    if (estadoGuardado == null || verificador == null || parametros['state'] != estadoGuardado) {
      _quedarSinSesion('No se pudo verificar el regreso desde Keycloak. Intenta de nuevo.');
      return;
    }

    await _pedirTokens({
      'grant_type': 'authorization_code',
      'client_id': configuracion.clienteId,
      'code': parametros['code']!,
      'redirect_uri': configuracion.urlRetorno.toString(),
      'code_verifier': verificador,
    }, siFalla: 'No se pudo completar el inicio de sesión. Intenta de nuevo.');
  }

  /// Pide un token nuevo con el de renovacion. La API tambien la usa ante un 401.
  /// Devuelve si se logro.
  Future<bool> renovar() async {
    final renovacion = _tokenRenovacion;
    if (renovacion == null) {
      _quedarSinSesion('Tu sesión expiró. Inicia sesión de nuevo.');
      return false;
    }
    return _pedirTokens({
      'grant_type': 'refresh_token',
      'client_id': configuracion.clienteId,
      'refresh_token': renovacion,
    }, siFalla: 'Tu sesión expiró. Inicia sesión de nuevo.');
  }

  Future<bool> _pedirTokens(Map<String, String> formulario, {required String siFalla}) async {
    try {
      final respuesta = await _cliente.post(configuracion.urlToken, body: formulario);
      if (respuesta.statusCode != 200) {
        _quedarSinSesion(siFalla);
        return false;
      }
      _guardarTokens(jsonDecode(respuesta.body) as Map<String, dynamic>);
      return true;
    } on Object {
      _quedarSinSesion('No hay conexión con el servidor de identidad. Revisa la red e intenta de nuevo.');
      return false;
    }
  }

  void _guardarTokens(Map<String, dynamic> datos) {
    _tokenAcceso = datos['access_token'] as String;
    _tokenRenovacion = datos['refresh_token'] as String?;
    _tokenIdentidad = (datos['id_token'] as String?) ?? _tokenIdentidad;

    // Se renueva al 80 % del plazo mas corto entre el token y la sesion de Keycloak: con 60
    // minutos de cada uno, a los 48. Asi una tableta aguanta el turno sin volver a entrar.
    final vence = datos['expires_in'] as int;
    final venceRenovacion = datos['refresh_expires_in'] as int? ?? vence;
    final plazo = min(vence, venceRenovacion > 0 ? venceRenovacion : vence);
    _temporizadorRenovacion?.cancel();
    _temporizadorRenovacion = Timer(Duration(seconds: (plazo * 0.8).floor()), renovar);

    _mensaje = null;
    _cambiar(EstadoSesion.conSesion);
  }

  /// Cierra la sesion en Keycloak, no solo en la app: si no, al volver a entrar Keycloak
  /// reconoceria su sesion y dejaria pasar con la misma cuenta sin pedir nada (RF-08).
  void cerrarSesion() {
    final identidad = _tokenIdentidad;
    _olvidarTokens();
    if (identidad == null) {
      _quedarSinSesion(null);
      return;
    }
    _cambiar(EstadoSesion.iniciando);
    navegador.irA(configuracion.urlCierre.replace(queryParameters: {
      'client_id': configuracion.clienteId,
      'id_token_hint': identidad,
      'post_logout_redirect_uri': configuracion.urlRetorno.toString(),
    }));
  }

  void _quedarSinSesion(String? mensaje) {
    _olvidarTokens();
    _mensaje = mensaje;
    _cambiar(EstadoSesion.sinSesion);
  }

  void _olvidarTokens() {
    _temporizadorRenovacion?.cancel();
    _temporizadorRenovacion = null;
    _tokenAcceso = null;
    _tokenRenovacion = null;
    _tokenIdentidad = null;
  }

  void _cambiar(EstadoSesion nuevo) {
    _estado = nuevo;
    notifyListeners();
  }

  @override
  void dispose() {
    _temporizadorRenovacion?.cancel();
    if (_clientePropio) _cliente.close();
    super.dispose();
  }
}
