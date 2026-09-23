import 'package:flutter/material.dart';

/// Provisoria de la fase B: confirma que el acceso funciona y permite salir. En la fase C
/// la reemplaza la pantalla de cada rol, segun lo que confirme GET /api/v1/sesion.
class PantallaSesionIniciada extends StatelessWidget {
  const PantallaSesionIniciada({super.key, required this.alCerrarSesion});

  final VoidCallback alCerrarSesion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Max Pizzapp'),
        actions: [
          TextButton.icon(
            onPressed: alCerrarSesion,
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Sesión iniciada.', style: tema.textTheme.titleLarge),
        ),
      ),
    );
  }
}
