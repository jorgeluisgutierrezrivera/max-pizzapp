/// Un producto de la carta, tal como lo entrega GET /api/v1/productos, y la carta completa.
library;

enum Categoria { pizza, entrada, bebida, postre, extra }

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

/// La carta, separada como la recorre la venta: pizzas, extras y bebidas, cada grupo en
/// orden alfabético (D-30).
class Carta {
  Carta(Iterable<Producto> productos)
    : pizzas = _ordenados(productos.where((p) => p.esPizza)),
      extras = _ordenados(productos.where((p) => p.esExtra)),
      bebidas = _ordenados(productos.where((p) => p.esBebida));

  final List<Producto> pizzas;
  final List<Producto> extras;
  final List<Producto> bebidas;

  bool get vacia => pizzas.isEmpty && bebidas.isEmpty;

  static List<Producto> _ordenados(Iterable<Producto> productos) =>
      List.unmodifiable(productos.toList()..sort((a, b) => _clave(a.nombre).compareTo(_clave(b.nombre))));

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
