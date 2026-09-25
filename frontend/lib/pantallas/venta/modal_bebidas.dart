import 'package:flutter/material.dart';

import '../../carta/producto.dart';
import '../../carta/venta.dart';
import '../../tema.dart';
import 'comunes.dart';

/// Guarda la venta directa y devuelve lo que guardó el servidor.
typedef Cobrar = Future<Map<String, dynamic>> Function(Map<String, dynamic> venta);

/// Abre la venta directa de bebidas (D-38): las bebidas, el total y *Cobrar*. Sin nombre ni
/// preguntas; el servidor la guarda entregada. Devuelve la venta guardada, o nulo si se cerró.
Future<Map<String, dynamic>?> mostrarVentaDeBebidas(
  BuildContext context, {
  required Carta carta,
  required ConstructorImagen imagen,
  required Cobrar cobrar,
  required String Function(Object error) explicarError,
}) {
  ModalBebidas modal({required bool ajustado}) =>
      ModalBebidas(carta: carta, imagen: imagen, cobrar: cobrar, explicarError: explicarError, ajustado: ajustado);
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => MediaQuery.sizeOf(context).width < 560
        ? Dialog.fullscreen(child: modal(ajustado: false))
        : Dialog(
            insetPadding: const EdgeInsets.all(24),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
              child: modal(ajustado: true),
            ),
          ),
  );
}

class ModalBebidas extends StatefulWidget {
  const ModalBebidas({
    super.key,
    required this.carta,
    required this.imagen,
    required this.cobrar,
    required this.explicarError,
    this.ajustado = false,
  });

  final Carta carta;
  final ConstructorImagen imagen;
  final Cobrar cobrar;
  final String Function(Object error) explicarError;

  /// En un diálogo: tan alto como su contenido. A pantalla completa: todo el alto.
  final bool ajustado;

  @override
  State<ModalBebidas> createState() => _ModalBebidasState();
}

class _ModalBebidasState extends State<ModalBebidas> {
  late final _venta = VentaDeBebidas(widget.carta);
  bool _cobrando = false;
  String? _error;

  @override
  void dispose() {
    _venta.dispose();
    super.dispose();
  }

  Future<void> _cobrar() async {
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final guardada = await widget.cobrar(_venta.aVentaDirecta());
      if (!mounted) return;
      Navigator.of(context).pop(guardada);
    } catch (error) {
      if (!mounted) return;
      // No se guardó: las bebidas quedan elegidas, para volver a intentarlo.
      setState(() {
        _cobrando = false;
        _error = widget.explicarError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      key: const Key('modal-bebidas'),
      color: cremaFondo,
      child: ListenableBuilder(
        listenable: _venta,
        builder: (context, _) => Column(
          mainAxisSize: widget.ajustado ? MainAxisSize.min : MainAxisSize.max,
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
                        Text('Vender bebidas', style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          'Sin nombre: se entrega en el momento y no pasa por cocina.',
                          style: tema.textTheme.bodySmall?.copyWith(color: textoSecundario),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('cerrar-bebidas'),
                    tooltip: 'Cerrar sin vender',
                    onPressed: _cobrando ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              fit: widget.ajustado ? FlexFit.loose : FlexFit.tight,
              child: ListView(
                shrinkWrap: widget.ajustado,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final bebida in widget.carta.bebidas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilaBebida(
                        bebida: bebida,
                        imagen: widget.imagen,
                        cantidad: _venta.cantidadDe(bebida),
                        clave: 'directa-${bebida.id}',
                        alCambiar: _cobrando ? null : (v) => _venta.cambiar(bebida, v),
                      ),
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
                          key: const Key('error-bebidas'),
                          style: TextStyle(color: tema.colorScheme.error),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('cobrar-bebidas'),
                      style: estiloBotonRojo(),
                      onPressed: _venta.vacia || _cobrando ? null : _cobrar,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(
                        _cobrando
                            ? 'Registrando…'
                            : _venta.vacia
                            ? 'Elige al menos una bebida'
                            : 'Cobrar · ${formatoBs(_venta.total)}',
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

/// Una bebida con su foto, su precio y − n +. La usan el formulario y la venta directa.
class FilaBebida extends StatelessWidget {
  const FilaBebida({
    super.key,
    required this.bebida,
    required this.imagen,
    required this.cantidad,
    required this.clave,
    required this.alCambiar,
    this.denso = false,
  });

  final Producto bebida;
  final ConstructorImagen imagen;
  final int cantidad;
  final String clave;
  final ValueChanged<int>? alCambiar;

  /// Más baja, para que varias quepan en una línea del formulario.
  final bool denso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final elegida = cantidad > 0;
    return Opacity(
      opacity: bebida.disponible || elegida ? 1 : 0.4,
      child: Container(
        padding: EdgeInsets.fromLTRB(10, denso ? 4 : 8, 6, denso ? 4 : 8),
        decoration: BoxDecoration(
          color: elegida ? amarilloSuave.withValues(alpha: 0.45) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: elegida ? rojoLadrillo : bordeSuave),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: denso ? 32 : 40,
              child: IlustracionProducto(producto: bebida, imagen: imagen),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bebida.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: denso ? tema.textTheme.bodyMedium?.copyWith(height: 1.15) : tema.textTheme.titleSmall,
                  ),
                  if (!denso) const SizedBox(height: 2),
                  if (bebida.disponible)
                    Text(
                      formatoBs(bebida.precio),
                      style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: textoSecundario),
                    )
                  else
                    Text('Agotada', style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.error)),
                ],
              ),
            ),
            Contador(
              clave: clave,
              valor: cantidad,
              minimo: 0,
              maximo: bebida.disponible ? 99 : cantidad,
              denso: denso,
              alCambiar: alCambiar ?? (_) {},
            ),
          ],
        ),
      ),
    );
  }
}
