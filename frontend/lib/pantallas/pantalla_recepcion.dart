import 'package:flutter/material.dart';

import '../api/usuario.dart';
import 'esqueleto_rol.dart';

class PantallaRecepcion extends StatelessWidget {
  const PantallaRecepcion({super.key, required this.usuario, required this.alCerrarSesion});

  final Usuario usuario;
  final VoidCallback alCerrarSesion;

  @override
  Widget build(BuildContext context) {
    return EsqueletoRol(
      titulo: 'Recepción',
      usuario: usuario,
      alCerrarSesion: alCerrarSesion,
      cuerpo: BienvenidaRol(
        icono: Icons.point_of_sale,
        nombre: usuario.nombreVisible,
        texto: 'Desde aquí vas a registrar los pedidos a partir de la carta.',
      ),
    );
  }
}
