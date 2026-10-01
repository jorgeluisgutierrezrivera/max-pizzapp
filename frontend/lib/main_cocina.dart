import 'package:flutter/material.dart';

import 'api/canal_en_vivo.dart';
import 'api/cliente_api.dart';
import 'app.dart';
import 'autenticacion/autorizador_android.dart';
import 'autenticacion/servicio_sesion.dart';
import 'configuracion.dart';
import 'pantallas/pantalla_acceso.dart';
import 'pantallas/red.dart';
import 'pantallas/timbre.dart';

/// La entrada del APK de cocina (D-48): el mismo código que la web, con las piezas de
/// Android. Recepción sigue en la web.
///
/// La dirección del servidor llega al compilar, porque en el teléfono no hay página de la
/// que deducirla:
///   flutter build apk -t lib/main_cocina.dart --dart-define=ORIGEN=https://maxpizzapp.tech
/// En desarrollo, contra el entorno local (con adb reverse de los puertos 3001 y 8082):
///   flutter run -t lib/main_cocina.dart --dart-define=ORIGEN=http://localhost:3001
///     --dart-define=KEYCLOAK_URL=http://localhost:8082
const _origenDefinido = String.fromEnvironment('ORIGEN');
const _keycloakDefinido = String.fromEnvironment('KEYCLOAK_URL');

const _titulo = 'Max Pizzapp Cocina';

void main() {
  final Configuracion configuracion;
  try {
    configuracion = Configuracion.paraApp(origenDefinido: _origenDefinido, keycloakDefinido: _keycloakDefinido);
  } on ErrorDeConfiguracion catch (e) {
    runApp(AppMaxPizzapp(titulo: _titulo, inicio: PantallaAcceso(mensaje: e.mensaje)));
    return;
  }

  final sesion = ServicioSesion(
    configuracion: configuracion,
    autorizador: AutorizadorAndroid(configuracion: configuracion),
  );
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
      titulo: _titulo,
      inicio: SegunSesion(
        sesion: sesion,
        api: api,
        crearCanal: crearCanal,
        timbre: TimbreMudo(),
        // Sin paquete de red (D-50): al perderla, Android cierra las conexiones y el latido
        // del canal cubre el resto.
        red: const RedSiempreEnLinea(),
        webDeRecepcion: configuracion.origen,
      ),
    ),
  );
  sesion.arrancar();
}
