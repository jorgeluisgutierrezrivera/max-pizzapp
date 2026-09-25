import 'package:flutter/material.dart';

import '../tema.dart';
import 'logo.dart';

/// Primera pantalla: el local y el sistema, y el botón que lleva a Keycloak. El sistema es
/// Max Pizzapp; el local, Max's Pizzas (D-29).
///
/// La app nunca pide la contraseña: la pide Keycloak, en su propia página. Por eso aquí no
/// hay campos de usuario ni de clave.
///
/// En una pantalla ancha, dos mitades: la foto de una pizza del local con su nombre, y el
/// acceso. En el celular, la foto arriba, como portada. Todo lo que dice del local sale de
/// sus datos registrados: nada inventado.
class PantallaAcceso extends StatelessWidget {
  const PantallaAcceso({super.key, this.alIniciarSesion, this.mensaje});

  /// Si es null, el botón queda deshabilitado (por ejemplo, mientras se procesa el regreso
  /// desde Keycloak).
  final VoidCallback? alIniciarSesion;

  /// Aviso opcional sobre el botón: sesión vencida, error de conexión, etc.
  final String? mensaje;

  /// Desde este ancho, la foto y el acceso van lado a lado.
  static const anchoDividido = 900.0;

  @override
  Widget build(BuildContext context) {
    final acceso = _Acceso(alIniciarSesion: alIniciarSesion, mensaje: mensaje);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, lados) {
          if (lados.maxWidth >= anchoDividido) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(flex: 11, child: _Portada()),
                Expanded(
                  flex: 9,
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: acceso),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          // En el celular: la foto arriba y el acceso debajo, con el logo montado sobre el
          // borde de la foto.
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 230, child: _Portada(compacta: true)),
                Transform.translate(
                  offset: const Offset(0, -44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: acceso),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// La foto de una pizza del local, con su nombre encima.
class _Portada extends StatelessWidget {
  const _Portada({this.compacta = false});
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    const blanco = Colors.white;
    const suave = Color(0xE6FFFFFF);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/marca/portada.webp',
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          filterQuality: FilterQuality.medium,
        ),
        // Oscurece el pie de la foto para que el texto blanco se lea sobre cualquier parte.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.35, 1],
              colors: [Color(0x00000000), Color(0xD91E0E0B)],
            ),
          ),
        ),
        Positioned(
          left: compacta ? 20 : 48,
          right: compacta ? 20 : 48,
          bottom: compacta ? 56 : 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Max's Pizzas",
                style: (compacta ? tema.textTheme.headlineMedium : tema.textTheme.displayMedium)?.copyWith(
                  color: blanco,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!compacta) ...[
                const SizedBox(height: 8),
                Text(
                  'Pizzería de Tarija. Pizzas enteras, de un sabor o mitad y mitad.',
                  style: tema.textTheme.titleMedium?.copyWith(color: suave),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18, color: suave),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Villa Fátima · Villa Avaroa · Tabladita',
                        style: tema.textTheme.bodyMedium?.copyWith(color: suave),
                      ),
                    ),
                  ],
                ),
              ] else
                Text('Pizzería de Tarija', style: tema.textTheme.titleSmall?.copyWith(color: suave)),
            ],
          ),
        ),
      ],
    );
  }
}

/// El acceso: el logo, el nombre del sistema, el botón y qué hace el sistema.
class _Acceso extends StatelessWidget {
  const _Acceso({required this.alIniciarSesion, required this.mensaje});

  final VoidCallback? alIniciarSesion;
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // El borde blanco lo separa de la foto cuando va montado sobre ella, en el celular.
        Center(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const LogoMaxPizzas(tamano: 88),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'Max '),
              TextSpan(
                text: 'Pizzapp',
                style: TextStyle(color: rojoLadrillo),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Pedidos entre recepción y cocina, en tiempo real.',
          textAlign: TextAlign.center,
          style: tema.textTheme.bodyLarge?.copyWith(color: colores.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        if (mensaje != null) ...[_Aviso(texto: mensaje!), const SizedBox(height: 16)],
        FilledButton.icon(
          onPressed: alIniciarSesion,
          icon: const Icon(Icons.login),
          label: const Text('Iniciar sesión'),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 16, color: colores.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                "Acceso para el personal de Max's Pizzas",
                style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Divider(height: 1),
        const SizedBox(height: 20),
        const _Detalle(icono: Icons.receipt_long_outlined, texto: 'La venta en una sola pantalla'),
        const _Detalle(icono: Icons.soup_kitchen_outlined, texto: 'Cocina ve cada pedido al instante'),
        const _Detalle(icono: Icons.notifications_active_outlined, texto: 'Aviso cuando un pedido está listo'),
        const SizedBox(height: 20),
        Text(
          "Max's Pizzas · Villa Fátima, Tarija",
          textAlign: TextAlign.center,
          style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Una línea de lo que hace el sistema, con su ícono en un círculo rojo suave.
class _Detalle extends StatelessWidget {
  const _Detalle({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: rojoSuave, shape: BoxShape.circle),
            child: Icon(icono, size: 20, color: rojoLadrillo),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: tema.textTheme.bodyMedium)),
        ],
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
      decoration: BoxDecoration(color: colores.errorContainer, borderRadius: BorderRadius.circular(10)),
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
