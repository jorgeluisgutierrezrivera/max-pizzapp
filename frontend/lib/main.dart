import 'package:flutter/material.dart';

import 'api/cliente_api.dart';
import 'api/usuario.dart';
import 'autenticacion/navegador_web.dart';
import 'autenticacion/servicio_sesion.dart';
import 'configuracion.dart';
import 'pantallas/pantalla_acceso.dart';
import 'pantallas/pantalla_cargando.dart';
import 'pantallas/segun_rol.dart';
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
  final api = ClienteApi(
    base: configuracion.origen.replace(path: Configuracion.rutaApi),
    token: () => sesion.tokenAcceso,
    renovar: sesion.renovar,
  );
  runApp(_App(inicio: _SegunSesion(sesion: sesion, api: api)));
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
      // Tema oscuro fijo, con la identidad del local (D-29): no sigue el modo del dispositivo.
      theme: temaMaxPizzas(),
      home: inicio,
    );
  }
}

/// Muestra la pantalla que corresponde al estado de la sesion.
class _SegunSesion extends StatelessWidget {
  const _SegunSesion({required this.sesion, required this.api});

  final ServicioSesion sesion;
  final ClienteApi api;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sesion,
      builder: (context, _) => switch (sesion.estado) {
        EstadoSesion.iniciando => const PantallaCargando(),
        EstadoSesion.sinSesion =>
          PantallaAcceso(alIniciarSesion: sesion.iniciarSesion, mensaje: sesion.mensaje),
        EstadoSesion.conSesion => PantallaSegunRol(
            cargarUsuario: () async => Usuario.desdeJson(await api.obtener('/sesion')),
            alCerrarSesion: sesion.cerrarSesion,
          ),
      },
    );
  }
}
