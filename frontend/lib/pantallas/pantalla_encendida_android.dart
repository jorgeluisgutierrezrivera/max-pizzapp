import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'pantalla_encendida.dart';

/// La pantalla siempre encendida del APK de cocina (D-50), con `wakelock_plus`: mientras la
/// cola está abierta, Android no apaga la pantalla. Solo se importa desde main_cocina.dart.
///
/// No hace falta ningún permiso: solo vale mientras la app está al frente, y al cerrar
/// sesión o salir de la app el teléfono vuelve a apagarse como siempre.
class PantallaEncendidaAndroid implements PantallaEncendida {
  const PantallaEncendidaAndroid();

  @override
  void mantener() => WakelockPlus.enable().catchError(_anotar);

  @override
  void soltar() => WakelockPlus.disable().catchError(_anotar);

  static void _anotar(Object error) => debugPrint('No se pudo cambiar la pantalla encendida: $error');
}
