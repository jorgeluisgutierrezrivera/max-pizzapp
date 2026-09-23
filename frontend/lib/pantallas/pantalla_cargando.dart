import 'package:flutter/material.dart';

/// Mientras la app va y vuelve de Keycloak, o espera una respuesta.
class PantallaCargando extends StatelessWidget {
  const PantallaCargando({super.key, this.texto = 'Conectando…'});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(texto, style: tema.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
