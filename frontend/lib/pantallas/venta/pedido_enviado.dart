import 'package:flutter/material.dart';

import '../../carta/producto.dart';
import '../../tema.dart';

/// Después de "Terminar venta": el pedido quedó guardado. Dice su número, a nombre de quién
/// va y cuánto se cobra, y deja lista una venta nueva con un toque.
///
/// El número y el total son los del SERVIDOR, no la vista previa: son los que quedaron
/// guardados.
class PedidoEnviado extends StatelessWidget {
  const PedidoEnviado({super.key, required this.pedido, required this.alNuevaVenta});

  /// El pedido como lo devuelve POST /api/v1/pedidos.
  final Map<String, dynamic> pedido;
  final VoidCallback alNuevaVenta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final numero = pedido['id'];
    final cliente = (pedido['cliente'] as Map<String, dynamic>)['nombre'] as String;
    final paraLlevar = pedido['paraLlevar'] == true;
    // Un pedido de solo bebidas nace listo: no pasa por cocina (D-32).
    final soloBebidas = pedido['estado'] == 'listo';
    final total = ((pedido['total'] as num) * 100).round();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: rojoLadrillo, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 52, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                soloBebidas ? 'Pedido #$numero listo para entregar' : 'Pedido #$numero enviado a cocina',
                key: const Key('pedido-enviado'),
                textAlign: TextAlign.center,
                style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '$cliente · ${paraLlevar ? 'Para llevar' : 'Para comer aquí'}',
                textAlign: TextAlign.center,
                style: tema.textTheme.titleMedium,
              ),
              if (soloBebidas) ...[
                const SizedBox(height: 4),
                Text('Es solo de bebidas: no pasa por cocina.',
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 16),
              Center(child: EtiquetaPrecio(formatoBs(total), grande: true, key: const Key('total-enviado'))),
              const SizedBox(height: 32),
              FilledButton.icon(
                autofocus: true,
                onPressed: alNuevaVenta,
                icon: const Icon(Icons.add),
                label: const Text('Nueva venta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
