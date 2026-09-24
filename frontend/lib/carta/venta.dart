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
  int get precioBase =>
      segundaMitad == null ? sabor.precio : precioDeDosMitades(sabor, segundaMitad!);

  /// Cada extra suma su precio, uno solo para cualquier pizza (D-28).
  int get precioUnitario => precioBase + extras.fold(0, (s, e) => s + e.precio);

  /// Peperoni · Mitad Salame / mitad Peperoni
  String get titulo =>
      segundaMitad == null ? sabor.nombre : 'Mitad ${sabor.nombre} / mitad ${segundaMitad!.nombre}';

  /// Mitad A y mitad B es la misma pizza que mitad B y mitad A, con los mismos extras.
  bool esIgualA(PizzaElegida otra) =>
      setEquals({sabor, ?segundaMitad}, {otra.sabor, ?otra.segundaMitad}) &&
      listEquals(extras, otra.extras);
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

/// Los pasos del recorrido (D-30). Uno por pantalla. "llevar" y "cliente" llegan con la
/// tarjeta 06: el pedido dice si es para llevar (D-34) y a nombre de quién va (D-31).
enum Paso {
  cantidad, iguales, tipo, sabor, primeraMitad, segundaMitad, extras, bebidas, observacion,
  llevar, cliente, resumen,
}

/// Celular boliviano: 8 dígitos que empiezan con 6 o 7. La misma regla que el servidor y la
/// base (D-31).
final celularValido = RegExp(r'^[67][0-9]{7}$');

/// La pizza que se está definiendo, a medio camino.
@immutable
class PizzaEnCurso {
  const PizzaEnCurso({this.mitades = false, this.sabor, this.segundaMitad});
  final bool mitades;
  final Producto? sabor;
  final Producto? segundaMitad;
}

/// Todo el estado de una venta, INMUTABLE: cada paso crea uno nuevo. Así "Volver" es
/// simplemente recuperar el anterior, sin deshacer nada a mano.
@immutable
class EstadoVenta {
  const EstadoVenta({
    this.paso = Paso.cantidad,
    this.grupos = const [],
    this.bebidas = const [],
    this.observacion = '',
    this.cantidadDelTramo = 0,
    this.pendientes = 0,
    this.iguales = false,
    this.enCurso = const PizzaEnCurso(),
    this.ultimaPizza,
    this.paraLlevar,
    this.nombreCliente = '',
    this.celular = '',
  });

  final Paso paso;
  final List<GrupoPizzas> grupos;
  final List<LineaBebida> bebidas;
  final String observacion;

  /// Cuántas pizzas pidió el cliente en esta tanda, y cuántas faltan definir.
  final int cantidadDelTramo;
  final int pendientes;

  /// Si las pizzas de la tanda son todas iguales: se definen una sola vez.
  final bool iguales;
  final PizzaEnCurso enCurso;

  /// La última pizza confirmada en esta tanda: la que ofrece "Igual a la pizza anterior".
  final PizzaElegida? ultimaPizza;

  /// Nulo mientras no se preguntó (D-34).
  final bool? paraLlevar;
  final String nombreCliente;
  final String celular;

  /// Si ya se sabe a nombre de quién va y si es para llevar: al volver del resumen a cambiar
  /// algo, no se vuelve a preguntar.
  bool get clienteCompleto => paraLlevar != null && nombreCliente.trim().isNotEmpty;

  int get unidadesDePizza => grupos.fold(0, (s, g) => s + g.cantidad);
  int get unidadesDeBebida => bebidas.fold(0, (s, b) => s + b.cantidad);
  int get total =>
      grupos.fold(0, (s, g) => s + g.subtotal) + bebidas.fold(0, (s, b) => s + b.subtotal);
  bool get vacia => grupos.isEmpty && bebidas.isEmpty;

  /// Cuál pizza de la tanda se está definiendo (1, 2, 3…), cuando son distintas.
  int get pizzaActual => cantidadDelTramo - pendientes + 1;

  EstadoVenta con({
    Paso? paso,
    List<GrupoPizzas>? grupos,
    List<LineaBebida>? bebidas,
    String? observacion,
    int? cantidadDelTramo,
    int? pendientes,
    bool? iguales,
    PizzaEnCurso? enCurso,
    PizzaElegida? ultimaPizza,
    bool sinUltimaPizza = false,
    bool? paraLlevar,
    String? nombreCliente,
    String? celular,
  }) =>
      EstadoVenta(
        paso: paso ?? this.paso,
        grupos: grupos ?? this.grupos,
        bebidas: bebidas ?? this.bebidas,
        observacion: observacion ?? this.observacion,
        cantidadDelTramo: cantidadDelTramo ?? this.cantidadDelTramo,
        pendientes: pendientes ?? this.pendientes,
        iguales: iguales ?? this.iguales,
        enCurso: enCurso ?? this.enCurso,
        ultimaPizza: sinUltimaPizza ? null : (ultimaPizza ?? this.ultimaPizza),
        paraLlevar: paraLlevar ?? this.paraLlevar,
        nombreCliente: nombreCliente ?? this.nombreCliente,
        celular: celular ?? this.celular,
      );

  /// El cuerpo de POST /api/v1/pedidos. Las pizzas iguales ya vienen juntas en un grupo; cada
  /// extra va dentro de su pizza. El total es el que se mostró, en bolivianos: el servidor
  /// lo compara con el suyo y, si no coinciden, no guarda nada (409 PRECIO_CAMBIADO).
  Map<String, dynamic> aPedido() => {
        'paraLlevar': paraLlevar,
        'cliente': {
          'nombre': nombreCliente.trim(),
          'celular': celular.trim().isEmpty ? null : celular.trim(),
        },
        'observacion': observacion.trim().isEmpty ? null : observacion.trim(),
        'lineas': [
          for (final g in grupos)
            {
              'productoId': g.pizza.sabor.id,
              if (g.pizza.segundaMitad != null) 'mitadId': g.pizza.segundaMitad!.id,
              'cantidad': g.cantidad,
              if (g.pizza.extras.isNotEmpty) 'extras': [for (final e in g.pizza.extras) e.id],
            },
          for (final b in bebidas) {'productoId': b.bebida.id, 'cantidad': b.cantidad},
        ],
        'totalEsperado': total / 100,
      };
}

/// El recorrido guiado de una venta: una pregunta por pantalla, siempre hacia adelante,
/// con "Volver" en cada paso (D-30).
///
/// Es lógica pura, sin pantalla: las pruebas recorren una venta completa llamando a estos
/// métodos, y la pantalla solo muestra el paso y llama al que corresponde.
class RecorridoVenta extends ChangeNotifier {
  RecorridoVenta(this.carta);

  final Carta carta;

  /// Techo de una tanda: solo ataja un error de tipeo (200 en vez de 20).
  static const maximoPorTanda = 50;

  /// El mismo límite que la base para una línea (detalle_pedido_cantidad_valida).
  static const maximoPorLinea = 999;
  static const largoObservacion = 240;
  static const largoNombre = 120;

  EstadoVenta _estado = const EstadoVenta();
  final List<EstadoVenta> _anteriores = [];

  EstadoVenta get estado => _estado;

  /// En el resumen no se "vuelve": desde ahí se edita con sus propios botones.
  bool get puedeVolver => _anteriores.isNotEmpty && _estado.paso != Paso.resumen;

  /// Hay algo que perder si se cancela.
  bool get empezada => !_estado.vacia || _estado.paso != Paso.cantidad;

  void _ir(EstadoVenta nuevo) {
    _anteriores.add(_estado);
    _estado = nuevo;
    notifyListeners();
  }

  /// Cambia algo del paso actual sin crear un paso nuevo: las cantidades de bebidas, la
  /// observación, las ediciones del resumen. Tocar "+" diez veces no son diez pasos atrás.
  void _cambiarAqui(EstadoVenta nuevo) {
    _estado = nuevo;
    notifyListeners();
  }

  void volver() {
    if (!puedeVolver) return;
    _estado = _anteriores.removeLast();
    notifyListeners();
  }

  /// Empieza de cero: la venta en curso se descarta.
  void cancelar() {
    _anteriores.clear();
    _estado = const EstadoVenta();
    notifyListeners();
  }

  // --- 1. Cuántas pizzas -------------------------------------------------------

  void elegirCantidad(int cantidad) {
    _exigirPaso(Paso.cantidad);
    if (cantidad < 1 || cantidad > maximoPorTanda) {
      throw const VentaInvalida('La cantidad va de 1 a $maximoPorTanda pizzas.');
    }
    // Con una sola pizza no hay nada que preguntar: es "todas iguales".
    _ir(_estado.con(
      paso: cantidad == 1 ? Paso.tipo : Paso.iguales,
      cantidadDelTramo: cantidad,
      pendientes: cantidad,
      iguales: cantidad == 1,
      enCurso: const PizzaEnCurso(),
      sinUltimaPizza: true,
    ));
  }

  /// Una venta puede ser solo de bebidas (D-27).
  void soloBebidas() {
    _exigirPaso(Paso.cantidad);
    _ir(_estado.con(paso: Paso.bebidas, cantidadDelTramo: 0, pendientes: 0));
  }

  // --- 2. ¿Todas iguales? --------------------------------------------------------

  void elegirIguales(bool iguales) {
    _exigirPaso(Paso.iguales);
    _ir(_estado.con(paso: Paso.tipo, iguales: iguales));
  }

  // --- 3. ¿Un sabor o mitad y mitad? --------------------------------------------

  void elegirTipo({required bool mitades}) {
    _exigirPaso(Paso.tipo);
    _ir(_estado.con(
      paso: mitades ? Paso.primeraMitad : Paso.sabor,
      enCurso: PizzaEnCurso(mitades: mitades),
    ));
  }

  // --- 4. El sabor o las dos mitades --------------------------------------------

  void elegirSabor(Producto sabor) {
    _exigirPaso(Paso.sabor);
    _exigirPizzaDisponible(sabor);
    _alTerminarSabores(PizzaEnCurso(sabor: sabor));
  }

  void elegirPrimeraMitad(Producto sabor) {
    _exigirPaso(Paso.primeraMitad);
    _exigirPizzaDisponible(sabor);
    _ir(_estado.con(paso: Paso.segundaMitad, enCurso: PizzaEnCurso(mitades: true, sabor: sabor)));
  }

  /// Los sabores que se ofrecen como segunda mitad: todos menos el de la primera.
  List<Producto> get opcionesSegundaMitad =>
      carta.pizzas.where((p) => p != _estado.enCurso.sabor).toList();

  void elegirSegundaMitad(Producto sabor) {
    _exigirPaso(Paso.segundaMitad);
    _exigirPizzaDisponible(sabor);
    if (sabor == _estado.enCurso.sabor) {
      throw const VentaInvalida('La segunda mitad tiene que ser de otro sabor.');
    }
    _alTerminarSabores(PizzaEnCurso(mitades: true, sabor: _estado.enCurso.sabor, segundaMitad: sabor));
  }

  /// Si la carta no tiene extras disponibles, el paso de extras no se muestra.
  void _alTerminarSabores(PizzaEnCurso enCurso) {
    if (carta.extras.any((e) => e.disponible)) {
      _ir(_estado.con(paso: Paso.extras, enCurso: enCurso));
    } else {
      _ir(_estado.con(enCurso: enCurso));
      _definirPizza(const []);
    }
  }

  /// La pizza que se está armando, con los extras elegidos: para mostrar su precio.
  PizzaElegida pizzaConExtras(Iterable<Producto> extras) {
    final enCurso = _estado.enCurso;
    return PizzaElegida(sabor: enCurso.sabor!, segundaMitad: enCurso.segundaMitad, extras: extras);
  }

  // --- 5. Extras y confirmación ----------------------------------------------------

  /// Cuántas pizzas confirma el botón del paso de extras: todas las de la tanda si son
  /// iguales, una si son distintas.
  int get pizzasQueConfirma => _estado.iguales ? _estado.pendientes : 1;

  /// "Confirmar pizza 2": la pizza queda en la venta con los extras elegidos.
  void confirmarExtras(Iterable<Producto> extras) {
    _exigirPaso(Paso.extras);
    _definirPizza(extras);
  }

  /// La pizza quedó definida. Si todas son iguales, vale por las que faltan; si son
  /// distintas, vale por una, y la siguiente empieza con la opción de repetirla.
  void _definirPizza(Iterable<Producto> extras) {
    _agregarGrupo(pizzaConExtras(extras), pizzasQueConfirma, desdeAqui: _estado.paso != Paso.extras);
  }

  // --- 6. Igual a la pizza anterior -------------------------------------------------

  /// Desde la segunda pizza de una tanda de pizzas distintas, la primera pregunta ofrece
  /// repetir la anterior con un toque.
  bool get puedeRepetirAnterior =>
      _estado.paso == Paso.tipo && !_estado.iguales && _estado.pizzaActual > 1 && _estado.ultimaPizza != null;

  void repetirAnterior() {
    _exigirPaso(Paso.tipo);
    if (!puedeRepetirAnterior) throw const VentaInvalida('No hay una pizza anterior para repetir.');
    _agregarGrupo(_estado.ultimaPizza!, 1, desdeAqui: false);
  }

  void _agregarGrupo(PizzaElegida pizza, int cantidad, {required bool desdeAqui}) {
    final grupos = [..._estado.grupos];
    final i = grupos.indexWhere((g) => g.pizza.esIgualA(pizza));
    if (i >= 0) {
      final suma = grupos[i].cantidad + cantidad;
      if (suma > maximoPorLinea) throw const VentaInvalida('Una pizza admite hasta $maximoPorLinea unidades.');
      grupos[i] = GrupoPizzas(grupos[i].pizza, suma);
    } else {
      grupos.add(GrupoPizzas(pizza, cantidad));
    }
    final faltan = _estado.pendientes - cantidad;
    final nuevo = _estado.con(
      paso: faltan > 0 ? Paso.tipo : Paso.bebidas,
      grupos: grupos,
      pendientes: faltan,
      enCurso: const PizzaEnCurso(),
      ultimaPizza: pizza,
    );
    if (desdeAqui) {
      _cambiarAqui(nuevo);
    } else {
      _ir(nuevo);
    }
  }

  // --- 7. Bebidas ----------------------------------------------------------------

  int cantidadDeBebida(Producto bebida) =>
      _estado.bebidas.where((b) => b.bebida == bebida).firstOrNull?.cantidad ?? 0;

  void cambiarBebida(Producto bebida, int cantidad) {
    if (_estado.paso != Paso.bebidas && _estado.paso != Paso.resumen) {
      throw const VentaInvalida('Las bebidas se eligen en su paso o en el resumen.');
    }
    if (!bebida.esBebida) throw VentaInvalida('${bebida.nombre} no es una bebida.');
    if (cantidad > 0 && !bebida.disponible) throw VentaInvalida('${bebida.nombre} está agotada.');
    if (cantidad < 0 || cantidad > maximoPorLinea) {
      throw const VentaInvalida('Una bebida admite hasta $maximoPorLinea unidades.');
    }
    final bebidas = [..._estado.bebidas];
    final i = bebidas.indexWhere((b) => b.bebida == bebida);
    if (cantidad == 0) {
      if (i >= 0) bebidas.removeAt(i);
    } else if (i >= 0) {
      bebidas[i] = LineaBebida(bebida, cantidad);
    } else {
      bebidas.add(LineaBebida(bebida, cantidad));
    }
    _cambiarAqui(_estado.con(bebidas: bebidas));
  }

  void continuarDeBebidas() {
    _exigirPaso(Paso.bebidas);
    _ir(_estado.con(paso: Paso.observacion));
  }

  // --- 8. Observación ----------------------------------------------------------

  void escribirObservacion(String texto) {
    _exigirPaso(Paso.observacion);
    if (texto.length > largoObservacion) {
      throw const VentaInvalida('La observación admite hasta $largoObservacion caracteres.');
    }
    _cambiarAqui(_estado.con(observacion: texto));
  }

  /// Sigue a "¿para llevar?". Si ya se sabe a nombre de quién va (se volvió desde el
  /// resumen a cambiar algo), vuelve directo al resumen.
  void continuarDeObservacion() {
    _exigirPaso(Paso.observacion);
    final limpio = _estado.con(observacion: _estado.observacion.trim());
    if (limpio.clienteCompleto) {
      _alResumen(limpio);
    } else {
      _ir(limpio.con(paso: Paso.llevar));
    }
  }

  // --- 9. ¿Para llevar o para comer aquí? (D-34) -----------------------------------

  void elegirParaLlevar(bool paraLlevar) {
    _exigirPaso(Paso.llevar);
    _ir(_estado.con(paso: Paso.cliente, paraLlevar: paraLlevar));
  }

  // --- 10. ¿A nombre de quién? (D-31) -------------------------------------------------

  void escribirNombre(String nombre) {
    _exigirPaso(Paso.cliente);
    if (nombre.length > largoNombre) {
      throw const VentaInvalida('El nombre admite hasta $largoNombre caracteres.');
    }
    _cambiarAqui(_estado.con(nombreCliente: nombre));
  }

  void escribirCelular(String celular) {
    _exigirPaso(Paso.cliente);
    _cambiarAqui(_estado.con(celular: celular));
  }

  /// El nombre es obligatorio; el celular, opcional, pero si se escribe tiene que ser uno
  /// boliviano. Devuelve el problema, o null si no hay.
  String? get problemaDelCliente {
    if (_estado.nombreCliente.trim().isEmpty) return 'Escribe el nombre del cliente.';
    final celular = _estado.celular.trim();
    if (celular.isNotEmpty && !celularValido.hasMatch(celular)) {
      return 'El celular tiene 8 dígitos y empieza con 6 o 7.';
    }
    return null;
  }

  void continuarDeCliente() {
    _exigirPaso(Paso.cliente);
    final problema = problemaDelCliente;
    if (problema != null) throw VentaInvalida(problema);
    _alResumen(_estado.con(nombreCliente: _estado.nombreCliente.trim(), celular: _estado.celular.trim()));
  }

  /// Pasa al resumen. Desde ahí ya no se "vuelve": se edita con sus botones.
  void _alResumen(EstadoVenta estado) {
    _ir(estado.con(paso: Paso.resumen));
    _anteriores.clear();
  }

  // --- 11. Resumen ---------------------------------------------------------------

  void cambiarCantidadDeGrupo(int indice, int cantidad) {
    _exigirPaso(Paso.resumen);
    if (cantidad > maximoPorLinea) throw const VentaInvalida('Una pizza admite hasta $maximoPorLinea unidades.');
    final grupos = [..._estado.grupos];
    if (cantidad <= 0) {
      grupos.removeAt(indice);
    } else {
      grupos[indice] = GrupoPizzas(grupos[indice].pizza, cantidad);
    }
    _cambiarAqui(_estado.con(grupos: grupos));
  }

  /// El cliente cambió de idea: vuelve a preguntar cuántas, y suma a la misma venta.
  void agregarMasPizzas() {
    _exigirPaso(Paso.resumen);
    _ir(_estado.con(paso: Paso.cantidad));
  }

  void cambiarBebidas() {
    _exigirPaso(Paso.resumen);
    _ir(_estado.con(paso: Paso.bebidas));
  }

  void cambiarObservacion() {
    _exigirPaso(Paso.resumen);
    _ir(_estado.con(paso: Paso.observacion));
  }

  /// Vuelve a preguntar si es para llevar y a nombre de quién, con lo ya escrito.
  void cambiarCliente() {
    _exigirPaso(Paso.resumen);
    _ir(_estado.con(paso: Paso.llevar));
  }

  // --- Validaciones --------------------------------------------------------------

  void _exigirPaso(Paso paso) {
    if (_estado.paso != paso) {
      throw VentaInvalida('Este paso no corresponde ahora (${_estado.paso.name}).');
    }
  }

  void _exigirPizzaDisponible(Producto p) {
    if (!p.esPizza) throw VentaInvalida('${p.nombre} no es una pizza.');
    if (!p.disponible) throw VentaInvalida('${p.nombre} está agotada.');
  }
}
