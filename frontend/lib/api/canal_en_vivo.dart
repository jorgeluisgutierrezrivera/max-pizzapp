import 'dart:async';
import 'dart:convert';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// El canal en vivo con la API (D-04, D-21): avisa de los pedidos nuevos, de los cambios de
/// estado y de lo que se agrega a un pedido, sin recargar.
///
/// El canal AVISA; la fuente es la API. Si la conexión se corta y vuelve, la pantalla vuelve
/// a leer su lista: mientras estuvo cortada pudo perderse algún aviso.
abstract class CanalEnVivo {
  /// Cada pedido recién guardado, como lo devuelve la API.
  Stream<Map<String, dynamic>> get pedidosNuevos;

  /// Cada cambio de estado: { id, anterior, nuevo, fechaHora }.
  Stream<Map<String, dynamic>> get cambiosDeEstado;

  /// Cada pedido al que se le agregó algo (D-37), completo, como lo devuelve la API.
  Stream<Map<String, dynamic>> get pedidosActualizados;

  /// true al conectarse (también al reconectarse); false al perder la conexión.
  Stream<bool> get conexion;

  bool get conectado;

  void conectar();
  void cerrar();
}

/// Lo que el canal necesita de un socket de Socket.IO. Existe para que las pruebas puedan
/// simular cortes y rechazos sin un servidor.
abstract class SocketDelCanal {
  void on(String evento, void Function(dynamic datos) accion);
  void connect();
  void dispose();
}

/// El socket de verdad, por /socket.io/ en el mismo origen que la app.
SocketDelCanal abrirSocketIo(Uri origen, String? Function() token) => _SocketIo(io.io(
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
    ));

class _SocketIo implements SocketDelCanal {
  _SocketIo(this._socket);
  final io.Socket _socket;
  @override
  void on(String evento, void Function(dynamic datos) accion) => _socket.on(evento, accion);
  @override
  void connect() => _socket.connect();
  @override
  void dispose() => _socket.dispose();
}

/// El canal de verdad: Socket.IO sobre el mismo origen que la app, por /socket.io/, que
/// Caddy reenvía a la API.
///
/// El cliente de Socket.IO reintenta solo cuando se cae la red o el servidor, pero **no**
/// cuando el servidor corta la conexión a propósito ni cuando la rechaza: en esos dos casos
/// destruye el socket y se queda quieto. Por eso el canal decide:
/// - corte del servidor (cuando vence el token, D-47): reconecta en el acto con el vigente;
/// - rechazo por el token (D-46): lo renueva una vez y reconecta; si lo vuelven a rechazar,
///   o si la cuenta no tiene rol, la sesión termina.
class CanalSocketIo implements CanalEnVivo {
  CanalSocketIo({
    required this.origen,
    required this.token,
    required this.renovar,
    required this.alRechazarSesion,
    this.abrirSocket = abrirSocketIo,
  });

  final Uri origen;

  /// El token vigente. Se pide en cada conexión, también al reconectarse: así una
  /// reconexión no se presenta con un token vencido.
  final String? Function() token;

  /// Pide un token nuevo. Si no lo consigue, la sesión ya volvió a la pantalla de acceso.
  final Future<bool> Function() renovar;

  /// La sesión no se puede recuperar: la app vuelve a la pantalla de acceso.
  final void Function() alRechazarSesion;

  final SocketDelCanal Function(Uri origen, String? Function() token) abrirSocket;

  /// Los rechazos del servidor que se deben al token: renovarlo puede resolverlos.
  static const _rechazosDelToken = {'TOKEN_AUSENTE', 'TOKEN_EXPIRADO', 'TOKEN_INVALIDO'};

  SocketDelCanal? _socket;
  bool _conectado = false;
  bool _yaRenovo = false;
  final _nuevos = StreamController<Map<String, dynamic>>.broadcast();
  final _cambios = StreamController<Map<String, dynamic>>.broadcast();
  final _actualizados = StreamController<Map<String, dynamic>>.broadcast();
  final _conexion = StreamController<bool>.broadcast();

  @override
  Stream<Map<String, dynamic>> get pedidosNuevos => _nuevos.stream;
  @override
  Stream<Map<String, dynamic>> get cambiosDeEstado => _cambios.stream;
  @override
  Stream<Map<String, dynamic>> get pedidosActualizados => _actualizados.stream;
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
    final socket = abrirSocket(origen, token);
    _socket = socket;
    socket.on('connect', (_) {
      _yaRenovo = false;
      _cambiarConexion(true);
    });
    socket.on('disconnect', (motivo) {
      _cambiarConexion(false);
      if (motivo == 'io server disconnect') socket.connect();
    });
    socket.on('connect_error', (error) => _alSerRechazado(socket, error));
    socket.on('pedido:nuevo', (datos) => _nuevos.add(_comoJson(datos)));
    socket.on('pedido:estado', (datos) => _cambios.add(_comoJson(datos)));
    socket.on('pedido:actualizado', (datos) => _actualizados.add(_comoJson(datos)));
    socket.connect();
  }

  Future<void> _alSerRechazado(SocketDelCanal socket, dynamic error) async {
    _cambiarConexion(false);
    final codigo = _codigoDelRechazo(error);
    if (codigo == null) return; // no respondió la red o el servidor: el cliente reintenta solo
    if (!_rechazosDelToken.contains(codigo) || _yaRenovo) {
      alRechazarSesion();
      return;
    }
    _yaRenovo = true;
    // Si no se pudo renovar, la sesión ya volvió al acceso y no hay nada que reconectar.
    if (await renovar() && _socket == socket) socket.connect();
  }

  /// El código con que el servidor rechazó la conexión, o null si no la rechazó el servidor.
  static String? _codigoDelRechazo(dynamic error) {
    if (error is Map && error['data'] is Map) return (error['data'] as Map)['codigo'] as String?;
    return null;
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
  Stream<Map<String, dynamic>> get pedidosActualizados => const Stream.empty();
  @override
  Stream<bool> get conexion => const Stream.empty();
  @override
  bool get conectado => false;
  @override
  void conectar() {}
  @override
  void cerrar() {}
}
