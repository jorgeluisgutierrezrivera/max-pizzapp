import 'package:flutter/material.dart';

import 'api/canal_en_vivo.dart';
import 'api/cliente_api.dart';
import 'app.dart';
import 'autenticacion/navegador_web.dart';
import 'autenticacion/servicio_sesion.dart';
import 'configuracion.dart';
import 'pantallas/pantalla_acceso.dart';
import 'pantallas/red_web.dart';
import 'pantallas/telefono_web.dart';
import 'pantallas/timbre_web.dart';

/// La entrada de la web: recepción y cocina en el navegador. El APK de cocina tiene la suya,
/// main_cocina.dart (D-48); las pantallas son las mismas (app.dart).
///
/// En desarrollo: flutter run --dart-define=KEYCLOAK_URL=http://localhost:8082
/// En produccion no se define: la direccion se deduce del dominio.
const _keycloakDefinido = String.fromEnvironment('KEYCLOAK_URL');

void main() {
  final navegador = NavegadorWeb();
  final Configuracion configuracion;
  try {
    configuracion = Configuracion.deducir(paginaActual: navegador.direccionActual, keycloakDefinido: _keycloakDefinido);
  } on ErrorDeConfiguracion catch (e) {
    runApp(AppMaxPizzapp(inicio: PantallaAcceso(mensaje: e.mensaje)));
    return;
  }

  final sesion = ServicioSesion(configuracion: configuracion, navegador: navegador);
  final api = ClienteApi(
    base: configuracion.origen.replace(path: Configuracion.rutaApi),
    token: () => sesion.tokenAcceso,
    renovar: sesion.renovar,
    alRechazarSesion: sesion.terminarSesionRechazada,
  );
  CanalEnVivo crearCanal() => CanalSocketIo(
        origen: configuracion.origen,
        token: () => sesion.tokenAcceso,
        renovar: sesion.renovar,
        alRechazarSesion: sesion.terminarSesionRechazada,
      );
  runApp(
    AppMaxPizzapp(
      inicio: SegunSesion(
        sesion: sesion,
        api: api,
        crearCanal: crearCanal,
        timbre: TimbreWeb(),
        red: RedWeb(),
        llamar: llamarPorTelefono,
      ),
    ),
  );
  sesion.arrancar();
}
