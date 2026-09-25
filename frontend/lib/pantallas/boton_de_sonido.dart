import 'package:flutter/material.dart';

import 'timbre.dart';

/// En la barra, el estado del sonido. Viene activado: se enciende solo con el primer toque en
/// la pantalla, y entonces muestra el ícono de que suena. Mientras tanto, se puede tocar para
/// activarlo y oír cómo suena. El navegador no deja sonar una página que nadie usó.
class BotonDeSonido extends StatelessWidget {
  const BotonDeSonido({super.key, required this.timbre});
  final Timbre timbre;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: timbre.cambios,
      builder: (context, _) {
        if (timbre.habilitado) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Tooltip(message: 'Sonido activado', child: Icon(Icons.volume_up)),
          );
        }
        // Con texto solo si sobra lugar; si no, el ícono con su descripción.
        final conTexto = MediaQuery.sizeOf(context).width >= 1000;
        return !conTexto
            ? IconButton(
                tooltip: 'Activar sonido: se activa al tocar la pantalla',
                onPressed: timbre.habilitar,
                icon: const Icon(Icons.volume_off),
              )
            : TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: timbre.habilitar,
                icon: const Icon(Icons.volume_off),
                label: const Text('Activar sonido'),
              );
      },
    );
  }
}
