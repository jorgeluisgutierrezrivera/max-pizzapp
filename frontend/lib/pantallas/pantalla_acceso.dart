import 'package:flutter/material.dart';

/// Primera pantalla: la marca y el boton que lleva a Keycloak.
///
/// La app nunca pide la contrasena: la pide Keycloak, en su propia pagina. Por eso aqui no
/// hay campos de usuario ni de clave.
class PantallaAcceso extends StatelessWidget {
  const PantallaAcceso({super.key, this.alIniciarSesion, this.mensaje});

  /// Si es null, el boton queda deshabilitado (por ejemplo, mientras se procesa el regreso
  /// desde Keycloak).
  final VoidCallback? alIniciarSesion;

  /// Aviso opcional sobre el boton: sesion vencida, error de conexion, etc.
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colores.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'Max '),
                          TextSpan(text: 'Pizzapp', style: TextStyle(color: colores.primary)),
                        ]),
                        style: tema.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pedidos entre recepción y cocina, en tiempo real.',
                        style: tema.textTheme.bodyMedium
                            ?.copyWith(color: colores.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                      if (mensaje != null) ...[
                        _Aviso(texto: mensaje!),
                        const SizedBox(height: 16),
                      ],
                      FilledButton.icon(
                        onPressed: alIniciarSesion,
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar sesión'),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Max Pizzas · Villa Fátima, Tarija',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.bodySmall
                            ?.copyWith(color: colores.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colores.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: colores.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: TextStyle(color: colores.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
