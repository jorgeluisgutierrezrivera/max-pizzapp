import 'package:flutter/material.dart';

import 'autenticacion/navegador_web.dart';
import 'autenticacion/servicio_sesion.dart';
import 'configuracion.dart';
import 'pantallas/pantalla_acceso.dart';
import 'pantallas/pantalla_cargando.dart';
import 'pantallas/pantalla_sesion_iniciada.dart';
import 'tema.dart';

/// En desarrollo: flutter run --dart-define=KEYCLOAK_URL=http://localhost:8082
/// En produccion no se define: la direccion se deduce del dominio.
const _keycloakDefinido = String.fromEnvironment('KEYCLOAK_URL');

void main() {
  final navegador = NavegadorWeb();
  final Configuracion configuracion;
  try {
    configuracion = Configuracion.deducir(
      paginaActual: navegador.direccionActual,
      keycloakDefinido: _keycloakDefinido,
    );
  } on ErrorDeConfiguracion catch (e) {
    runApp(_App(inicio: PantallaAcceso(mensaje: e.mensaje)));
    return;
  }

  final sesion = ServicioSesion(configuracion: configuracion, navegador: navegador);
  runApp(_App(inicio: _SegunSesion(sesion: sesion)));
  sesion.arrancar();
}

class _App extends StatelessWidget {
  const _App({required this.inicio});

  final Widget inicio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Max Pizzapp',
      debugShowCheckedModeBanner: false,
      theme: temaClaro(),
      darkTheme: temaOscuro(),
      home: inicio,
    );
  }
}

/// Muestra la pantalla que corresponde al estado de la sesion.
class _SegunSesion extends StatelessWidget {
  const _SegunSesion({required this.sesion});

  final ServicioSesion sesion;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sesion,
      builder: (context, _) => switch (sesion.estado) {
        EstadoSesion.iniciando => const PantallaCargando(),
        EstadoSesion.sinSesion =>
          PantallaAcceso(alIniciarSesion: sesion.iniciarSesion, mensaje: sesion.mensaje),
        EstadoSesion.conSesion => PantallaSesionIniciada(alCerrarSesion: sesion.cerrarSesion),
      },
    );
  }
}
