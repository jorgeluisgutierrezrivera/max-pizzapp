import 'package:flutter/material.dart';

import '../api/cliente_api.dart';
import '../api/usuario.dart';
import '../carta/producto.dart';
import 'pantalla_cargando.dart';
import 'pantalla_cocina.dart';
import 'pantalla_error.dart';
import 'pantalla_recepcion.dart';

/// Pregunta al servidor quien es la persona y muestra la pantalla de su rol.
///
/// La app no decide el rol leyendo el token por su cuenta: lo decide el servidor, que acaba
/// de validar el token. La app puede ocultar lo que un rol no debe ver; impedirlo es tarea
/// del servidor.
class PantallaSegunRol extends StatefulWidget {
  const PantallaSegunRol({
    super.key,
    required this.cargarUsuario,
    required this.cargarCarta,
    required this.alCerrarSesion,
  });

  final Future<Usuario> Function() cargarUsuario;
  final Future<Carta> Function() cargarCarta;
  final VoidCallback alCerrarSesion;

  @override
  State<PantallaSegunRol> createState() => _PantallaSegunRolState();
}

class _PantallaSegunRolState extends State<PantallaSegunRol> {
  late Future<Usuario> _usuario;

  @override
  void initState() {
    super.initState();
    _usuario = widget.cargarUsuario();
  }

  // Cuerpo con llaves a proposito: con "=>", el callback devolveria el Future de la
  // asignacion y setState lo rechaza.
  void _reintentar() => setState(() {
        _usuario = widget.cargarUsuario();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Usuario>(
      future: _usuario,
      builder: (context, estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const PantallaCargando(texto: 'Verificando tu cuenta…');
        }
        if (estado.hasError) {
          final error = estado.error;
          return PantallaError(
            mensaje: error is ErrorApi ? error.mensaje : 'No se pudo verificar tu cuenta.',
            alReintentar: _reintentar,
            alCerrarSesion: widget.alCerrarSesion,
          );
        }
        final usuario = estado.requireData;
        return switch (usuario.rol) {
          Rol.recepcion => PantallaRecepcion(
              usuario: usuario,
              alCerrarSesion: widget.alCerrarSesion,
              cargarCarta: widget.cargarCarta,
            ),
          Rol.cocina => PantallaCocina(usuario: usuario, alCerrarSesion: widget.alCerrarSesion),
          null => PantallaError(
              mensaje: 'Tu cuenta no tiene un rol de este sistema. Pide que te asignen '
                  'recepción o cocina.',
              alReintentar: _reintentar,
              alCerrarSesion: widget.alCerrarSesion,
            ),
        };
      },
    );
  }
}
