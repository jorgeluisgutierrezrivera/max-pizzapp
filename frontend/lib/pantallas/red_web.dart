import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'red.dart';

/// La red según el navegador: los eventos `online` y `offline` de la ventana. Solo se importa
/// desde main.dart: las pruebas corren fuera del navegador.
class RedWeb implements Red {
  RedWeb() {
    web.window.addEventListener('online', ((web.Event _) => _cambios.add(true)).toJS);
    web.window.addEventListener('offline', ((web.Event _) => _cambios.add(false)).toJS);
  }

  final _cambios = StreamController<bool>.broadcast();

  @override
  bool get enLinea => web.window.navigator.onLine;

  @override
  Stream<bool> get cambios => _cambios.stream;
}
