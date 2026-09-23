import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Un error de la API, con la forma unica que devuelve el servidor:
///   { "error": { "codigo": "...", "mensaje": "..." } }
/// El mensaje esta pensado para mostrarse a la persona tal cual.
class ErrorApi implements Exception {
  const ErrorApi(this.estado, this.codigo, this.mensaje);

  /// Codigo HTTP; 0 si ni siquiera hubo respuesta.
  final int estado;
  final String codigo;
  final String mensaje;

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

  Future<Map<String, dynamic>> obtener(String ruta) async {
    var respuesta = await _get(ruta);
    if (respuesta.statusCode == 401 && await renovar()) {
      respuesta = await _get(ruta);
    }
    return _interpretar(respuesta);
  }

  Future<http.Response> _get(String ruta) async {
    final vigente = token();
    try {
      return await _cliente.get(
        base.replace(path: '${base.path}$ruta'),
        headers: {
          'Accept': 'application/json',
          if (vigente != null) 'Authorization': 'Bearer $vigente',
        },
      ).timeout(plazo);
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
      );
    }
    // Sin la forma esperada: un proxy intermedio, una pagina de error del servidor web...
    throw ErrorApi(respuesta.statusCode, 'RESPUESTA_INESPERADA',
        'El servidor respondió de forma inesperada (HTTP ${respuesta.statusCode}). Intenta de nuevo.');
  }

  void cerrar() => _cliente.close();
}
