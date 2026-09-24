import 'package:flutter/material.dart';

import '../api/usuario.dart';
import 'logo.dart';

/// Lo comun a las pantallas de cada rol: la barra con el logo del local, el rol, quien esta
/// dentro y el boton de salir. En pantallas angostas (el celular) solo quedan los iconos.
class EsqueletoRol extends StatelessWidget {
  const EsqueletoRol({
    super.key,
    required this.titulo,
    required this.usuario,
    required this.alCerrarSesion,
    required this.cuerpo,
    this.acciones = const [],
  });

  final String titulo;
  final Usuario usuario;
  final VoidCallback alCerrarSesion;
  final Widget cuerpo;

  /// Botones propios de la pantalla, antes de quien esta dentro y de salir.
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final angosta = MediaQuery.sizeOf(context).width < 600;
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const LogoMaxPizzas(tamano: 34),
            const SizedBox(width: 12),
            // En un celular angosto, con los botones de la pantalla, el titulo cede espacio.
            Flexible(child: Text(titulo, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          ...acciones,
          if (!angosta)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(usuario.nombreVisible,
                    style: TextStyle(color: colores.onSurfaceVariant)),
              ),
            ),
          if (angosta)
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: alCerrarSesion,
              icon: const Icon(Icons.logout),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: alCerrarSesion,
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ),
        ],
      ),
      body: SafeArea(child: cuerpo),
    );
  }
}

/// Cuerpo provisorio de las pantallas de rol hasta que lleguen las tarjetas 05 y 06.
class BienvenidaRol extends StatelessWidget {
  const BienvenidaRol({super.key, required this.icono, required this.nombre, required this.texto});

  final IconData icono;
  final String nombre;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 56, color: tema.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Hola, $nombre', textAlign: TextAlign.center, style: tema.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: tema.textTheme.bodyMedium
                      ?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
