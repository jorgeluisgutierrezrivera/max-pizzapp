/// Un producto de la carta, tal como lo entrega GET /api/v1/productos, y la carta completa.
library;

import 'package:flutter/foundation.dart';

enum Categoria { pizza, entrada, bebida, postre, extra }

/// "todas las pizzas", "todos los extras": para los avisos y el panel (D-70, D-71).
String todosLos(Categoria categoria) => switch (categoria) {
  Categoria.pizza => 'todas las pizzas',
  Categoria.entrada => 'todas las entradas',
  Categoria.bebida => 'todas las bebidas',
  Categoria.postre => 'todos los postres',
  Categoria.extra => 'todos los extras',
};

/// Si la palabra de la categoría es femenina: "agotadas" o "agotados".
bool esFemenina(Categoria categoria) => categoria != Categoria.postre && categoria != Categoria.extra;

/// Lo que agota y repone cada rol en el panel *Carta* (D-76), lo mismo que comprueba el
/// servidor: lo que sale de la cocina, cocina; las bebidas, recepción, que las tiene en el
/// mostrador.
const categoriasDeCocina = {Categoria.pizza, Categoria.extra, Categoria.entrada, Categoria.postre};
const categoriasDeRecepcion = {Categoria.bebida};

/// Los precios se guardan en CENTAVOS, como enteros: sumar decimales en coma flotante
/// termina, tarde o temprano, en un total de 79,99999. La API los manda como números con
/// dos decimales; aquí se convierten una sola vez.
class Producto {
  const Producto({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.precio,
    required this.descripcion,
    required this.imagen,
    required this.disponible,
    this.soloEntera = false,
  });

  factory Producto.desdeJson(Map<String, dynamic> json) {
    final nombreCategoria = json['categoria'] as String;
    final categoria = Categoria.values.where((c) => c.name == nombreCategoria).firstOrNull;
    if (categoria == null) {
      throw FormatException('Categoría desconocida: $nombreCategoria');
    }
    return Producto(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      categoria: categoria,
      precio: ((json['precio'] as num) * 100).round(),
      descripcion: json['descripcion'] as String?,
      imagen: json['imagen'] as String?,
      disponible: json['disponible'] as bool,
      soloEntera: json['soloEntera'] as bool? ?? false,
    );
  }

  final int id;
  final String nombre;
  final Categoria categoria;

  /// En centavos.
  final int precio;

  /// Los ingredientes, que la vendedora ve al elegir. Puede faltar.
  final String? descripcion;

  /// Solo el nombre del archivo de la imagen (peperoni.png).
  final String? imagen;
  final bool disponible;

  /// Una pizza que ya combina sabores (Dos estaciones, Tres estaciones, Criolla española): se
  /// vende solo entera, nunca como mitad de otra (D-39).
  final bool soloEntera;

  bool get esPizza => categoria == Categoria.pizza;
  bool get esBebida => categoria == Categoria.bebida;
  bool get esExtra => categoria == Categoria.extra;

  /// El mismo producto, agotado o disponible (RF-13).
  Producto conDisponible(bool disponible) => Producto(
    id: id,
    nombre: nombre,
    categoria: categoria,
    precio: precio,
    descripcion: descripcion,
    imagen: imagen,
    disponible: disponible,
    soloEntera: soloEntera,
  );

  /// Lo que aporta como mitad de una pizza de dos sabores: la mitad exacta (D-27). Se usa
  /// para mostrarlo; el precio de la pizza se calcula con [precioDeDosMitades].
  int get precioDeMitad => (precio + 1) ~/ 2;

  @override
  bool operator ==(Object other) => other is Producto && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Una pizza de dos mitades cuesta (precio A + precio B) / 2, al centavo, redondeando la
/// mitad de centavo hacia arriba (D-27). Con los precios de la carta, en bolivianos
/// enteros, el resultado siempre es exacto: 45 y 50 dan 47,50.
int precioDeDosMitades(Producto a, Producto b) => (a.precio + b.precio + 1) ~/ 2;

/// La carta, separada como la recorre la venta: pizzas, extras y bebidas. Las pizzas y los
/// extras van en orden alfabético, que es como se buscan (D-30); las bebidas, en el orden en
/// que se piden (D-74).
///
/// Avisa cuando un producto se agota o se repone (RF-13, D-67). El aviso en vivo cambia el
/// producto DENTRO de esta misma carta, sin reemplazarla: la venta que se está armando está
/// atada a la carta, y una carta nueva la empezaría de cero.
class Carta extends ChangeNotifier {
  Carta(Iterable<Producto> productos)
    : _pizzas = _ordenados(productos.where((p) => p.esPizza)),
      _extras = _ordenados(productos.where((p) => p.esExtra)),
      _bebidas = _comoSePiden(productos.where((p) => p.esBebida));

  List<Producto> _pizzas;
  List<Producto> _extras;
  List<Producto> _bebidas;

  List<Producto> get pizzas => _pizzas;
  List<Producto> get extras => _extras;
  List<Producto> get bebidas => _bebidas;

  bool get vacia => _pizzas.isEmpty && _bebidas.isEmpty;

  /// Todos, en el orden de la carta del local: pizzas, bebidas y extras.
  List<Producto> get todos => [..._pizzas, ..._bebidas, ..._extras];

  Producto? porId(int id) => todos.where((p) => p.id == id).firstOrNull;

  /// Si el producto se puede vender ahora, según esta carta. Hace falta porque el producto
  /// que guarda una venta a medio armar puede ser de antes del aviso.
  bool estaDisponible(Producto producto) => porId(producto.id)?.disponible ?? producto.disponible;

  /// Agota o repone un producto. Devuelve si cambió algo: un aviso repetido, o el de un
  /// cambio que esta misma pantalla ya aplicó, no vuelve a dibujar nada.
  bool marcarDisponibilidad(int id, bool disponible) {
    final cambio = _marcar(id, disponible);
    if (cambio) notifyListeners();
    return cambio;
  }

  /// Agota o repone una categoría entera (D-70), por ejemplo todas las pizzas cuando se acaba
  /// la masa. Devuelve cuántos productos cambiaron y avisa una sola vez.
  int marcarCategoria(Categoria categoria, bool disponible) {
    var cambiados = 0;
    for (final producto in todos.where((p) => p.categoria == categoria)) {
      if (_marcar(producto.id, disponible)) cambiados++;
    }
    if (cambiados > 0) notifyListeners();
    return cambiados;
  }

  /// La carta tiene pizzas y no queda ninguna disponible: la venta lo dice (D-71).
  bool get sinPizzas => _pizzas.isNotEmpty && _pizzas.every((p) => !p.disponible);

  /// La disponibilidad de una carta recién leída, por ejemplo al reconectar el canal, que
  /// pudo perderse algún aviso. Solo la disponibilidad: los precios los vuelve a controlar
  /// el servidor al vender (409 PRECIO_CAMBIADO).
  void aplicarDisponibilidadDe(Carta otra) {
    var cambio = false;
    for (final producto in otra.todos) {
      cambio = _marcar(producto.id, producto.disponible) || cambio;
    }
    if (cambio) notifyListeners();
  }

  bool _marcar(int id, bool disponible) {
    var cambio = false;
    List<Producto> reemplazar(List<Producto> lista) {
      final i = lista.indexWhere((p) => p.id == id);
      if (i < 0 || lista[i].disponible == disponible) return lista;
      cambio = true;
      return List.unmodifiable([...lista]..[i] = lista[i].conDisponible(disponible));
    }

    _pizzas = reemplazar(_pizzas);
    _extras = reemplazar(_extras);
    _bebidas = reemplazar(_bebidas);
    return cambio;
  }

  static List<Producto> _ordenados(Iterable<Producto> productos) =>
      List.unmodifiable(productos.toList()..sort((a, b) => _clave(a.nombre).compareTo(_clave(b.nombre))));

  /// Las bebidas, como se piden en el mostrador (D-74): por tipo, que es la primera palabra
  /// del nombre (Agua, Jugo, Soda), y dentro de cada tipo por precio, que en las sodas es el
  /// tamaño. Por nombre, la soda personal quedaría detrás de la de 2 litros.
  static List<Producto> _comoSePiden(Iterable<Producto> bebidas) {
    String tipo(Producto p) => _clave(p.nombre.trim().split(' ').first);
    return List.unmodifiable(
      bebidas.toList()..sort((a, b) {
        final porTipo = tipo(a).compareTo(tipo(b));
        if (porTipo != 0) return porTipo;
        final porPrecio = a.precio.compareTo(b.precio);
        return porPrecio != 0 ? porPrecio : _clave(a.nombre).compareTo(_clave(b.nombre));
      }),
    );
  }

  /// Orden alfabético sin mirar tildes ni mayúsculas, como lo ordena la base.
  static String _clave(String texto) {
    const conTilde = 'áéíóúüñ';
    const sinTilde = 'aeiouun';
    final minusculas = texto.toLowerCase();
    final salida = StringBuffer();
    for (final letra in minusculas.split('')) {
      final i = conTilde.indexOf(letra);
      salida.write(i >= 0 ? sinTilde[i] : letra);
    }
    return salida.toString();
  }
}

/// Solo nombres simples, igual que la restricción de la base: una respuesta alterada no
/// puede hacer que la app cargue una imagen de otro lugar.
final _nombreDeImagen = RegExp(r'^[a-z0-9-]+\.(png|jpg|webp)$');

/// La dirección de la imagen, relativa a la app: viajan con ella, en web/carta/. Nula si
/// el producto no tiene una o el nombre no es válido.
String? rutaDeImagen(Producto producto) {
  final imagen = producto.imagen;
  if (imagen == null || !_nombreDeImagen.hasMatch(imagen)) return null;
  return 'carta/$imagen';
}

/// Bs 65 · Bs 47,50
String formatoBs(int centavos) {
  final enteros = centavos ~/ 100;
  final resto = centavos % 100;
  return resto == 0 ? 'Bs $enteros' : 'Bs $enteros,${resto.toString().padLeft(2, '0')}';
}
