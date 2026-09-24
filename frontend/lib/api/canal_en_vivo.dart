import 'dart:async';
import 'dart:convert';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// El canal en vivo con la API (D-04, D-21): avisa de los pedidos nuevos y de los cambios de
/// estado, sin recargar.
///
/// El canal AVISA; la fuente es la API. Si la conexión se corta y vuelve, la pantalla vuelve
/// a leer su lista: mientras estuvo cortada pudo perderse algún aviso.
abstract class CanalEnVivo {
  /// Cada pedido recién guardado, como lo devuelve la API.
  Stream<Map<String, dynamic>> get pedidosNuevos;

  /// Cada cambio de estado: { id, anterior, nuevo, fechaHora }.
  Stream<Map<String, dynamic>> get cambiosDeEstado;

  /// true al conectarse (también al reconectarse); false al perder la conexión.
  Stream<bool> get conexion;

  bool get conectado;

  void conectar();
  void cerrar();
}

/// El canal de verdad: Socket.IO sobre el mismo origen que la app, por /socket.io/, que
/// Caddy reenvía a la API.
class CanalSocketIo implements CanalEnVivo {
  CanalSocketIo({required this.origen, required this.token});

  final Uri origen;

  /// El token vigente. Se pide en cada conexión, también al reconectarse: así una
  /// reconexión no se presenta con un token vencido.
  final String? Function() token;

  io.Socket? _socket;
  bool _conectado = false;
  final _nuevos = StreamController<Map<String, dynamic>>.broadcast();
  final _cambios = StreamController<Map<String, dynamic>>.broadcast();
  final _conexion = StreamController<bool>.broadcast();

  @override
  Stream<Map<String, dynamic>> get pedidosNuevos => _nuevos.stream;
  @override
  Stream<Map<String, dynamic>> get cambiosDeEstado => _cambios.stream;
  @override
  Stream<bool> get conexion => _conexion.stream;
  @override
  bool get conectado => _conectado;

  /// Lo que llega por el canal, como mapa de JSON corriente.
  static Map<String, dynamic> _comoJson(dynamic datos) =>
      jsonDecode(jsonEncode(datos)) as Map<String, dynamic>;

  void _cambiarConexion(bool conectado) {
    if (_conectado == conectado) return;
    _conectado = conectado;
    _conexion.add(conectado);
  }

  @override
  void conectar() {
    if (_socket != null) return;
    final socket = io.io(
      origen.toString(),
      io.OptionBuilder()
          // Directo por WebSocket: Caddy lo reenvía sin configuración, y no hace falta el
          // sondeo por HTTP que Socket.IO usa de respaldo.
          .setTransports(['websocket'])
          .setAuthFn((entregar) => entregar({'token': token()}))
          .enableReconnection()
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );
    socket.onConnect((_) => _cambiarConexion(true));
    socket.onDisconnect((_) => _cambiarConexion(false));
    socket.onConnectError((_) => _cambiarConexion(false));
    socket.on('pedido:nuevo', (datos) => _nuevos.add(_comoJson(datos)));
    socket.on('pedido:estado', (datos) => _cambios.add(_comoJson(datos)));
    socket.connect();
    _socket = socket;
  }

  @override
  void cerrar() {
    _socket?.dispose();
    _socket = null;
    _conectado = false;
  }
}

/// Un canal que nunca se conecta: para pantallas sin canal (las pruebas que no lo usan).
class CanalApagado implements CanalEnVivo {
  const CanalApagado();
  @override
  Stream<Map<String, dynamic>> get pedidosNuevos => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get cambiosDeEstado => const Stream.empty();
  @override
  Stream<bool> get conexion => const Stream.empty();
  @override
  bool get conectado => false;
  @override
  void conectar() {}
  @override
  void cerrar() {}
}
