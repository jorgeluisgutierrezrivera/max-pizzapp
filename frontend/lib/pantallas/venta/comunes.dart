import 'package:flutter/material.dart';

import '../../carta/producto.dart';
import '../../tema.dart';

/// Cómo se dibuja una imagen a partir de su ruta. En la app es una imagen de red relativa a
/// la página; las pruebas la reemplazan para no depender de la red.
typedef ConstructorImagen = Widget Function(String ruta, Widget respaldo, BoxFit ajuste);

Widget imagenDeRed(String ruta, Widget respaldo, BoxFit ajuste) => Image.network(
      ruta,
      fit: ajuste,
      errorBuilder: (context, error, traza) => respaldo,
    );

/// La imagen del producto, o un ícono si no tiene o no carga.
class IlustracionProducto extends StatelessWidget {
  const IlustracionProducto({
    super.key,
    required this.producto,
    required this.imagen,
    this.ajuste = BoxFit.contain,
  });

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

/// Una de las opciones de una pregunta ("Un solo sabor", "Mitad y mitad"…): grande, para
/// tocarla con el dedo en el mostrador sin apuntar.
class OpcionGrande extends StatelessWidget {
  const OpcionGrande({
    super.key,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.alTocar,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: bordeSuave),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: negroMarca, shape: BoxShape.circle),
                child: Icon(icono, size: 28, color: amarilloMarca),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(detalle, style: tema.textTheme.bodyMedium?.copyWith(color: colores.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colores.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// − n +, con botones grandes. El número se muestra; los límites se respetan.
class Contador extends StatelessWidget {
  const Contador({
    super.key,
    required this.valor,
    required this.minimo,
    required this.maximo,
    required this.alCambiar,
    this.clave = 'contador',
    this.grande = false,
  });

  final int valor;
  final int minimo;
  final int maximo;
  final ValueChanged<int> alCambiar;
  final String clave;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tamano = grande ? 56.0 : 40.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          key: Key('$clave-menos'),
          tooltip: 'Uno menos',
          iconSize: grande ? 28 : 20,
          constraints: BoxConstraints.tightFor(width: tamano, height: tamano),
          onPressed: valor > minimo ? () => alCambiar(valor - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: grande ? 96 : 40,
          child: Text(
            '$valor',
            key: Key('$clave-valor'),
            textAlign: TextAlign.center,
            style: (grande ? tema.textTheme.displaySmall : tema.textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton.outlined(
          key: Key('$clave-mas'),
          tooltip: 'Uno más',
          iconSize: grande ? 28 : 20,
          constraints: BoxConstraints.tightFor(width: tamano, height: tamano),
          onPressed: valor < maximo ? () => alCambiar(valor + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// El título de un paso: la pregunta, grande, y una aclaración opcional debajo.
class Pregunta extends StatelessWidget {
  const Pregunta(this.texto, {super.key, this.aclaracion});

  final String texto;
  final String? aclaracion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (aclaracion != null) ...[
            const SizedBox(height: 4),
            Text(aclaracion!, style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
