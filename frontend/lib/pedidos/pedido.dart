import 'package:flutter/foundation.dart';

/// Los estados de un pedido, en el orden en que los recorre (BRIEF, sección 4).
enum EstadoPedido {
  pendiente('Pendiente'),
  enPreparacion('En preparación'),
  listo('Listo'),
  entregado('Entregado'),
  cancelado('Cancelado');

  const EstadoPedido(this.etiqueta);
  final String etiqueta;

  /// Como lo escribe la API: en_preparacion.
  String get nombreApi => this == enPreparacion ? 'en_preparacion' : name;

  static EstadoPedido desdeApi(String texto) => switch (texto) {
        'pendiente' => pendiente,
        'en_preparacion' => enPreparacion,
        'listo' => listo,
        'entregado' => entregado,
        'cancelado' => cancelado,
        _ => throw FormatException('Estado de pedido desconocido: $texto'),
      };

  /// Los que todavía están en cocina.
  bool get enCocina => this == pendiente || this == enPreparacion;
}

/// Un extra de una pizza: "+ Extra queso".
@immutable
class ExtraDePedido {
  const ExtraDePedido({required this.nombre, required this.cantidad});
  final String nombre;
  final int cantidad;
}

/// Una línea del pedido: una pizza (de un sabor o de dos mitades, con sus extras) o una
/// bebida, con su cantidad.
@immutable
class LineaDePedido {
  const LineaDePedido({
    required this.producto,
    required this.categoria,
    required this.cantidad,
    this.mitad,
    this.extras = const [],
  });

  final String producto;
  final String categoria;
  final String? mitad;
  final int cantidad;
  final List<ExtraDePedido> extras;

  bool get esPizza => categoria == 'pizza';

  /// "Mitad Salame / mitad Peperoni", como la muestra la venta.
  String get titulo => mitad == null ? producto : 'Mitad $producto / mitad $mitad';

  factory LineaDePedido.desdeJson(Map<String, dynamic> j) {
    final producto = j['producto'] as Map<String, dynamic>;
    final mitad = j['mitad'] as Map<String, dynamic>?;
    return LineaDePedido(
      producto: producto['nombre'] as String,
      categoria: producto['categoria'] as String? ?? 'pizza',
      mitad: mitad?['nombre'] as String?,
      cantidad: j['cantidad'] as int,
      extras: [
        for (final e in (j['extras'] as List<dynamic>? ?? const []))
          ExtraDePedido(
            nombre: ((e as Map<String, dynamic>)['producto'] as Map<String, dynamic>)['nombre'] as String,
            cantidad: e['cantidad'] as int,
          ),
      ],
    );
  }
}

/// Un pedido como lo devuelve la API y como llega por el canal en vivo. El celular solo
/// viene para recepción (D-31); a cocina no le llega.
@immutable
class Pedido {
  const Pedido({
    required this.id,
    required this.estado,
    required this.paraLlevar,
    required this.cliente,
    required this.total,
    required this.creadoEn,
    this.celular,
    this.observacion,
    this.lineas = const [],
  });

  final int id;
  final EstadoPedido estado;
  final bool paraLlevar;
  final String cliente;
  final String? celular;
  final String? observacion;

  /// En centavos, como todo el dinero de la app.
  final int total;
  final DateTime creadoEn;
  final List<LineaDePedido> lineas;

  List<LineaDePedido> get pizzas => lineas.where((l) => l.esPizza).toList();
  List<LineaDePedido> get otros => lineas.where((l) => !l.esPizza).toList();

  Pedido conEstado(EstadoPedido nuevo) => Pedido(
        id: id,
        estado: nuevo,
        paraLlevar: paraLlevar,
        cliente: cliente,
        celular: celular,
        observacion: observacion,
        total: total,
        creadoEn: creadoEn,
        lineas: lineas,
      );

  factory Pedido.desdeJson(Map<String, dynamic> j) {
    final cliente = j['cliente'] as Map<String, dynamic>;
    return Pedido(
      id: j['id'] as int,
      estado: EstadoPedido.desdeApi(j['estado'] as String),
      paraLlevar: j['paraLlevar'] as bool,
      cliente: cliente['nombre'] as String,
      celular: cliente['celular'] as String?,
      observacion: j['observacion'] as String?,
      total: ((j['total'] as num) * 100).round(),
      creadoEn: DateTime.parse(j['creadoEn'] as String),
      lineas: [
        for (final l in (j['lineas'] as List<dynamic>? ?? const []))
          LineaDePedido.desdeJson(l as Map<String, dynamic>),
      ],
    );
  }
}

/// "hace 3 min", para ver de un vistazo qué pedido lleva más tiempo esperando.
String haceCuanto(DateTime desde, DateTime ahora) {
  final minutos = ahora.difference(desde).inMinutes;
  if (minutos < 1) return 'recién llegado';
  if (minutos < 60) return 'hace $minutos min';
  final horas = minutos ~/ 60;
  return 'hace $horas h ${minutos % 60} min';
}
