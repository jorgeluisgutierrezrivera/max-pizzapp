import 'package:flutter/material.dart';

import '../api/cliente_api.dart';
import '../api/usuario.dart';
import '../carta/producto.dart';
import '../carta/venta.dart';
import 'esqueleto_rol.dart';
import 'venta/comunes.dart';
import 'venta/venta_guiada.dart';

/// La pantalla de recepción: carga la carta y guía la venta (D-30).
///
/// Muestra los cuatro estados de una pantalla con datos: cargando, error con Reintentar,
/// carta vacía y la venta.
class PantallaRecepcion extends StatefulWidget {
  const PantallaRecepcion({
    super.key,
    required this.usuario,
    required this.alCerrarSesion,
    required this.cargarCarta,
    this.imagen = imagenDeRed,
    this.alTerminarVenta,
  });

  final Usuario usuario;
  final VoidCallback alCerrarSesion;
  final Future<Carta> Function() cargarCarta;
  final ConstructorImagen imagen;

  /// Envía la venta a cocina. Nulo hasta la tarjeta 06: el botón se ve, deshabilitado.
  final void Function(EstadoVenta venta)? alTerminarVenta;

  @override
  State<PantallaRecepcion> createState() => _PantallaRecepcionState();
}

class _PantallaRecepcionState extends State<PantallaRecepcion> {
  late Future<Carta> _carta;
  RecorridoVenta? _recorrido;

  @override
  void initState() {
    super.initState();
    _carta = widget.cargarCarta();
  }

  @override
  void dispose() {
    _recorrido?.dispose();
    super.dispose();
  }

  // Con llaves: setState no acepta un callback que devuelva un Future.
  void _recargar() => setState(() {
        _carta = widget.cargarCarta();
      });

  /// Una venta por carta cargada: si la carta se recarga, la venta empieza de nuevo.
  RecorridoVenta _recorridoPara(Carta carta) {
    if (_recorrido?.carta != carta) {
      _recorrido?.dispose();
      _recorrido = RecorridoVenta(carta);
    }
    return _recorrido!;
  }

  @override
  Widget build(BuildContext context) {
    return EsqueletoRol(
      titulo: 'Recepción',
      usuario: widget.usuario,
      alCerrarSesion: widget.alCerrarSesion,
      cuerpo: FutureBuilder<Carta>(
        future: _carta,
        builder: (context, estado) {
          if (estado.connectionState != ConnectionState.done) {
            return const _Aviso(mensaje: 'Cargando la carta…');
          }
          if (estado.hasError) {
            final error = estado.error;
            return _Aviso(
              icono: Icons.error_outline,
              esError: true,
              mensaje: error is ErrorApi ? error.mensaje : 'No se pudo cargar la carta.',
              alReintentar: _recargar,
            );
          }
          final carta = estado.requireData;
          if (carta.vacia) {
            return _Aviso(
              icono: Icons.menu_book_outlined,
              mensaje: 'La carta todavía no tiene productos.',
              alReintentar: _recargar,
            );
          }
          final recorrido = _recorridoPara(carta);
          final terminar = widget.alTerminarVenta;
          return VentaGuiada(
            recorrido: recorrido,
            imagen: widget.imagen,
            alTerminar: terminar == null ? null : () => terminar(recorrido.estado),
          );
        },
      ),
    );
  }
}

/// Cargando, vacía o error: un mensaje centrado y, si corresponde, reintentar.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje, this.icono, this.alReintentar, this.esError = false});

  final IconData? icono;
  final String mensaje;
  final VoidCallback? alReintentar;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono == null)
                const CircularProgressIndicator()
              else
                Icon(icono, size: 48, color: esError ? tema.colorScheme.error : tema.colorScheme.outline),
              const SizedBox(height: 16),
              Text(mensaje, textAlign: TextAlign.center, style: tema.textTheme.bodyLarge),
              if (alReintentar != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: alReintentar,
                  icon: const Icon(Icons.refresh),
                  label: Text(esError ? 'Reintentar' : 'Actualizar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
