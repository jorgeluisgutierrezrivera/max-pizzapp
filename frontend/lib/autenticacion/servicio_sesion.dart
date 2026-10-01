import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../configuracion.dart';
import 'autorizador.dart';
import 'autorizador_web.dart';
import 'navegador.dart';

enum EstadoSesion { iniciando, sinSesion, conSesion }

/// Inicio de sesion con Authorization Code + PKCE contra Keycloak.
///
/// Como se obtiene el codigo depende de la plataforma y lo resuelve el [Autorizador] (D-49):
/// en la web, la redireccion de la pagina ([AutorizadorWeb], el que se usa si se pasa un
/// [Navegador]); en el APK de cocina, AppAuth. Lo que sigue es comun: el canje del codigo, la
/// renovacion y el cierre de la sesion que el servidor rechaza.
///
/// Los tokens viven SOLO en memoria. En la web, al recargar la pagina se pierden y la app los
/// recupera preguntandole a Keycloak con prompt=none; en el APK, al cerrar la app se vuelve a
/// entrar.
class ServicioSesion extends ChangeNotifier {
  ServicioSesion({
    required this.configuracion,
    Navegador? navegador,
    Autorizador? autorizador,
    http.Client? cliente,
    Random? azar,
  })  : assert((navegador == null) != (autorizador == null), 'Un navegador (web) o un autorizador'),
        autorizador =
            autorizador ?? AutorizadorWeb(configuracion: configuracion, navegador: navegador!, azar: azar),
        _cliente = cliente ?? http.Client(),
        _clientePropio = cliente == null;

  static const claveVerificador = AutorizadorWeb.claveVerificador;
  static const claveEstado = AutorizadorWeb.claveEstado;

  final Configuracion configuracion;
  final Autorizador autorizador;
  final http.Client _cliente;
  final bool _clientePropio;

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

  /// Punto de entrada al abrir la app.
  Future<void> arrancar() async => _seguir(await autorizador.alArrancar());

  Future<void> iniciarSesion() async {
    _cambiar(EstadoSesion.iniciando);
    await _seguir(await autorizador.pedirCodigo());
  }

  Future<void> _seguir(Paso paso) async {
    switch (paso) {
      case Saliendo():
        return; // la pagina se va a Keycloak: el resto pasa cuando vuelva
      case SinCodigo(:final mensaje):
        _quedarSinSesion(mensaje);
      case CodigoRecibido():
        await _pedirTokens({
          'grant_type': 'authorization_code',
          'client_id': configuracion.clienteId,
          'code': paso.codigo,
          'redirect_uri': paso.retorno,
          'code_verifier': paso.verificador,
        }, siFalla: 'No se pudo completar el inicio de sesión. Intenta de nuevo.');
    }
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

  /// El servidor rechazo la sesion aunque el token se acababa de renovar, en la API o en el
  /// canal en vivo (D-46). No se puede recuperar: vuelve al acceso.
  void terminarSesionRechazada() => _quedarSinSesion('Tu sesión expiró. Inicia sesión de nuevo.');

  /// Cierra la sesion en Keycloak, no solo en la app: si no, al volver a entrar Keycloak
  /// reconoceria su sesion y dejaria pasar con la misma cuenta sin pedir nada (RF-08).
  Future<void> cerrarSesion() async {
    final identidad = _tokenIdentidad;
    _olvidarTokens();
    if (identidad == null) {
      _quedarSinSesion(null);
      return;
    }
    _cambiar(EstadoSesion.iniciando);
    final paso = await autorizador.cerrarSesion(identidad);
    // En la web la pagina ya se fue; en el APK, la app vuelve al acceso, con el aviso si
    // Keycloak no llego a cerrar.
    if (paso is! Saliendo) _quedarSinSesion(paso is SinCodigo ? paso.mensaje : null);
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
