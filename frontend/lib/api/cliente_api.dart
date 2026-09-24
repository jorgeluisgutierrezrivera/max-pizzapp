import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Un error de la API, con la forma unica que devuelve el servidor:
///   { "error": { "codigo": "...", "mensaje": "...", ...datos } }
/// El mensaje esta pensado para mostrarse a la persona tal cual. Los datos son lo que la app
/// necesita para resolver el error por su cuenta: el total correcto, el producto agotado.
class ErrorApi implements Exception {
  const ErrorApi(this.estado, this.codigo, this.mensaje, [this.datos = const {}]);

  /// Codigo HTTP; 0 si ni siquiera hubo respuesta.
  final int estado;
  final String codigo;
  final String mensaje;
  final Map<String, dynamic> datos;

  @override
  String toString() => '$codigo ($estado): $mensaje';
}

/// Cliente de la API. Agrega el token a cada peticion y, ante un 401, renueva el token una
/// vez y reintenta: un token vencido no deberia sacar a nadie de la pantalla.
class ClienteApi {
  ClienteApi({
    required this.base,
    required this.token,
    required this.renovar,
    http.Client? cliente,
    this.plazo = const Duration(seconds: 15),
  }) : _cliente = cliente ?? http.Client();

  /// Raiz de la API, en el mismo origen que la app: .../api/v1
  final Uri base;
  final String? Function() token;
  final Future<bool> Function() renovar;
  final Duration plazo;
  final http.Client _cliente;

  static const _sinConexion = ErrorApi(
      0, 'SIN_CONEXION', 'No hay conexión con el servidor. Revisa la red e intenta de nuevo.');

  Future<Map<String, dynamic>> obtener(String ruta) => _pedir('GET', ruta);

  /// POST con un cuerpo JSON: crear un pedido, cancelarlo.
  Future<Map<String, dynamic>> enviar(String ruta, Map<String, dynamic> cuerpo) =>
      _pedir('POST', ruta, cuerpo);

  /// PATCH con un cuerpo JSON: cambiar el estado de un pedido.
  Future<Map<String, dynamic>> cambiar(String ruta, Map<String, dynamic> cuerpo) =>
      _pedir('PATCH', ruta, cuerpo);

  Future<Map<String, dynamic>> _pedir(String metodo, String ruta, [Map<String, dynamic>? cuerpo]) async {
    var respuesta = await _enviarUnaVez(metodo, ruta, cuerpo);
    // Un 401 se rechaza antes de tocar nada en el servidor: reintentar con el token nuevo no
    // repite ninguna operacion.
    if (respuesta.statusCode == 401 && await renovar()) {
      respuesta = await _enviarUnaVez(metodo, ruta, cuerpo);
    }
    return _interpretar(respuesta);
  }

  Future<http.Response> _enviarUnaVez(String metodo, String ruta, Map<String, dynamic>? cuerpo) async {
    final vigente = token();
    final peticion = http.Request(metodo, base.replace(path: '${base.path}$ruta'))
      ..headers.addAll({
        'Accept': 'application/json',
        if (cuerpo != null) 'Content-Type': 'application/json',
        if (vigente != null) 'Authorization': 'Bearer $vigente',
      });
    if (cuerpo != null) peticion.body = jsonEncode(cuerpo);
    try {
      final enviada = await _cliente.send(peticion).timeout(plazo);
      return await http.Response.fromStream(enviada).timeout(plazo);
    } on TimeoutException {
      throw _sinConexion;
    } on http.ClientException {
      throw _sinConexion;
    }
  }

  Map<String, dynamic> _interpretar(http.Response respuesta) {
    Object? cuerpo;
    try {
      cuerpo = jsonDecode(respuesta.body);
    } on FormatException {
      cuerpo = null;
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300 && cuerpo is Map<String, dynamic>) {
      return cuerpo;
    }

    final error = cuerpo is Map<String, dynamic> ? cuerpo['error'] : null;
    if (error is Map<String, dynamic>) {
      throw ErrorApi(
        respuesta.statusCode,
        error['codigo'] as String? ?? 'ERROR',
        error['mensaje'] as String? ?? 'Ocurrió un error. Intenta de nuevo.',
        {
          for (final MapEntry(:key, :value) in error.entries)
            if (key != 'codigo' && key != 'mensaje') key: value,
        },
      );
    }
    // Sin la forma esperada: un proxy intermedio, una pagina de error del servidor web...
    throw ErrorApi(respuesta.statusCode, 'RESPUESTA_INESPERADA',
        'El servidor respondió de forma inesperada (HTTP ${respuesta.statusCode}). Intenta de nuevo.');
  }

  void cerrar() => _cliente.close();
}
