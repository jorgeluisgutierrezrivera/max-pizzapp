import 'package:flutter/material.dart';

import '../../api/cliente_api.dart';
import '../../carta/producto.dart';
import '../../carta/venta.dart';
import '../../pedidos/pedido.dart';
import '../../tema.dart';
import 'comunes.dart';
import 'modal_bebidas.dart';
import 'modal_pizza.dart';

/// Abre *Agregar* sobre un pedido ya enviado (D-37): pizzas mientras cocina no lo terminó, y
/// bebidas hasta que se entregue. Devuelve el pedido como quedó, o nulo si se cerró.
Future<Pedido?> mostrarAgregado(
  BuildContext context, {
  required Pedido pedido,
  required Carta carta,
  required ConstructorImagen imagen,
  required Future<Pedido> Function(Map<String, dynamic> cuerpo) agregar,
}) {
  final modal = ModalAgregar(pedido: pedido, carta: carta, imagen: imagen, agregar: agregar);
  return showDialog<Pedido>(
    context: context,
    builder: (context) => MediaQuery.sizeOf(context).width < 560
        ? Dialog.fullscreen(child: modal)
        : Dialog(
            insetPadding: const EdgeInsets.all(24),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: modal),
          ),
  );
}

class ModalAgregar extends StatefulWidget {
  const ModalAgregar({
    super.key,
    required this.pedido,
    required this.carta,
    required this.imagen,
    required this.agregar,
  });

  final Pedido pedido;
  final Carta carta;
  final ConstructorImagen imagen;
  final Future<Pedido> Function(Map<String, dynamic> cuerpo) agregar;

  @override
  State<ModalAgregar> createState() => _ModalAgregarState();
}

class _ModalAgregarState extends State<ModalAgregar> {
  late final _agregado = AgregadoAPedido(widget.carta, permitePizzas: widget.pedido.estado.enCocina);
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _agregado.dispose();
    super.dispose();
  }

  Future<void> _agregarPizza() async {
    final r = await mostrarModalPizza(context, carta: widget.carta, imagen: widget.imagen);
    if (r != null && !r.quitada) _agregado.agregarPizza(r.pizza!, r.cantidad);
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final quedo = await widget.agregar(_agregado.aCuerpo());
      if (!mounted) return;
      Navigator.of(context).pop(quedo);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = _explicar(error);
      });
    }
  }

  /// Los casos que la app sabe explicar; el resto, el mensaje del servidor.
  String _explicar(Object error) {
    if (error is! ErrorApi) return 'No se pudo agregar. Intenta de nuevo.';
    return switch (error.codigo) {
      'AGREGADO_NO_PERMITIDO' when error.datos['estadoActual'] == 'listo' =>
        'Mientras tanto, cocina lo marcó listo: las pizzas nuevas van en otro pedido. Las bebidas sí se pueden agregar.',
      'AGREGADO_NO_PERMITIDO' => 'El pedido ya se entregó o se canceló: haz una venta nueva.',
      'SIN_CONEXION' => 'No hay conexión con el servidor. Lo elegido sigue aquí; vuelve a intentarlo.',
      _ => error.mensaje,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final pedido = widget.pedido;
    return Material(
      key: const Key('modal-agregar'),
      color: cremaFondo,
      child: ListenableBuilder(
        listenable: _agregado,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agregar al ${pedido.etiqueta}',
                          style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${pedido.cliente} · ${pedido.estado.etiqueta.toLowerCase()}',
                          style: tema.textTheme.bodySmall?.copyWith(color: textoSecundario),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('cerrar-agregar'),
                    tooltip: 'Cerrar sin agregar',
                    onPressed: _enviando ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Seccion(
                    titulo: 'Pizzas',
                    hijos: [
                      if (!_agregado.permitePizzas)
                        const Text(
                          'El pedido ya está listo: las pizzas nuevas van en otro pedido.',
                          key: Key('sin-pizzas'),
                          style: TextStyle(color: textoSecundario),
                        )
                      else ...[
                        for (final (i, g) in _agregado.grupos.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Contador(
                                  clave: 'agregada-$i',
                                  valor: g.cantidad,
                                  minimo: 0,
                                  maximo: maximoPorLinea,
                                  alCambiar: (n) => _agregado.cambiarCantidadDeGrupo(i, n),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    [g.pizza.titulo, for (final e in g.pizza.extras) '+ ${e.nombre}'].join('  '),
                                    style: tema.textTheme.titleSmall,
                                  ),
                                ),
                                EtiquetaPrecio(formatoBs(g.subtotal)),
                              ],
                            ),
                          ),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            key: const Key('agregar-pizza-al-pedido'),
                            onPressed: _enviando ? null : _agregarPizza,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar pizza'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Seccion(
                    titulo: 'Bebidas',
                    hijos: [
                      for (final bebida in widget.carta.bebidas)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FilaBebida(
                            bebida: bebida,
                            imagen: widget.imagen,
                            cantidad: _agregado.cantidadDeBebida(bebida),
                            clave: 'agregar-bebida-${bebida.id}',
                            alCambiar: _enviando ? null : (v) => _agregado.cambiarBebida(bebida, v),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: bordeSuave)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error!,
                          key: const Key('error-agregar'),
                          style: TextStyle(color: tema.colorScheme.error),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('confirmar-agregado'),
                      style: estiloBotonRojo(),
                      onPressed: _agregado.vacio || _enviando ? null : _enviar,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: Text(
                        _enviando
                            ? 'Agregando…'
                            : _agregado.vacio
                            ? 'Elige qué agregar'
                            : 'Agregar al pedido · ${formatoBs(_agregado.total)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
