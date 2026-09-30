import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/canal_en_vivo.dart';

/// Un socket que no habla con nadie: la prueba dispara los eventos que dispararía el de
/// Socket.IO y cuenta cuántas veces el canal le pide conectarse.
class SocketFalso implements SocketDelCanal {
  final _acciones = <String, void Function(dynamic)>{};
  int conexiones = 0;
  bool cerrado = false;

  @override
  void on(String evento, void Function(dynamic datos) accion) => _acciones[evento] = accion;
  @override
  void connect() => conexiones++;
  @override
  void dispose() => cerrado = true;

  void emitir(String evento, [dynamic datos]) => _acciones[evento]?.call(datos);

  /// El rechazo del servidor tal como llega: { message, data: { codigo } }.
  void rechazar(String codigo) => emitir('connect_error', {'message': 'rechazado', 'data': {'codigo': codigo}});
}

void main() {
  late SocketFalso socket;
  late List<Uri> origenes;
  late int renovaciones;
  late bool renovacionFunciona;
  late Completer<void>? renovacionPendiente;
  late int rechazosDeSesion;
  late CanalSocketIo canal;
  late String token;

  setUp(() {
    socket = SocketFalso();
    origenes = [];
    renovaciones = 0;
    renovacionFunciona = true;
    renovacionPendiente = null;
    rechazosDeSesion = 0;
    token = 'token-1';
    canal = CanalSocketIo(
      origen: Uri.parse('https://maxpizzapp.tech'),
      token: () => token,
      renovar: () async {
        renovaciones++;
        await renovacionPendiente?.future;
        if (renovacionFunciona) token = 'token-${renovaciones + 1}';
        return renovacionFunciona;
      },
      alRechazarSesion: () => rechazosDeSesion++,
      abrirSocket: (origen, leerToken) {
        origenes.add(origen);
        return socket;
      },
    );
  });

  /// Deja que terminen las renovaciones que el canal esperaba.
  Future<void> esperarRenovacion() => Future<void>.delayed(Duration.zero);

  test('conecta una sola vez, al origen de la app, y avisa cuando entra', () async {
    final estados = <bool>[];
    canal.conexion.listen(estados.add);
    canal.conectar();
    canal.conectar();
    expect(origenes, [Uri.parse('https://maxpizzapp.tech')]);
    expect(socket.conexiones, 1);

    socket.emitir('connect');
    await esperarRenovacion();
    expect(canal.conectado, isTrue);
    expect(estados, [true]);
  });

  group('cuando se corta (D-47)', () {
    test('si lo corta el servidor, al vencer el token, se reconecta en el acto y sin renovar', () async {
      canal.conectar();
      socket.emitir('connect');
      socket.emitir('disconnect', 'io server disconnect');
      expect(canal.conectado, isFalse);
      expect(socket.conexiones, 2, reason: 'el cliente de Socket.IO no reconecta solo tras un corte del servidor');
      expect(renovaciones, 0);
      expect(rechazosDeSesion, 0);
    });

    for (final motivo in ['transport close', 'ping timeout', 'transport error']) {
      test('si se cae la red o el servidor ("$motivo"), deja que el cliente reintente solo', () async {
        canal.conectar();
        socket.emitir('connect');
        socket.emitir('disconnect', motivo);
        expect(canal.conectado, isFalse);
        expect(socket.conexiones, 1);
        expect(renovaciones, 0);
      });
    }
  });

  group('cuando el servidor lo rechaza (D-46)', () {
    for (final codigo in ['TOKEN_EXPIRADO', 'TOKEN_INVALIDO', 'TOKEN_AUSENTE']) {
      test('por el token ($codigo): lo renueva una vez y reconecta', () async {
        canal.conectar();
        socket.rechazar(codigo);
        await esperarRenovacion();
        expect(renovaciones, 1);
        expect(socket.conexiones, 2);
        expect(token, 'token-2', reason: 'la reconexión se presenta con el token nuevo');
        expect(rechazosDeSesion, 0);
      });
    }

    test('si lo rechaza otra vez con el token renovado, la sesión termina', () async {
      canal.conectar();
      socket.rechazar('TOKEN_EXPIRADO');
      await esperarRenovacion();
      socket.rechazar('TOKEN_INVALIDO');
      await esperarRenovacion();
      expect(renovaciones, 1, reason: 'se renueva una sola vez');
      expect(socket.conexiones, 2);
      expect(rechazosDeSesion, 1);
    });

    test('después de reconectar, un rechazo futuro vuelve a tener su renovación', () async {
      canal.conectar();
      socket.rechazar('TOKEN_EXPIRADO');
      await esperarRenovacion();
      socket.emitir('connect');
      socket.emitir('disconnect', 'transport close');
      socket.rechazar('TOKEN_EXPIRADO');
      await esperarRenovacion();
      expect(renovaciones, 2);
      expect(socket.conexiones, 3);
      expect(rechazosDeSesion, 0);
    });

    test('si la cuenta no tiene rol, la sesión termina sin intentar renovar', () async {
      canal.conectar();
      socket.rechazar('ROL_SIN_PERMISO');
      await esperarRenovacion();
      expect(renovaciones, 0);
      expect(socket.conexiones, 1);
      expect(rechazosDeSesion, 1);
    });

    test('si no se pudo renovar, no reconecta: la sesión ya volvió al acceso', () async {
      renovacionFunciona = false;
      canal.conectar();
      socket.rechazar('TOKEN_EXPIRADO');
      await esperarRenovacion();
      expect(renovaciones, 1);
      expect(socket.conexiones, 1);
      expect(rechazosDeSesion, 0, reason: 'de eso ya se encargó la renovación fallida');
    });

    test('un error sin código (la red o el servidor no responden) no renueva ni termina nada', () async {
      canal.conectar();
      socket.emitir('connect_error', 'websocket error');
      await esperarRenovacion();
      expect(canal.conectado, isFalse);
      expect(renovaciones, 0);
      expect(socket.conexiones, 1);
      expect(rechazosDeSesion, 0);
    });

    test('si la pantalla cerró el canal mientras renovaba, no lo vuelve a abrir', () async {
      renovacionPendiente = Completer<void>();
      canal.conectar();
      socket.rechazar('TOKEN_EXPIRADO');
      canal.cerrar();
      renovacionPendiente!.complete();
      await esperarRenovacion();
      expect(socket.cerrado, isTrue);
      expect(socket.conexiones, 1);
    });
  });

  test('los avisos siguen llegando como JSON corriente', () async {
    canal.conectar();
    final nuevo = canal.pedidosNuevos.first;
    final cambio = canal.cambiosDeEstado.first;
    final actualizado = canal.pedidosActualizados.first;
    socket.emitir('pedido:nuevo', {'id': 12, 'estado': 'pendiente'});
    socket.emitir('pedido:estado', {'id': 12, 'anterior': 'pendiente', 'nuevo': 'en_preparacion'});
    socket.emitir('pedido:actualizado', {'id': 12, 'version': 2});
    expect(await nuevo, {'id': 12, 'estado': 'pendiente'});
    expect((await cambio)['nuevo'], 'en_preparacion');
    expect((await actualizado)['version'], 2);
  });
}
