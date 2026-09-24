import 'package:flutter/material.dart';

import '../api/usuario.dart';
import 'esqueleto_rol.dart';

class PantallaCocina extends StatelessWidget {
  const PantallaCocina({super.key, required this.usuario, required this.alCerrarSesion});

  final Usuario usuario;
  final VoidCallback alCerrarSesion;

  @override
  Widget build(BuildContext context) {
    return EsqueletoRol(
      titulo: 'Cocina',
      usuario: usuario,
      alCerrarSesion: alCerrarSesion,
      cuerpo: BienvenidaRol(
        icono: Icons.soup_kitchen,
        nombre: usuario.nombreVisible,
        texto: 'Desde aquí vas a ver la cola de pedidos, en orden de llegada.',
      ),
    );
  }
}
