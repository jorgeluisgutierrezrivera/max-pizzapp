import 'dart:async';

import 'package:flutter/material.dart';

import '../tema.dart';
import 'red.dart';

/// Decide cuándo mostrar el aviso de canal caído (D-45). Es lógica sin pantalla: la usan
/// recepción y cocina.
///
/// - Si el dispositivo pierde la red, el aviso aparece en el acto.
/// - Al abrir la pantalla se esperan [graciaAlAbrir] a la primera conexión, para no alarmar
///   en cada arranque.
/// - Si el canal se corta, se espera [graciaAlCortarse] antes de avisar. Cuando el servidor
///   corta la conexión al vencer el token (D-47), la app vuelve a entrar en milisegundos: sin
///   esta espera, la banda parpadearía una vez por hora. Con el latido de 7 s (D-44), un
///   corte silencioso se avisa a los 8 s como mucho, bajo los 10 que pide RNF-05.
class VigiaDelCanal extends ChangeNotifier {
  VigiaDelCanal({
    required Stream<bool> conexion,
    required bool conectado,
    required this.red,
    this.graciaAlAbrir = const Duration(seconds: 5),
    this.graciaAlCortarse = const Duration(seconds: 1),
  }) : _conectado = conectado {
    _suscripciones
      ..add(conexion.listen(_alCambiarConexion))
      ..add(red.cambios.listen((_) => _evaluar()));
    if (!conectado) _esperar(graciaAlAbrir);
    _evaluar();
  }

  final Red red;
  final Duration graciaAlAbrir;
  final Duration graciaAlCortarse;

  final List<StreamSubscription<dynamic>> _suscripciones = [];
  bool _conectado;
  Timer? _espera;
  bool _mostrar = false;

  /// Si hay que mostrar el aviso ahora.
  bool get mostrar => _mostrar;

  void _alCambiarConexion(bool conectado) {
    final antes = _conectado;
    _conectado = conectado;
    if (conectado) {
      _espera?.cancel();
      _espera = null;
    } else if (antes) {
      _esperar(graciaAlCortarse);
    }
    _evaluar();
  }

  void _esperar(Duration cuanto) {
    _espera?.cancel();
    _espera = Timer(cuanto, () {
      _espera = null;
      _evaluar();
    });
  }

  void _evaluar() {
    final mostrar = !red.enLinea || (!_conectado && _espera == null);
    if (mostrar == _mostrar) return;
    _mostrar = mostrar;
    notifyListeners();
  }

  @override
  void dispose() {
    _espera?.cancel();
    for (final s in _suscripciones) {
      s.cancel();
    }
    super.dispose();
  }
}

/// La banda de canal caído (CA-03.2): dice que lo que se ve puede no estar al día y ofrece
/// *Recargar*, que vuelve a leer de la API lo que la pantalla muestra. No recarga la página:
/// eso obligaría a pasar otra vez por Keycloak. Mientras tanto se puede seguir trabajando,
/// porque las acciones van por la API y no por el canal.
class AvisoSinConexion extends StatefulWidget {
  const AvisoSinConexion({super.key, required this.alRecargar});

  final Future<void> Function() alRecargar;

  @override
  State<AvisoSinConexion> createState() => _AvisoSinConexionState();
}

class _AvisoSinConexionState extends State<AvisoSinConexion> {
  bool _recargando = false;

  Future<void> _recargar() async {
    setState(() => _recargando = true);
    try {
      await widget.alRecargar();
    } catch (_) {
      // Si la lectura falla, la pantalla ya muestra su error: aquí solo vuelve el botón.
    } finally {
      if (mounted) setState(() => _recargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final texto = Text.rich(
      const TextSpan(
        children: [
          TextSpan(text: 'Sin conexión en vivo. ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: 'Lo que ves puede no estar al día.'),
        ],
      ),
      key: const Key('texto-sin-conexion'),
      style: tema.textTheme.bodyLarge?.copyWith(color: textoSobreAmarillo),
    );
    final boton = FilledButton.icon(
      key: const Key('boton-recargar'),
      // El tema estira los botones a todo el ancho; en la fila, el botón mide lo suyo.
      style: FilledButton.styleFrom(minimumSize: const Size(150, 44)),
      onPressed: _recargando ? null : _recargar,
      icon: _recargando
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh),
      label: Text(_recargando ? 'Recargando…' : 'Recargar'),
    );
    const icono = Icon(Icons.wifi_off, color: textoSobreAmarillo);
    return Semantics(
      liveRegion: true,
      child: Material(
        key: const Key('aviso-sin-conexion'),
        color: amarilloSuave,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: LayoutBuilder(
            builder: (context, lados) => lados.maxWidth < 560
                // En el celular, el botón debajo del texto, a todo el ancho.
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [icono, const SizedBox(width: 10), Expanded(child: texto)],
                      ),
                      const SizedBox(height: 8),
                      boton,
                    ],
                  )
                : Row(
                    children: [icono, const SizedBox(width: 12), Expanded(child: texto), const SizedBox(width: 12), boton],
                  ),
          ),
        ),
      ),
    );
  }
}
