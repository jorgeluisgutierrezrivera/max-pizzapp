import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/canal_en_vivo.dart';
import 'pedido.dart';

/// Los pedidos que recepción tiene que atender (RF-03, RF-04), al día sin recargar: los que
/// están en cocina y los listos para entregar.
///
/// La lista la da la API; el canal en vivo solo avisa. Si la conexión se corta y vuelve, la
/// lista se vuelve a leer: mientras estuvo cortada pudo perderse algún aviso.
///
/// Es lógica sin pantalla: la usan la pestaña *Pedidos*, el contador de listos de la barra y
/// el aviso que suena cuando un pedido queda listo.
class PedidosEnVivo extends ChangeNotifier {
  PedidosEnVivo({required this.cargar, required this.canal});

  /// GET /api/v1/pedidos: los activos.
  final Future<List<Pedido>> Function() cargar;
  final CanalEnVivo canal;

  final List<StreamSubscription<dynamic>> _suscripciones = [];
  final _quedaronListos = StreamController<Pedido>.broadcast();

  List<Pedido>? _pedidos;
  Object? _error;
  bool _conectado = false;

  /// Nulo hasta la primera lectura.
  List<Pedido>? get pedidos => _pedidos;
  Object? get error => _error;
  bool get conectado => _conectado;

  /// Cada pedido que cocina marca listo, para que recepción lo sepa ya: suena y se avisa.
  Stream<Pedido> get quedaronListos => _quedaronListos.stream;

  /// Los listos primero, porque son los que hay que entregar; después los que están en
  /// cocina. Dentro de cada grupo, en orden de llegada.
  List<Pedido> get ordenados {
    final todos = [...?_pedidos];
    int grupo(Pedido p) => p.estado == EstadoPedido.listo ? 0 : 1;
    todos.sort((a, b) {
      final g = grupo(a).compareTo(grupo(b));
      if (g != 0) return g;
      final c = a.creadoEn.compareTo(b.creadoEn);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return todos;
  }

  int get listos => (_pedidos ?? const []).where((p) => p.estado == EstadoPedido.listo).length;

  void iniciar() {
    _suscripciones
      ..add(canal.pedidosNuevos.listen(_alLlegar))
      ..add(canal.pedidosActualizados.listen(_alLlegar))
      ..add(canal.cambiosDeEstado.listen(_alCambiarEstado))
      ..add(canal.conexion.listen(_alCambiarConexion));
    canal.conectar();
    leer();
  }

  Future<void> leer() async {
    _error = null;
    notifyListeners();
    try {
      final pedidos = await cargar();
      _pedidos = [
        for (final p in pedidos)
          if (p.estado.activo) p,
      ];
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  /// Un pedido nuevo, o uno al que se le agregó algo: entra o reemplaza al que estaba.
  void _alLlegar(Map<String, dynamic> json) => reemplazar(Pedido.desdeJson(json));

  /// Lo que devolvió la API después de una acción propia, o lo que avisó el canal.
  void reemplazar(Pedido pedido) {
    final pedidos = _pedidos;
    if (pedidos == null) return; // todavía no cargó: va a venir en la lectura
    final i = pedidos.indexWhere((p) => p.id == pedido.id);
    if (!pedido.estado.activo) {
      if (i >= 0) _pedidos = [...pedidos]..removeAt(i);
    } else if (i >= 0) {
      _pedidos = [...pedidos]..[i] = pedido;
    } else {
      _pedidos = [...pedidos, pedido];
    }
    notifyListeners();
  }

  void _alCambiarEstado(Map<String, dynamic> aviso) {
    final pedidos = _pedidos;
    if (pedidos == null) return;
    final id = aviso['id'] as int;
    final nuevo = EstadoPedido.desdeApi(aviso['nuevo'] as String);
    final i = pedidos.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final antes = pedidos[i];
    if (antes.estado == nuevo) return; // ya estaba al día, por una acción propia
    final ahora = antes.conEstado(nuevo);
    reemplazar(ahora);
    if (nuevo == EstadoPedido.listo) _quedaronListos.add(ahora);
  }

  void _alCambiarConexion(bool conectado) {
    _conectado = conectado;
    notifyListeners();
    if (conectado) leer(); // al volver, ponerse al día con la API
  }

  @override
  void dispose() {
    for (final s in _suscripciones) {
      s.cancel();
    }
    _quedaronListos.close();
    canal.cerrar();
    super.dispose();
  }
}
