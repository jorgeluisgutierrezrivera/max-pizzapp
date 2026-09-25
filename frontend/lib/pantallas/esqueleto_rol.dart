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
    this.pestanas,
  });

  final String titulo;
  final Usuario usuario;
  final VoidCallback alCerrarSesion;
  final Widget cuerpo;

  /// Botones propios de la pantalla, antes de quien esta dentro y de salir.
  final List<Widget> acciones;

  /// Las pestanas de la pantalla, como las de recepcion. En una pantalla ancha van en la
  /// misma barra, junto al titulo, para no quitarle alto al contenido; si no, debajo.
  final PreferredSizeWidget? pestanas;

  /// Desde este ancho, las pestanas caben en la barra, junto al titulo.
  static const anchoPestanasEnLaBarra = 1100.0;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final angosta = ancho < 600;
    final pestanasArriba = pestanas != null && ancho >= anchoPestanasEnLaBarra;
    // El nombre de la cuenta necesita lugar: en una tableta, la barra se lo cede a los
    // botones de la pantalla, y con pestanas en la barra, a las pestanas.
    final conNombre = ancho >= (pestanasArriba ? 1400 : 900);
    return Scaffold(
      appBar: AppBar(
        bottom: pestanas == null || pestanasArriba ? null : pestanas,
        titleSpacing: 16,
        title: Row(
          children: [
            const LogoMaxPizzas(tamano: 34),
            const SizedBox(width: 12),
            // En un celular angosto, con los botones de la pantalla, el titulo cede espacio.
            Flexible(child: Text(titulo, overflow: TextOverflow.ellipsis)),
            if (pestanasArriba) ...[const SizedBox(width: 24), Flexible(flex: 3, child: pestanas!)],
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
            IconButton(tooltip: 'Cerrar sesión', onPressed: alCerrarSesion, icon: const Icon(Icons.logout))
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
