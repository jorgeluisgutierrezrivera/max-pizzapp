import 'package:web/web.dart' as web;

import 'navegador.dart';

/// El navegador real. Solo compila para la web: las pruebas usan una version falsa.
class NavegadorWeb implements Navegador {
  @override
  Uri get direccionActual => Uri.parse(web.window.location.href);

  @override
  void irA(Uri destino) => web.window.location.assign(destino.toString());

  @override
  void reemplazarDireccion(Uri destino) =>
      web.window.history.replaceState(null, '', destino.toString());

  @override
  String? leer(String clave) => web.window.sessionStorage.getItem(clave);

  @override
  void guardar(String clave, String valor) => web.window.sessionStorage.setItem(clave, valor);

  @override
  void borrar(String clave) => web.window.sessionStorage.removeItem(clave);
}
