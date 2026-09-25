import 'package:flutter/material.dart';

import '../../carta/producto.dart';
import '../../tema.dart';

/// Cuánto queda a la vista el aviso de la venta guardada antes de cerrarse solo.
const duracionDelAviso = Duration(seconds: 6);

/// Después de confirmar: la venta quedó guardada. Un aviso flotante dice el número que se
/// canta, a nombre de quién va y cuánto se cobra (D-35, D-36), y se cierra solo a los pocos
/// segundos, o antes con la X. No ocupa lugar en el formulario, que ya quedó limpio para el
/// siguiente cliente.
///
/// El número y el total son los del SERVIDOR, no la vista previa: son los que quedaron
/// guardados.
SnackBar avisoDeVentaGuardada(Map<String, dynamic> pedido, {required bool ancha}) {
  final total = formatoBs(((pedido['total'] as num) * 100).round());
  final cliente = pedido['cliente'] as Map<String, dynamic>?;

  // La venta directa de bebidas no lleva nombre ni número: se entregó en el momento (D-38).
  final String titulo;
  final String detalle;
  if (cliente == null) {
    titulo = 'Venta de bebidas registrada · $total';
    detalle = 'Entregada en el mostrador.';
  } else {
    final numero = pedido['numero'] ?? pedido['id'];
    titulo = 'Pedido $numero de ${cliente['nombre']} enviado a cocina';
    detalle = '${pedido['paraLlevar'] == true ? 'Para llevar' : 'Para comer aquí'} · $total';
  }

  return SnackBar(
    key: const Key('aviso-enviado'),
    behavior: SnackBarBehavior.floating,
    width: ancha ? 520 : null,
    duration: duracionDelAviso,
    backgroundColor: amarilloSuave,
    showCloseIcon: true,
    closeIconColor: textoSobreAmarillo,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: rojoLadrillo),
    ),
    content: Row(
      children: [
        const CircleAvatar(
          radius: 16,
          backgroundColor: rojoLadrillo,
          child: Icon(Icons.check, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                key: const Key('pedido-enviado'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textoSobreAmarillo),
              ),
              Text(detalle, style: const TextStyle(color: textoSobreAmarillo)),
            ],
          ),
        ),
      ],
    ),
  );
}
