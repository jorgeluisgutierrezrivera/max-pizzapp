import 'package:flutter/material.dart';

import '../../carta/producto.dart';
import '../../carta/venta.dart';
import '../../tema.dart';
import 'comunes.dart';

/// Lo que dice una línea de pizza debajo del título: sus extras.
String? _detalleDeExtras(PizzaElegida pizza) =>
    pizza.extras.isEmpty ? null : pizza.extras.map((e) => '+ ${e.nombre}').join(', ');

// --- 9. El resumen -------------------------------------------------------------------

/// El último paso: todo lo que lleva la venta, editable, y el botón que la termina.
///
/// El total es una VISTA PREVIA: el precio que se cobra lo calcula el servidor al
/// registrar el pedido (tarjeta 06), con la misma regla.
class PasoResumen extends StatelessWidget {
  const PasoResumen({super.key, required this.recorrido, required this.alTerminar});

  final RecorridoVenta recorrido;

  /// Nulo mientras el envío a cocina no exista (llega con la tarjeta 06).
  final VoidCallback? alTerminar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final estado = recorrido.estado;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Pregunta('Resumen de la venta'),
              if (estado.vacia)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('La venta está vacía: agrega una pizza o una bebida.',
                      style: TextStyle(color: colores.onSurfaceVariant)),
                ),
              for (final (i, grupo) in estado.grupos.indexed)
                _LineaResumen(
                  titulo: grupo.pizza.titulo,
                  detalle: _detalleDeExtras(grupo.pizza),
                  precioUnitario: grupo.pizza.precioUnitario,
                  cantidad: grupo.cantidad,
                  clave: 'grupo-$i',
                  minimo: 1,
                  alCambiar: (c) => recorrido.cambiarCantidadDeGrupo(i, c),
                  alQuitar: () => recorrido.cambiarCantidadDeGrupo(i, 0),
                ),
              for (final linea in estado.bebidas)
                _LineaResumen(
                  titulo: linea.bebida.nombre,
                  precioUnitario: linea.bebida.precio,
                  cantidad: linea.cantidad,
                  clave: 'bebida-${linea.bebida.id}',
                  minimo: 1,
                  alCambiar: (c) => recorrido.cambiarBebida(linea.bebida, c),
                  alQuitar: () => recorrido.cambiarBebida(linea.bebida, 0),
                ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(estado.observacion.isEmpty ? 'Sin observación para cocina' : estado.observacion),
                  trailing: TextButton(onPressed: recorrido.cambiarObservacion, child: const Text('Cambiar')),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: recorrido.agregarMasPizzas,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar pizzas'),
                  ),
                  OutlinedButton.icon(
                    onPressed: recorrido.cambiarBebidas,
                    icon: const Icon(Icons.local_drink_outlined),
                    label: const Text('Cambiar bebidas'),
                  ),
                ],
              ),
              const Divider(height: 40),
              Row(
                children: [
                  Expanded(child: Text('Total', style: tema.textTheme.headlineSmall)),
                  Text(formatoBs(estado.total),
                      key: const Key('total-resumen'),
                      style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: estiloBotonRojo(),
                onPressed: estado.vacia ? null : alTerminar,
                icon: const Icon(Icons.send),
                label: const Text('Terminar venta'),
              ),
              if (alTerminar == null && !estado.vacia)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('El envío a cocina todavía no está disponible.',
                      textAlign: TextAlign.center, style: TextStyle(color: colores.onSurfaceVariant)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineaResumen extends StatelessWidget {
  const _LineaResumen({
    required this.titulo,
    required this.precioUnitario,
    required this.cantidad,
    required this.clave,
    required this.minimo,
    required this.alCambiar,
    required this.alQuitar,
    this.detalle,
  });

  final String titulo;
  final String? detalle;
  final int precioUnitario;
  final int cantidad;
  final String clave;
  final int minimo;
  final ValueChanged<int> alCambiar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (detalle != null)
                      Text(detalle!, style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant)),
                    Text('${formatoBs(precioUnitario)} c/u · ${formatoBs(precioUnitario * cantidad)}',
                        style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Contador(
                clave: clave,
                valor: cantidad,
                minimo: minimo,
                maximo: RecorridoVenta.maximoPorLinea,
                alCambiar: alCambiar,
              ),
              IconButton(tooltip: 'Quitar', onPressed: alQuitar, icon: const Icon(Icons.delete_outline)),
            ],
          ),
        ),
      ),
    );
  }
}

// --- La venta a la vista -----------------------------------------------------------

/// Lo que lleva la venta hasta ahora, y el total. A la derecha en pantallas anchas.
class PanelVenta extends StatelessWidget {
  const PanelVenta({super.key, required this.recorrido, this.desplazamiento});

  final RecorridoVenta recorrido;
  final ScrollController? desplazamiento;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final estado = recorrido.estado;
    return ColoredBox(
      color: Colors.white,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Venta', style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: ListView(
            controller: desplazamiento,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (estado.vacia)
                Text('Todavía no hay nada en la venta.', style: TextStyle(color: colores.onSurfaceVariant)),
              for (final g in estado.grupos)
                _LineaPanel(texto: '${g.cantidad} × ${g.pizza.titulo}', detalle: _detalleDeExtras(g.pizza), monto: g.subtotal),
              for (final b in estado.bebidas)
                _LineaPanel(texto: '${b.cantidad} × ${b.bebida.nombre}', monto: b.subtotal),
              if (estado.observacion.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Observación: ${estado.observacion}',
                      style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text('Total', style: tema.textTheme.titleLarge)),
              EtiquetaPrecio(formatoBs(estado.total), grande: true, key: const Key('total-panel')),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

class _LineaPanel extends StatelessWidget {
  const _LineaPanel({required this.texto, required this.monto, this.detalle});
  final String texto;
  final String? detalle;
  final int monto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: tema.textTheme.bodyMedium),
                if (detalle != null)
                  Text(detalle!, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatoBs(monto), style: tema.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// En pantallas angostas: el resumen de la venta abajo, que se abre para verla completa.
class BarraVenta extends StatelessWidget {
  const BarraVenta({super.key, required this.recorrido});
  final RecorridoVenta recorrido;

  String _resumen(EstadoVenta e) {
    if (e.vacia) return 'Venta vacía';
    final partes = [
      if (e.unidadesDePizza > 0) '${e.unidadesDePizza} ${e.unidadesDePizza == 1 ? 'pizza' : 'pizzas'}',
      if (e.unidadesDeBebida > 0) '${e.unidadesDeBebida} ${e.unidadesDeBebida == 1 ? 'bebida' : 'bebidas'}',
    ];
    return '${partes.join(' · ')} · ${formatoBs(e.total)}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // Negra como la barra de arriba: la venta queda enmarcada con los colores de la marca.
    return Material(
      color: negroMarca,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(_resumen(recorrido.estado),
                    key: const Key('resumen-barra'),
                    style: tema.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: amarilloMarca),
                onPressed: recorrido.estado.vacia
                    ? null
                    : () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (context) => DraggableScrollableSheet(
                            expand: false,
                            initialChildSize: 0.6,
                            builder: (context, desplazamiento) =>
                                PanelVenta(recorrido: recorrido, desplazamiento: desplazamiento),
                          ),
                        ),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Ver venta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
