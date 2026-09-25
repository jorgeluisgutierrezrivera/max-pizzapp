import 'package:flutter/material.dart';

import '../../carta/producto.dart';
import '../../tema.dart';

/// Cómo se dibuja una imagen a partir de su ruta. En la app es una imagen de red relativa a
/// la página; las pruebas la reemplazan para no depender de la red.
typedef ConstructorImagen = Widget Function(String ruta, Widget respaldo, BoxFit ajuste);

Widget imagenDeRed(String ruta, Widget respaldo, BoxFit ajuste) =>
    Image.network(ruta, fit: ajuste, errorBuilder: (context, error, traza) => respaldo);

/// La imagen del producto, o un ícono si no tiene o no carga.
class IlustracionProducto extends StatelessWidget {
  const IlustracionProducto({super.key, required this.producto, required this.imagen, this.ajuste = BoxFit.contain});

  final Producto producto;
  final ConstructorImagen imagen;

  /// Una foto llena su espacio (cover); un dibujo con fondo transparente cabe entero.
  final BoxFit ajuste;

  @override
  Widget build(BuildContext context) {
    final respaldo = LayoutBuilder(
      builder: (context, lados) => Icon(
        producto.esPizza ? Icons.local_pizza_outlined : Icons.local_drink_outlined,
        size: lados.biggest.shortestSide * 0.5,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
    final ruta = rutaDeImagen(producto);
    return ruta == null ? respaldo : imagen(ruta, respaldo, ajuste);
  }
}

/// − n +, con botones del tamaño de un dedo. [denso], un poco más chico, para las filas
/// de bebidas, que van varias en una misma línea.
class Contador extends StatelessWidget {
  const Contador({
    super.key,
    required this.valor,
    required this.minimo,
    required this.maximo,
    required this.alCambiar,
    this.clave = 'contador',
    this.denso = false,
  });

  final int valor;
  final int minimo;
  final int maximo;
  final ValueChanged<int> alCambiar;
  final String clave;
  final bool denso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tamano = denso ? 34.0 : 40.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          key: Key('$clave-menos'),
          tooltip: 'Uno menos',
          iconSize: denso ? 18 : 20,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: tamano, height: tamano),
          onPressed: valor > minimo ? () => alCambiar(valor - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: denso ? 30 : 40,
          child: Text(
            '$valor',
            key: Key('$clave-valor'),
            textAlign: TextAlign.center,
            style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton.outlined(
          key: Key('$clave-mas'),
          tooltip: 'Uno más',
          iconSize: denso ? 18 : 20,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: tamano, height: tamano),
          onPressed: valor < maximo ? () => alCambiar(valor + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Una de dos o más opciones excluyentes ("Para comer aquí", "Para llevar", "Entera"…):
/// grande para tocarla sin apuntar, y la elegida, en amarillo con borde rojo y una marca.
class BotonEleccion extends StatelessWidget {
  const BotonEleccion({
    super.key,
    required this.icono,
    required this.texto,
    required this.elegido,
    required this.alTocar,
    this.detalle,
  });

  final IconData icono;
  final String texto;
  final String? detalle;
  final bool elegido;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final fila = Row(
      children: [
        Icon(icono, color: elegido ? textoSobreAmarillo : rojoLadrillo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texto,
                style: tema.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: elegido ? textoSobreAmarillo : textoPrincipal,
                ),
              ),
              if (detalle != null)
                Text(
                  detalle!,
                  style: tema.textTheme.bodySmall?.copyWith(color: elegido ? textoSobreAmarillo : textoSecundario),
                ),
            ],
          ),
        ),
        if (elegido) const Icon(Icons.check_circle, color: rojoLadrillo),
      ],
    );
    return Semantics(
      button: true,
      selected: elegido,
      child: Material(
        color: elegido ? amarilloSuave : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: elegido ? rojoLadrillo : bordeSuave, width: elegido ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alTocar,
          // Centrado en su alto: si la de al lado ocupa dos renglones, esta no queda arriba.
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: fila),
          ),
        ),
      ),
    );
  }
}

/// Una sección del formulario: una tarjeta con su título ("1 · Cliente").
class Seccion extends StatelessWidget {
  const Seccion({super.key, required this.titulo, required this.hijos, this.accion, this.denso = false});

  final String titulo;

  /// Si alguno es Expanded, la sección llena el alto que le den.
  final List<Widget> hijos;

  /// Algo a la derecha del título, como un botón.
  final Widget? accion;

  /// Un poco más ajustada, para una ventana baja.
  final bool denso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: denso ? const EdgeInsets.fromLTRB(16, 10, 16, 12) : const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: rojoLadrillo),
                  ),
                ),
                ?accion,
              ],
            ),
            SizedBox(height: denso ? 8 : 12),
            ...hijos,
          ],
        ),
      ),
    );
  }
}
