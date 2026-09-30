import 'package:flutter/material.dart';

import '../tema.dart';
import 'timbre.dart';

/// La franja de sonido apagado. El navegador no deja sonar una página hasta que la persona la
/// toca, e iniciar sesión recarga la página: si nadie toca la pantalla, el primer pedido que
/// llega no suena. Mientras sea así, la franja lo dice. Al primer toque en cualquier parte, el
/// sonido se activa, suena una vez para confirmarlo y la franja se va.
///
/// No tiene botón propio: cualquier toque la resuelve, y un botón aquí haría sonar dos veces.
class AvisoSinSonido extends StatelessWidget {
  const AvisoSinSonido({super.key, required this.timbre});

  final Timbre timbre;

  /// La letra de la franja, sobre el rojo suave del fondo.
  static const letra = Color(0xFF7A2219);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: timbre.cambios,
      builder: (context, _) {
        if (!timbre.pendienteDeActivar) return const SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          child: Material(
            key: const Key('aviso-sin-sonido'),
            color: rojoSuave,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.volume_off, color: letra),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(text: 'El sonido está apagado. ', style: TextStyle(fontWeight: FontWeight.w800)),
                          TextSpan(text: 'Tocá en cualquier parte de la pantalla para activarlo.'),
                        ],
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: letra),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
