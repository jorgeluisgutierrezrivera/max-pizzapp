import 'package:flutter/material.dart';

import '../api/cliente_api.dart';
import '../carta/producto.dart';
import '../tema.dart';

/// PATCH /api/v1/productos/:id/disponibilidad: devuelve el producto como quedó.
typedef MarcarDisponibilidad = Future<Producto> Function(Producto producto, bool disponible);

Future<Producto> sinMarcarDisponibilidad(Producto producto, bool disponible) =>
    Future.error(const ErrorApi(0, 'SIN_API', 'Esta pantalla no tiene cómo marcar productos.'));

/// PATCH /api/v1/productos/disponibilidad: agota o repone una categoría entera (D-70).
typedef MarcarCategoria = Future<void> Function(Categoria categoria, bool disponible);

Future<void> sinMarcarCategoria(Categoria categoria, bool disponible) =>
    Future.error(const ErrorApi(0, 'SIN_API', 'Esta pantalla no tiene cómo marcar productos.'));

/// Desde este ancho el panel se abre como ventana; más angosto, como hoja desde abajo.
const anchoPanelEnVentana = 600.0;

/// El botón *Carta* de la barra (D-68), igual en cocina y en recepción. Con texto desde
/// [anchoConTexto]; más angosto queda el ícono, con su descripción. Cada pantalla elige el
/// suyo: la barra de recepción comparte el lugar con las pestañas, y con texto se
/// desbordaba a 1366 px; la de cocina tiene lugar de sobra.
class BotonCarta extends StatelessWidget {
  const BotonCarta({super.key, required this.alTocar, this.anchoConTexto = 1700});
  final VoidCallback alTocar;
  final double anchoConTexto;

  @override
  Widget build(BuildContext context) {
    const icono = Icon(Icons.restaurant_menu);
    return MediaQuery.sizeOf(context).width >= anchoConTexto
        ? TextButton.icon(
            key: const Key('boton-carta'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: alTocar,
            icon: icono,
            label: const Text('Carta'),
          )
        : IconButton(
            key: const Key('boton-carta'),
            tooltip: 'Carta: marcar lo que se agotó',
            onPressed: alTocar,
            icon: icono,
          );
  }
}

/// Abre el panel *Carta* (RF-13, D-68): una ventana en pantallas anchas y una hoja desde
/// abajo en el celular. Recibe la carta que la pantalla ya tiene, la MISMA: así lo que se
/// marca aquí se ve en la venta sin esperar el aviso.
Future<void> mostrarPanelDeCarta(
  BuildContext context, {
  required Future<Carta> carta,
  required MarcarDisponibilidad marcar,
  MarcarCategoria? marcarCategoria,
}) {
  final tamano = MediaQuery.sizeOf(context);
  if (tamano.width >= anchoPanelEnVentana) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: tamano.height * 0.85),
          child: PanelDeCarta(carta: carta, marcar: marcar, marcarCategoria: marcarCategoria),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.9,
      child: PanelDeCarta(carta: carta, marcar: marcar, marcarCategoria: marcarCategoria),
    ),
  );
}

/// La carta con un interruptor por producto: *Disponible* o *Agotado*, escrito y no solo
/// con el color. El cambio se guarda al tocar, sin pedir confirmación, porque se deshace
/// con otro toque. Mientras se guarda, ese interruptor espera; si falla, queda como estaba
/// y el panel dice por qué. Si otra pantalla marca algo, el interruptor se mueve solo: la
/// carta avisa sus cambios.
///
/// Al lado del título de cada categoría, *Agotar todas* o *Reponer todas* (D-71): por ejemplo,
/// cuando se acaba la masa. Ese sí pide confirmación, porque cambia toda una parte de la carta.
class PanelDeCarta extends StatefulWidget {
  const PanelDeCarta({super.key, required this.carta, required this.marcar, this.marcarCategoria});

  final Future<Carta> carta;
  final MarcarDisponibilidad marcar;

  /// Sin ella, el panel no ofrece agotar una categoría entera.
  final MarcarCategoria? marcarCategoria;

  @override
  State<PanelDeCarta> createState() => _PanelDeCartaState();
}

class _PanelDeCartaState extends State<PanelDeCarta> {
  final _guardando = <int>{};
  final _guardandoCategoria = <Categoria>{};
  String? _error;

  /// Agotar (o reponer) toda la categoría, después de confirmarlo.
  Future<void> _marcarCategoria(Carta carta, Categoria categoria, List<Producto> productos) async {
    final agotar = productos.any((p) => p.disponible);
    final todas = todosLos(categoria);
    final verbo = agotar ? 'Agotar' : 'Reponer';
    final reponer = 'Reponer ${esFemenina(categoria) ? 'todas' : 'todos'}';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('confirmar-categoria'),
        title: Text('¿$verbo $todas?'),
        content: Text(
          agotar
              ? 'Dejan de ofrecerse en la venta, en todas las pantallas. Se vuelven a ofrecer con «$reponer».'
              : 'Vuelven a ofrecerse en la venta, en todas las pantallas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirmar-categoria-si'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('$verbo $todas'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    setState(() {
      _guardandoCategoria.add(categoria);
      _error = null;
    });
    try {
      await widget.marcarCategoria!(categoria, !agotar);
      carta.marcarCategoria(categoria, !agotar);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ErrorApi ? error.mensaje : 'No se pudo guardar. Revisa la conexión e intenta de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _guardandoCategoria.remove(categoria));
    }
  }

  Future<void> _marcar(Carta carta, Producto producto, bool disponible) async {
    setState(() {
      _guardando.add(producto.id);
      _error = null;
    });
    try {
      final guardado = await widget.marcar(producto, disponible);
      carta.marcarDisponibilidad(guardado.id, guardado.disponible);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ErrorApi
            ? error.mensaje
            : 'No se pudo guardar ${producto.nombre}. Revisa la conexión e intenta de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _guardando.remove(producto.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      key: const Key('panel-carta'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.restaurant_menu, color: rojoLadrillo),
                const SizedBox(width: 12),
                Expanded(child: Text('Carta', style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Lo que marques Agotado deja de ofrecerse en la venta al instante, en todas las pantallas.',
              style: TextStyle(color: textoSecundario),
            ),
          ),
          if (_error != null)
            Container(
              key: const Key('error-carta'),
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: rojoSuave, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: rojoLadrillo, fontWeight: FontWeight.w600)),
            ),
          const Divider(height: 1),
          Flexible(
            child: FutureBuilder<Carta>(
              future: widget.carta,
              builder: (context, estado) {
                if (estado.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (estado.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No se pudo cargar la carta. Cierra el panel e intenta de nuevo.'),
                  );
                }
                final carta = estado.requireData;
                return ListenableBuilder(
                  listenable: carta,
                  builder: (context, _) => ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      for (final (titulo, categoria, productos) in [
                        ('Pizzas', Categoria.pizza, carta.pizzas),
                        ('Bebidas', Categoria.bebida, carta.bebidas),
                        ('Extras', Categoria.extra, carta.extras),
                      ])
                        if (productos.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    titulo,
                                    style: tema.textTheme.titleSmall?.copyWith(color: textoSecundario),
                                  ),
                                ),
                                if (widget.marcarCategoria != null)
                                  TextButton(
                                    key: Key('categoria-${categoria.name}'),
                                    onPressed: _guardandoCategoria.contains(categoria)
                                        ? null
                                        : () => _marcarCategoria(carta, categoria, productos),
                                    child: Text(
                                      '${productos.any((p) => p.disponible) ? 'Agotar' : 'Reponer'} '
                                      '${esFemenina(categoria) ? 'todas' : 'todos'}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (final producto in productos)
                            _FilaDeProducto(
                              producto: producto,
                              guardando:
                                  _guardando.contains(producto.id) || _guardandoCategoria.contains(categoria),
                              alCambiar: (disponible) => _marcar(carta, producto, disponible),
                            ),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaDeProducto extends StatelessWidget {
  const _FilaDeProducto({required this.producto, required this.guardando, required this.alCambiar});

  final Producto producto;
  final bool guardando;
  final ValueChanged<bool> alCambiar;

  @override
  Widget build(BuildContext context) {
    final disponible = producto.disponible;
    return SwitchListTile(
      key: Key('disponible-${producto.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(producto.nombre),
      subtitle: Text(
        guardando ? 'Guardando…' : (disponible ? 'Disponible' : 'Agotado'),
        key: Key('estado-${producto.id}'),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: guardando ? textoSecundario : (disponible ? const Color(0xFF2E7D32) : rojoLadrillo),
        ),
      ),
      value: disponible,
      onChanged: guardando ? null : alCambiar,
    );
  }
}
