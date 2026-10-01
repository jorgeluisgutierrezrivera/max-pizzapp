import 'package:flutter/material.dart';

/// Un error que se muestra, no se traga: el mensaje, reintentar si sirve de algo y, si hay
/// sesion, salir.
class PantallaError extends StatelessWidget {
  const PantallaError({
    super.key,
    required this.mensaje,
    this.alReintentar,
    this.alCerrarSesion,
    this.icono = Icons.error_outline,
  });

  final String mensaje;
  final VoidCallback? alReintentar;
  final VoidCallback? alCerrarSesion;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icono, size: 48, color: tema.colorScheme.error),
                const SizedBox(height: 16),
                Text(mensaje, textAlign: TextAlign.center, style: tema.textTheme.bodyLarge),
                const SizedBox(height: 24),
                if (alReintentar != null)
                  FilledButton.icon(
                    onPressed: alReintentar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                if (alCerrarSesion != null) ...[
                  if (alReintentar != null) const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: alCerrarSesion,
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
