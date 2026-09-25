import 'package:flutter/foundation.dart';

import 'producto.dart';

/// Una combinación que las reglas de venta no permiten (D-27, D-28).
class VentaInvalida implements Exception {
  const VentaInvalida(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Una pizza ya definida: un sabor, o dos mitades de sabores distintos, con sus extras.
@immutable
class PizzaElegida {
  PizzaElegida({required this.sabor, this.segundaMitad, Iterable<Producto> extras = const []})
    : extras = List.unmodifiable(extras.toSet().toList()..sort((a, b) => a.id.compareTo(b.id))) {
    for (final p in [sabor, ?segundaMitad]) {
      if (!p.esPizza) throw VentaInvalida('${p.nombre} no es una pizza.');
      if (!p.disponible) throw VentaInvalida('${p.nombre} está agotada.');
    }
    if (segundaMitad == sabor) {
      throw const VentaInvalida('Dos mitades del mismo sabor son una pizza de ese sabor.');
    }
    if (segundaMitad != null) {
      for (final p in [sabor, segundaMitad!]) {
        if (p.soloEntera) throw VentaInvalida('${p.nombre} se vende solo entera, no por mitades.');
      }
    }
    for (final e in this.extras) {
      if (!e.esExtra) throw VentaInvalida('${e.nombre} no es un extra.');
      if (!e.disponible) throw VentaInvalida('${e.nombre} está agotado.');
    }
  }

  /// En una pizza de dos mitades, la primera.
  final Producto sabor;
  final Producto? segundaMitad;
  final List<Producto> extras;

  bool get esMitadYMitad => segundaMitad != null;

  /// La pizza sin extras (D-27): su precio, o (A + B) / 2 si es de dos mitades.
  int get precioBase => segundaMitad == null ? sabor.precio : precioDeDosMitades(sabor, segundaMitad!);

  /// Cada extra suma su precio, uno solo para cualquier pizza (D-28).
  int get precioUnitario => precioBase + extras.fold(0, (s, e) => s + e.precio);

  /// Peperoni · Mitad Salame / mitad Peperoni
  String get titulo => segundaMitad == null ? sabor.nombre : 'Mitad ${sabor.nombre} / mitad ${segundaMitad!.nombre}';

  /// Mitad A y mitad B es la misma pizza que mitad B y mitad A, con los mismos extras.
  bool esIgualA(PizzaElegida otra) =>
      setEquals({sabor, ?segundaMitad}, {otra.sabor, ?otra.segundaMitad}) && listEquals(extras, otra.extras);

  /// La línea de POST /api/v1/pedidos: cada extra va dentro de su pizza.
  Map<String, dynamic> aLinea(int cantidad) => {
    'productoId': sabor.id,
    if (segundaMitad != null) 'mitadId': segundaMitad!.id,
    'cantidad': cantidad,
    if (extras.isNotEmpty) 'extras': [for (final e in extras) e.id],
  };
}

@immutable
class GrupoPizzas {
  const GrupoPizzas(this.pizza, this.cantidad);
  final PizzaElegida pizza;
  final int cantidad;
  int get subtotal => pizza.precioUnitario * cantidad;
}

@immutable
class LineaBebida {
  const LineaBebida(this.bebida, this.cantidad);
  final Producto bebida;
  final int cantidad;
  int get subtotal => bebida.precio * cantidad;
}

/// Celular boliviano: 8 dígitos que empiezan con 6 o 7. La misma regla que el servidor y la
/// base (D-31).
final celularValido = RegExp(r'^[67][0-9]{7}$');

/// El mismo límite que la base para una línea (detalle_pedido_cantidad_valida).
const maximoPorLinea = 999;

/// Las bebidas de una venta, con sus cantidades. Las usan el formulario y la venta directa.
class _Bebidas {
  List<LineaBebida> lineas = const [];

  int cantidadDe(Producto bebida) => lineas.where((b) => b.bebida == bebida).firstOrNull?.cantidad ?? 0;

  void cambiar(Producto bebida, int cantidad) {
    if (!bebida.esBebida) throw VentaInvalida('${bebida.nombre} no es una bebida.');
    if (cantidad > cantidadDe(bebida) && !bebida.disponible) throw VentaInvalida('${bebida.nombre} está agotada.');
    if (cantidad < 0 || cantidad > maximoPorLinea) {
      throw const VentaInvalida('Una bebida admite hasta $maximoPorLinea unidades.');
    }
    final nuevas = [...lineas];
    final i = nuevas.indexWhere((b) => b.bebida == bebida);
    if (cantidad == 0) {
      if (i >= 0) nuevas.removeAt(i);
    } else if (i >= 0) {
      nuevas[i] = LineaBebida(bebida, cantidad);
    } else {
      nuevas.add(LineaBebida(bebida, cantidad));
    }
    lineas = List.unmodifiable(nuevas);
  }

  int get total => lineas.fold(0, (s, b) => s + b.subtotal);
  List<Map<String, dynamic>> aLineas() => [
    for (final b in lineas) {'productoId': b.bebida.id, 'cantidad': b.cantidad},
  ];
}

/// La venta en un solo formulario (D-36), en el orden en que se atiende en el mostrador:
/// el cliente, si es para llevar o para comer aquí, las pizzas, las bebidas y la
/// observación. Todo se puede corregir en el lugar hasta confirmar.
///
/// Es lógica pura, sin pantalla: las pruebas arman una venta completa llamando a estos
/// métodos, y la pantalla solo muestra el estado y llama al que corresponde.
class FormularioVenta extends ChangeNotifier {
  FormularioVenta(this.carta);

  final Carta carta;

  static const largoObservacion = 240;
  static const largoNombre = 120;

  String _nombre = '';
  String _celular = '';
  bool? _paraLlevar;
  String _observacion = '';
  List<GrupoPizzas> _grupos = const [];
  final _bebidas = _Bebidas();

  String get nombre => _nombre;
  String get celular => _celular;

  /// Nulo mientras no se eligió: no hay una opción marcada de entrada (D-36).
  bool? get paraLlevar => _paraLlevar;
  String get observacion => _observacion;
  List<GrupoPizzas> get grupos => _grupos;
  List<LineaBebida> get bebidas => _bebidas.lineas;

  int get unidadesDePizza => _grupos.fold(0, (s, g) => s + g.cantidad);
  int get total => _grupos.fold(0, (s, g) => s + g.subtotal) + _bebidas.total;

  /// No hay nada escrito ni elegido: cancelarla no pierde nada.
  bool get vacia =>
      _grupos.isEmpty &&
      _bebidas.lineas.isEmpty &&
      _nombre.trim().isEmpty &&
      _celular.isEmpty &&
      _paraLlevar == null &&
      _observacion.trim().isEmpty;

  // --- El cliente -------------------------------------------------------------------

  void escribirNombre(String nombre) {
    if (nombre.length > largoNombre) throw const VentaInvalida('El nombre admite hasta $largoNombre caracteres.');
    _nombre = nombre;
    notifyListeners();
  }

  void escribirCelular(String celular) {
    _celular = celular;
    notifyListeners();
  }

  void elegirParaLlevar(bool paraLlevar) {
    _paraLlevar = paraLlevar;
    notifyListeners();
  }

  void escribirObservacion(String texto) {
    if (texto.length > largoObservacion) {
      throw const VentaInvalida('La observación admite hasta $largoObservacion caracteres.');
    }
    _observacion = texto;
    notifyListeners();
  }

  // --- Las pizzas -------------------------------------------------------------------

  /// La pizza del modal, con su cantidad. Si ya hay una igual, se suma a esa línea.
  void agregarPizza(PizzaElegida pizza, int cantidad) {
    _grupos = _conPizza(_grupos, pizza, cantidad);
    notifyListeners();
  }

  /// La pizza de una línea, corregida en el modal. Si quedó igual a otra, se juntan.
  void reemplazarPizza(int indice, PizzaElegida pizza, int cantidad) {
    final sin = [..._grupos]..removeAt(indice);
    _grupos = _conPizza(sin, pizza, cantidad, en: indice);
    notifyListeners();
  }

  /// − y + de una línea. En cero, la línea sale.
  void cambiarCantidadDeGrupo(int indice, int cantidad) {
    if (cantidad > maximoPorLinea) throw const VentaInvalida('Una pizza admite hasta $maximoPorLinea unidades.');
    final grupos = [..._grupos];
    if (cantidad <= 0) {
      grupos.removeAt(indice);
    } else {
      grupos[indice] = GrupoPizzas(grupos[indice].pizza, cantidad);
    }
    _grupos = List.unmodifiable(grupos);
    notifyListeners();
  }

  void quitarPizza(int indice) => cambiarCantidadDeGrupo(indice, 0);

  static List<GrupoPizzas> _conPizza(List<GrupoPizzas> grupos, PizzaElegida pizza, int cantidad, {int? en}) {
    if (cantidad < 1 || cantidad > maximoPorLinea) {
      throw const VentaInvalida('La cantidad va de 1 a $maximoPorLinea.');
    }
    final nuevos = [...grupos];
    final i = nuevos.indexWhere((g) => g.pizza.esIgualA(pizza));
    if (i >= 0) {
      final suma = nuevos[i].cantidad + cantidad;
      if (suma > maximoPorLinea) throw const VentaInvalida('Una pizza admite hasta $maximoPorLinea unidades.');
      nuevos[i] = GrupoPizzas(nuevos[i].pizza, suma);
    } else {
      nuevos.insert(en ?? nuevos.length, GrupoPizzas(pizza, cantidad));
    }
    return List.unmodifiable(nuevos);
  }

  // --- Las bebidas ------------------------------------------------------------------

  int cantidadDeBebida(Producto bebida) => _bebidas.cantidadDe(bebida);

  void cambiarBebida(Producto bebida, int cantidad) {
    _bebidas.cambiar(bebida, cantidad);
    notifyListeners();
  }

  // --- Confirmar --------------------------------------------------------------------

  /// Lo que falta para confirmar, en el orden del formulario. Vacía si se puede enviar.
  /// Las mismas reglas que el servidor: nombre obligatorio, celular boliviano si se
  /// escribe, para llevar o no, y al menos una pizza (D-31, D-34, D-38).
  List<String> get problemas => [
    if (_nombre.trim().isEmpty) 'Escribe el nombre del cliente.',
    if (_celular.trim().isNotEmpty && !celularValido.hasMatch(_celular.trim()))
      'El celular tiene 8 dígitos y empieza con 6 o 7.',
    if (_paraLlevar == null) 'Elige si es para comer aquí o para llevar.',
    if (_grupos.isEmpty)
      _bebidas.lineas.isEmpty
          ? 'Agrega al menos una pizza.'
          : 'Agrega al menos una pizza. Las bebidas solas se venden con «Vender bebidas».',
  ];

  /// El cuerpo de POST /api/v1/pedidos. El total es el que se mostró, en bolivianos: el
  /// servidor lo compara con el suyo y, si no coinciden, no guarda nada (409 PRECIO_CAMBIADO).
  Map<String, dynamic> aPedido() {
    final pendiente = problemas;
    if (pendiente.isNotEmpty) throw VentaInvalida(pendiente.first);
    return {
      'paraLlevar': _paraLlevar,
      'cliente': {'nombre': _nombre.trim(), 'celular': _celular.trim().isEmpty ? null : _celular.trim()},
      'observacion': _observacion.trim().isEmpty ? null : _observacion.trim(),
      'lineas': [for (final g in _grupos) g.pizza.aLinea(g.cantidad), ..._bebidas.aLineas()],
      'totalEsperado': total / 100,
    };
  }

  /// Empieza de cero: después de enviar, o si se cancela la venta.
  void limpiar() {
    _nombre = '';
    _celular = '';
    _paraLlevar = null;
    _observacion = '';
    _grupos = const [];
    _bebidas.lineas = const [];
    notifyListeners();
  }
}

/// La pizza que se arma en el modal (D-36): entera o mitad y mitad, sus sabores, sus extras
/// y cuántas. Mientras falte un sabor, no hay pizza.
class ArmadoDePizza extends ChangeNotifier {
  ArmadoDePizza(this.carta, {PizzaElegida? desde, int cantidad = 1})
    : _mitades = desde?.esMitadYMitad ?? false,
      _primera = desde?.sabor,
      _segunda = desde?.segundaMitad,
      _extras = {...?desde?.extras},
      _cantidad = cantidad < 1 ? 1 : cantidad;

  final Carta carta;

  /// Techo del modal: solo ataja un error de tipeo (200 en vez de 20).
  static const maximoPorVez = 50;

  bool _mitades;
  Producto? _primera;
  Producto? _segunda;
  final Set<Producto> _extras;
  int _cantidad;

  bool get mitades => _mitades;
  Producto? get primera => _primera;
  Producto? get segunda => _segunda;
  Set<Producto> get extras => Set.unmodifiable(_extras);
  int get cantidad => _cantidad;

  /// Entera o mitad y mitad. Al pasar a entera, se queda el primer sabor elegido; al pasar a
  /// mitad y mitad, se suelta si es una pizza que se vende solo entera (D-39).
  void elegirMitades(bool mitades) {
    _mitades = mitades;
    if (!mitades) _segunda = null;
    if (mitades && (_primera?.soloEntera ?? false)) _primera = null;
    notifyListeners();
  }

  /// Si el sabor se puede tocar ahora: una pizza solo entera no sirve de mitad (D-39).
  bool sePuedeElegir(Producto sabor) => sabor.disponible && !(_mitades && sabor.soloEntera);

  /// Entera: el sabor tocado es el sabor. Mitad y mitad: el primero que se toca es la
  /// primera mitad y el segundo, la segunda; tocar uno elegido lo quita, y con las dos
  /// elegidas, un tercero reemplaza a la segunda.
  void tocarSabor(Producto sabor) {
    if (!sabor.esPizza) throw VentaInvalida('${sabor.nombre} no es una pizza.');
    if (!sabor.disponible) throw VentaInvalida('${sabor.nombre} está agotada.');
    if (_mitades && sabor.soloEntera) {
      throw VentaInvalida('${sabor.nombre} se vende solo entera, no por mitades.');
    }
    if (!_mitades) {
      _primera = sabor;
    } else if (sabor == _primera) {
      _primera = _segunda;
      _segunda = null;
    } else if (sabor == _segunda) {
      _segunda = null;
    } else if (_primera == null) {
      _primera = sabor;
    } else {
      _segunda = sabor;
    }
    notifyListeners();
  }

  /// 1 o 2 si el sabor es una de las mitades; 1 si es el sabor de una entera; si no, nulo.
  int? lugarDe(Producto sabor) {
    if (sabor == _primera) return 1;
    if (sabor == _segunda) return 2;
    return null;
  }

  void alternarExtra(Producto extra) {
    if (!extra.esExtra) throw VentaInvalida('${extra.nombre} no es un extra.');
    if (!_extras.remove(extra)) {
      if (!extra.disponible) throw VentaInvalida('${extra.nombre} está agotado.');
      _extras.add(extra);
    }
    notifyListeners();
  }

  void cambiarCantidad(int cantidad) {
    if (cantidad < 1 || cantidad > maximoPorVez) {
      throw const VentaInvalida('La cantidad va de 1 a $maximoPorVez.');
    }
    _cantidad = cantidad;
    notifyListeners();
  }

  /// Qué falta elegir, o nulo si la pizza está completa.
  String? get falta {
    if (_primera == null) return _mitades ? 'Elige los dos sabores' : 'Elige el sabor';
    if (_mitades && _segunda == null) return 'Elige la segunda mitad';
    return null;
  }

  PizzaElegida? get pizza =>
      falta != null ? null : PizzaElegida(sabor: _primera!, segundaMitad: _mitades ? _segunda : null, extras: _extras);

  /// El precio de todas las que se agregan: el único precio del modal.
  int? get subtotal {
    final p = pizza;
    return p == null ? null : p.precioUnitario * _cantidad;
  }
}

/// La venta directa de bebidas (D-38): sin nombre ni preguntas, se entrega en el momento.
class VentaDeBebidas extends ChangeNotifier {
  VentaDeBebidas(this.carta);

  final Carta carta;
  final _bebidas = _Bebidas();

  List<LineaBebida> get lineas => _bebidas.lineas;
  int get total => _bebidas.total;
  bool get vacia => _bebidas.lineas.isEmpty;
  int cantidadDe(Producto bebida) => _bebidas.cantidadDe(bebida);

  void cambiar(Producto bebida, int cantidad) {
    _bebidas.cambiar(bebida, cantidad);
    notifyListeners();
  }

  /// El cuerpo de POST /api/v1/pedidos para una venta directa: sin cliente, sin "para
  /// llevar" y sin observación; el servidor la guarda entregada.
  Map<String, dynamic> aVentaDirecta() {
    if (vacia) throw const VentaInvalida('Elige al menos una bebida.');
    return {'ventaDirecta': true, 'lineas': _bebidas.aLineas(), 'totalEsperado': total / 100};
  }
}

/// Lo que se agrega a un pedido ya enviado (D-37): la soda que el cliente pide después de la
/// pizza, sin hacer otro pedido. Las pizzas, solo mientras cocina no lo terminó; las bebidas,
/// hasta que se entregue. El servidor vuelve a decidirlo con el estado de ese momento.
class AgregadoAPedido extends ChangeNotifier {
  AgregadoAPedido(this.carta, {required this.permitePizzas});

  final Carta carta;
  final bool permitePizzas;

  List<GrupoPizzas> _grupos = const [];
  final _bebidas = _Bebidas();

  List<GrupoPizzas> get grupos => _grupos;
  List<LineaBebida> get bebidas => _bebidas.lineas;
  int get total => _grupos.fold(0, (s, g) => s + g.subtotal) + _bebidas.total;
  bool get vacio => _grupos.isEmpty && _bebidas.lineas.isEmpty;

  void agregarPizza(PizzaElegida pizza, int cantidad) {
    if (!permitePizzas) {
      throw const VentaInvalida('El pedido ya está listo: las pizzas nuevas van en otro pedido.');
    }
    _grupos = FormularioVenta._conPizza(_grupos, pizza, cantidad);
    notifyListeners();
  }

  void cambiarCantidadDeGrupo(int indice, int cantidad) {
    final grupos = [..._grupos];
    if (cantidad <= 0) {
      grupos.removeAt(indice);
    } else {
      if (cantidad > maximoPorLinea) throw const VentaInvalida('Una pizza admite hasta $maximoPorLinea unidades.');
      grupos[indice] = GrupoPizzas(grupos[indice].pizza, cantidad);
    }
    _grupos = List.unmodifiable(grupos);
    notifyListeners();
  }

  int cantidadDeBebida(Producto bebida) => _bebidas.cantidadDe(bebida);

  void cambiarBebida(Producto bebida, int cantidad) {
    _bebidas.cambiar(bebida, cantidad);
    notifyListeners();
  }

  /// El cuerpo de POST /api/v1/pedidos/:id/lineas. El total es el de lo agregado, en
  /// bolivianos: el servidor lo compara con el suyo.
  Map<String, dynamic> aCuerpo() {
    if (vacio) throw const VentaInvalida('Elige al menos un producto para agregar.');
    return {
      'lineas': [for (final g in _grupos) g.pizza.aLinea(g.cantidad), ..._bebidas.aLineas()],
      'totalEsperado': total / 100,
    };
  }
}
