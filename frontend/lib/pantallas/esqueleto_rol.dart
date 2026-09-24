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
    final ancho = MediaQuery.sizeOf(context).width;
    final angosta = ancho < 600;
    // El nombre de la cuenta necesita lugar: en una tableta, la barra se lo cede a los
    // botones de la pantalla.
    final conNombre = ancho >= 900;
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
          if (conNombre)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(usuario.nombreVisible, style: const TextStyle(color: Colors.white)),
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
                style: TextButton.styleFrom(foregroundColor: Colors.white),
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
