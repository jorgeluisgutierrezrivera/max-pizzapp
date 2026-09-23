import 'package:flutter/material.dart';

import 'configuracion.dart';
import 'pantallas/pantalla_acceso.dart';
import 'tema.dart';

/// En desarrollo: flutter run --dart-define=KEYCLOAK_URL=http://localhost:8082
/// En produccion no se define: la direccion se deduce del dominio.
const _keycloakDefinido = String.fromEnvironment('KEYCLOAK_URL');

void main() {
  String? errorDeConfiguracion;
  try {
    // En la web, Uri.base es la direccion de la pagina actual.
    Configuracion.deducir(paginaActual: Uri.base, keycloakDefinido: _keycloakDefinido);
  } on ErrorDeConfiguracion catch (e) {
    errorDeConfiguracion = e.mensaje;
  }
  runApp(MaxPizzappApp(errorDeConfiguracion: errorDeConfiguracion));
}

class MaxPizzappApp extends StatelessWidget {
  const MaxPizzappApp({super.key, this.errorDeConfiguracion});

  final String? errorDeConfiguracion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Max Pizzapp',
      debugShowCheckedModeBanner: false,
      theme: temaClaro(),
      darkTheme: temaOscuro(),
      // El inicio de sesion se conecta en la fase B del plan 04.
      home: PantallaAcceso(mensaje: errorDeConfiguracion),
    );
  }
}
