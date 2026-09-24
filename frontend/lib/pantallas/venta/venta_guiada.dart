import 'package:flutter/material.dart';

import '../../carta/venta.dart';
import 'comunes.dart';
import 'pasos.dart';
import 'resumen_venta.dart';

/// Desde este ancho la venta queda a la derecha del paso (tableta apaisada, escritorio); por
/// debajo, abajo, en una barra que se abre (celular, tableta vertical).
const anchoConPanelLateral = 900.0;

const _pasosDePizza = {Paso.tipo, Paso.sabor, Paso.primeraMitad, Paso.segundaMitad, Paso.extras};

/// Dónde está la vendedora: "Pizza 2 de 20 · Mitad y mitad · Segunda mitad".
String migaDePan(EstadoVenta e) {
  if (_pasosDePizza.contains(e.paso)) {
    final base = e.iguales
        ? (e.cantidadDelTramo == 1 ? 'Pizza' : '${e.cantidadDelTramo} pizzas iguales')
        : 'Pizza ${e.pizzaActual} de ${e.cantidadDelTramo}';
    final detalle = switch (e.paso) {
      Paso.sabor => ' · Un sabor',
      Paso.primeraMitad => ' · Mitad y mitad · Primera mitad',
      Paso.segundaMitad => ' · Mitad y mitad · Segunda mitad',
      Paso.extras => ' · Extras',
      _ => '',
    };
    return base + detalle;
  }
  return switch (e.paso) {
    Paso.cantidad => e.grupos.isEmpty ? 'Nueva venta' : 'Agregar pizzas',
    Paso.iguales => '${e.cantidadDelTramo} pizzas',
    Paso.bebidas => 'Bebidas',
    Paso.observacion => 'Observación',
    _ => 'Resumen',
  };
}

/// La venta guiada (D-30): una pregunta por pantalla, con el total siempre a la vista.
class VentaGuiada extends StatelessWidget {
  const VentaGuiada({
    super.key,
    required this.recorrido,
    required this.imagen,
    required this.alTerminar,
  });

  final RecorridoVenta recorrido;
  final ConstructorImagen imagen;
  final VoidCallback? alTerminar;

  Widget _paso() {
    final e = recorrido.estado;
    // La clave cambia cuando cambia el paso o la pizza que se arma: así cada paso nuevo
    // empieza limpio (la cantidad en 1, ningún extra marcado), pero escribir la
    // observación o sumar una bebida no lo reinicia.
    final clave = ValueKey('${e.paso.name}-${e.pizzaActual}-${e.grupos.length}-${e.cantidadDelTramo}');
    return KeyedSubtree(
      key: clave,
      child: switch (e.paso) {
        Paso.cantidad => PasoCantidad(recorrido: recorrido),
        Paso.iguales => PasoIguales(recorrido: recorrido),
        Paso.tipo => PasoTipo(recorrido: recorrido),
        Paso.sabor || Paso.primeraMitad || Paso.segundaMitad => PasoSabor(recorrido: recorrido, imagen: imagen),
        Paso.extras => PasoExtras(recorrido: recorrido),
        Paso.bebidas => PasoBebidas(recorrido: recorrido, imagen: imagen),
        Paso.observacion => PasoObservacion(recorrido: recorrido),
        Paso.resumen => PasoResumen(recorrido: recorrido, alTerminar: alTerminar),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorrido,
      builder: (context, _) => LayoutBuilder(builder: (context, lados) {
        final lateral = lados.maxWidth >= anchoConPanelLateral;
        final columna = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Encabezado(recorrido: recorrido),
            Expanded(child: _paso()),
            if (!lateral && recorrido.estado.paso != Paso.resumen) BarraVenta(recorrido: recorrido),
          ],
        );
        if (!lateral) return columna;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: columna),
            const VerticalDivider(width: 1),
            SizedBox(width: 340, child: PanelVenta(recorrido: recorrido)),
          ],
        );
      }),
    );
  }
}

/// Arriba de cada paso: Volver, dónde está, Cancelar venta y, si las pizzas son distintas,
/// cuántas faltan.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.recorrido});
  final RecorridoVenta recorrido;

  Future<void> _confirmarCancelar(BuildContext context) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar la venta?'),
        content: const Text('Se descarta todo lo que se armó.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir con la venta')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar venta'),
          ),
        ],
      ),
    );
    if (si == true) recorrido.cancelar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final e = recorrido.estado;
    final mostrarAvance = !e.iguales && e.cantidadDelTramo > 1 && _pasosDePizza.contains(e.paso);
    // En un celular angosto, Volver y Cancelar venta quedan como íconos (con su texto como
    // descripción): si no, la miga de pan no tiene lugar.
    final angosto = MediaQuery.sizeOf(context).width < 480;
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (recorrido.puedeVolver)
                  angosto
                      ? IconButton(tooltip: 'Volver', onPressed: recorrido.volver, icon: const Icon(Icons.arrow_back))
                      : TextButton.icon(
                          onPressed: recorrido.volver,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Volver'),
                        )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    migaDePan(e),
                    key: const Key('miga'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.titleSmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (recorrido.empezada)
                  angosto
                      ? IconButton(
                          tooltip: 'Cancelar venta',
                          color: tema.colorScheme.error,
                          onPressed: () => _confirmarCancelar(context),
                          icon: const Icon(Icons.close),
                        )
                      : TextButton(
                          style: TextButton.styleFrom(foregroundColor: tema.colorScheme.error),
                          onPressed: () => _confirmarCancelar(context),
                          child: const Text('Cancelar venta'),
                        ),
              ],
            ),
            if (mostrarAvance)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Faltan ${e.pendientes} de ${e.cantidadDelTramo}',
                        key: const Key('faltan'), style: tema.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (e.cantidadDelTramo - e.pendientes) / e.cantidadDelTramo,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
