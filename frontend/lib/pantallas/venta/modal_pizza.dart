import 'package:flutter/material.dart';

import '../../carta/producto.dart';
import '../../carta/venta.dart';
import '../../tema.dart';
import 'comunes.dart';

/// Lo que devuelve el modal: la pizza y cuántas, o que se quitó la que se estaba corrigiendo.
class PizzaDelModal {
  const PizzaDelModal(this.pizza, this.cantidad);
  const PizzaDelModal.quitada() : pizza = null, cantidad = 0;

  final PizzaElegida? pizza;
  final int cantidad;
  bool get quitada => pizza == null;
}

/// Por debajo de este ancho (el celular), el modal ocupa toda la pantalla.
const anchoModalCompleto = 700.0;

/// Abre el modal para armar una pizza (D-36): entera o mitad y mitad, los sabores, los
/// extras y cuántas. Con [desde], corrige la pizza de una línea.
Future<PizzaDelModal?> mostrarModalPizza(
  BuildContext context, {
  required Carta carta,
  required ConstructorImagen imagen,
  PizzaElegida? desde,
  int cantidad = 1,
}) {
  final modal = ModalPizza(carta: carta, imagen: imagen, desde: desde, cantidad: cantidad);
  return showDialog<PizzaDelModal>(
    context: context,
    builder: (context) => MediaQuery.sizeOf(context).width < anchoModalCompleto
        ? Dialog.fullscreen(child: modal)
        : Dialog(
            insetPadding: const EdgeInsets.all(24),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 900), child: modal),
          ),
  );
}

class ModalPizza extends StatefulWidget {
  const ModalPizza({super.key, required this.carta, required this.imagen, this.desde, this.cantidad = 1});

  final Carta carta;
  final ConstructorImagen imagen;
  final PizzaElegida? desde;
  final int cantidad;

  @override
  State<ModalPizza> createState() => _ModalPizzaState();
}

class _ModalPizzaState extends State<ModalPizza> {
  late final _armado = ArmadoDePizza(widget.carta, desde: widget.desde, cantidad: widget.cantidad);

  bool get _corrigiendo => widget.desde != null;

  @override
  void dispose() {
    _armado.dispose();
    super.dispose();
  }

  void _listo() {
    final pizza = _armado.pizza;
    if (pizza == null) return;
    Navigator.of(context).pop(PizzaDelModal(pizza, _armado.cantidad));
  }

  String _textoDelBoton() {
    final falta = _armado.falta;
    if (falta != null) return falta;
    final cuantas = _armado.cantidad == 1 ? '1 pizza' : '${_armado.cantidad} pizzas';
    return '${_corrigiendo ? 'Guardar' : 'Agregar'} $cuantas · ${formatoBs(_armado.subtotal!)}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      key: const Key('modal-pizza'),
      color: cremaFondo,
      child: ListenableBuilder(
        listenable: _armado,
        builder: (context, _) => LayoutBuilder(
          builder: (context, lados) {
            final pie = _Pie(
              armado: _armado,
              texto: _textoDelBoton(),
              alListo: _armado.falta == null ? _listo : null,
              alQuitar: _corrigiendo ? () => Navigator.of(context).pop(const PizzaDelModal.quitada()) : null,
            );
            final sabores = _Sabores(armado: _armado, imagen: widget.imagen);
            // En la computadora: los sabores a la izquierda y, a la derecha, fijo, todo lo
            // demás (el tipo, los extras, la cantidad y el botón). En el celular: el tipo
            // arriba, los sabores al medio y los extras en el pie. En los dos casos, los
            // extras están siempre a la vista: no hay que bajar hasta después de las pizzas.
            final cuerpo = lados.maxWidth >= anchoModalCompleto
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: sabores),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 320,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _Tipo(armado: _armado, apilado: true),
                                    const SizedBox(height: 24),
                                    _Extras(armado: _armado, enFila: false),
                                  ],
                                ),
                              ),
                            ),
                            pie,
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _Tipo(armado: _armado, apilado: false),
                      ),
                      Expanded(child: sabores),
                      const Divider(height: 1),
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _Extras(armado: _armado, enFila: true),
                      ),
                      pie,
                    ],
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // El encabezado, fijo: qué se hace y cómo salir sin agregar nada.
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _corrigiendo ? 'Cambiar pizza' : 'Agregar pizza',
                          style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        key: const Key('cerrar-modal'),
                        tooltip: 'Cerrar sin cambios',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: cuerpo),
              ],
            );
          },
        ),
      ),
    );
  }
}

Widget _titulo(BuildContext context, String texto, [String? aclaracion]) {
  final tema = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(texto, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (aclaracion != null) Text(aclaracion, style: tema.textTheme.bodySmall?.copyWith(color: textoSecundario)),
      ],
    ),
  );
}

/// ¿Entera o mitad y mitad? Lado a lado, o una sobre otra en el panel de la derecha.
class _Tipo extends StatelessWidget {
  const _Tipo({required this.armado, required this.apilado});
  final ArmadoDePizza armado;
  final bool apilado;

  @override
  Widget build(BuildContext context) {
    final entera = BotonEleccion(
      key: const Key('tipo-entera'),
      icono: Icons.circle_outlined,
      texto: 'Entera',
      detalle: 'Un solo sabor',
      elegido: !armado.mitades,
      alTocar: () => armado.elegirMitades(false),
    );
    final mitades = BotonEleccion(
      key: const Key('tipo-mitades'),
      icono: Icons.contrast,
      texto: 'Mitad y mitad',
      detalle: 'Dos sabores',
      elegido: armado.mitades,
      alTocar: () => armado.elegirMitades(true),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo(context, '¿Entera o mitad y mitad?'),
        if (apilado) ...[
          entera,
          const SizedBox(height: 10),
          mitades,
        ] else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: entera),
                const SizedBox(width: 12),
                Expanded(child: mitades),
              ],
            ),
          ),
      ],
    );
  }
}

/// Los sabores con su foto, en una grilla que se desplaza por su cuenta.
class _Sabores extends StatelessWidget {
  const _Sabores({required this.armado, required this.imagen});
  final ArmadoDePizza armado;
  final ConstructorImagen imagen;

  @override
  Widget build(BuildContext context) {
    final pizzas = armado.carta.pizzas;
    return CustomScrollView(
      key: const Key('grilla-sabores'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (armado.mitades) ...[
                  _titulo(
                    context,
                    'Sabores',
                    'Toca dos: la primera y la segunda mitad. Cada mitad vale la mitad de su pizza.',
                  ),
                  _Mitades(armado: armado),
                  const SizedBox(height: 12),
                ] else
                  _titulo(context, 'Sabor'),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
            itemCount: pizzas.length,
            itemBuilder: (context, i) {
              final sabor = pizzas[i];
              return TarjetaSabor(
                key: Key('sabor-${sabor.nombre}'),
                sabor: sabor,
                precio: armado.mitades ? sabor.precioDeMitad : sabor.precio,
                etiquetaPrecio: armado.mitades ? 'la mitad' : null,
                imagen: imagen,
                lugar: armado.lugarDe(sabor),
                mostrarLugar: armado.mitades,
                alTocar: sabor.disponible ? () => armado.tocarSabor(sabor) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Los extras. En el panel de la derecha, todos a la vista; en el celular, en una fila que
/// se desliza de lado, en el pie.
class _Extras extends StatelessWidget {
  const _Extras({required this.armado, required this.enFila});
  final ArmadoDePizza armado;
  final bool enFila;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final extras = armado.carta.extras;
    if (extras.isEmpty) return const SizedBox.shrink();
    final chips = [
      for (final extra in extras)
        FilterChip(
          key: Key('extra-${extra.nombre}'),
          label: Text(extra.disponible ? '${extra.nombre} · +${formatoBs(extra.precio)}' : '${extra.nombre} · agotado'),
          labelStyle: tema.textTheme.titleSmall,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          selected: armado.extras.contains(extra),
          onSelected: extra.disponible || armado.extras.contains(extra) ? (_) => armado.alternarExtra(extra) : null,
        ),
    ];
    if (enFila) {
      return Row(
        children: [
          Text('Extras', style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('fila-extras'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, chip) in chips.indexed) ...[if (i > 0) const SizedBox(width: 8), chip],
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titulo(context, 'Extras', 'Se puede elegir más de uno, o ninguno.'),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }
}

/// Cuál es cada mitad, a la vista mientras se eligen.
class _Mitades extends StatelessWidget {
  const _Mitades({required this.armado});
  final ArmadoDePizza armado;

  @override
  Widget build(BuildContext context) {
    Widget mitad(String cual, Producto? sabor, String clave) => Expanded(
      child: Container(
        key: Key(clave),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sabor == null ? Colors.white : amarilloSuave,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sabor == null ? bordeSuave : rojoLadrillo),
        ),
        child: Text(
          '$cual: ${sabor?.nombre ?? 'elige'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700, color: sabor == null ? textoSecundario : textoSobreAmarillo),
        ),
      ),
    );
    return Row(
      children: [
        mitad('Mitad 1', armado.primera, 'mitad-1'),
        const SizedBox(width: 10),
        mitad('Mitad 2', armado.segunda, 'mitad-2'),
      ],
    );
  }
}

/// El pie, fijo: la pizza que se está armando, cuántas y el botón con el único precio.
class _Pie extends StatelessWidget {
  const _Pie({required this.armado, required this.texto, required this.alListo, this.alQuitar});

  final ArmadoDePizza armado;
  final String texto;
  final VoidCallback? alListo;
  final VoidCallback? alQuitar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final pizza = armado.pizza;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pizza != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  [pizza.titulo, for (final e in pizza.extras) '+ ${e.nombre}'].join('  '),
                  key: const Key('pizza-armada'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Cantidad', style: tema.textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Contador(
                      clave: 'cantidad-pizza',
                      valor: armado.cantidad,
                      minimo: 1,
                      maximo: armado.cantidad > ArmadoDePizza.maximoPorVez
                          ? armado.cantidad
                          : ArmadoDePizza.maximoPorVez,
                      alCambiar: armado.cambiarCantidad,
                    ),
                  ],
                ),
                if (alQuitar != null)
                  TextButton.icon(
                    key: const Key('quitar-pizza'),
                    onPressed: alQuitar,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Quitar esta pizza'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('listo-pizza'),
              style: estiloBotonRojo(),
              onPressed: alListo,
              icon: Icon(alListo == null ? Icons.touch_app_outlined : Icons.check),
              label: Text(texto),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un sabor de la carta, grande para tocarlo. Un agotado se ve atenuado y no responde. El
/// elegido lleva borde rojo y, si es mitad y mitad, el número de su mitad.
class TarjetaSabor extends StatelessWidget {
  const TarjetaSabor({
    super.key,
    required this.sabor,
    required this.precio,
    required this.imagen,
    required this.alTocar,
    this.etiquetaPrecio,
    this.lugar,
    this.mostrarLugar = false,
  });

  final Producto sabor;
  final int precio;
  final String? etiquetaPrecio;
  final ConstructorImagen imagen;
  final VoidCallback? alTocar;

  /// 1 o 2 si está elegido; nulo si no.
  final int? lugar;

  /// Si la marca dice la mitad (1 o 2) o solo que está elegido.
  final bool mostrarLugar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final agotado = !sabor.disponible;
    final elegido = lugar != null;
    return Semantics(
      button: true,
      enabled: !agotado,
      selected: elegido,
      label:
          '${sabor.nombre}. ${agotado ? 'Agotada' : formatoBs(precio)}'
          '${elegido && mostrarLugar ? '. Mitad $lugar' : ''}',
      excludeSemantics: true,
      child: Opacity(
        opacity: agotado ? 0.4 : 1,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: elegido ? rojoLadrillo : bordeSuave, width: elegido ? 3 : 1),
          ),
          child: InkWell(
            onTap: alTocar,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // La foto de borde a borde: es lo primero que se reconoce.
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: colores.surfaceContainer,
                        child: IlustracionProducto(producto: sabor, imagen: imagen, ajuste: BoxFit.cover),
                      ),
                      if (elegido)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: rojoLadrillo,
                            child: mostrarLugar
                                ? Text(
                                    '$lugar',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                  )
                                : const Icon(Icons.check, color: Colors.white, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sabor.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 32,
                        child: Text(
                          sabor.descripcion ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant, height: 1.2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (agotado)
                        Text(
                          'Agotada',
                          style: tema.textTheme.titleSmall?.copyWith(color: colores.error, fontWeight: FontWeight.w700),
                        )
                      else
                        Row(
                          children: [
                            // En una tarjeta angosta, la etiqueta se achica antes que desbordar.
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: EtiquetaPrecio(formatoBs(precio)),
                              ),
                            ),
                            if (etiquetaPrecio != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  etiquetaPrecio ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
