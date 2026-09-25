import 'package:flutter/material.dart';

import '../api/cliente_api.dart';
import '../api/usuario.dart';
import '../carta/producto.dart';
import '../carta/venta.dart';
import 'esqueleto_rol.dart';
import 'venta/comunes.dart';
import 'venta/formulario_de_venta.dart';
import 'venta/modal_bebidas.dart';
import 'venta/pedido_enviado.dart';

/// La pantalla de recepción: carga la carta, arma la venta en un solo formulario (D-36) y
/// la envía a cocina; o vende bebidas sueltas, sin nombre (D-38).
///
/// Muestra los cuatro estados de una pantalla con datos: cargando, error con Reintentar,
/// carta vacía y la venta. Al confirmar, el aviso con el número del pedido.
class PantallaRecepcion extends StatefulWidget {
  const PantallaRecepcion({
    super.key,
    required this.usuario,
    required this.alCerrarSesion,
    required this.cargarCarta,
    this.imagen = imagenDeRed,
    this.enviarPedido,
  });

  final Usuario usuario;
  final VoidCallback alCerrarSesion;
  final Future<Carta> Function() cargarCarta;
  final ConstructorImagen imagen;

  /// Envía el cuerpo de POST /api/v1/pedidos y devuelve el pedido guardado; también la
  /// venta directa de bebidas. Nulo si no hay cómo enviarlo: los botones se ven, deshabilitados.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> pedido)? enviarPedido;

  @override
  State<PantallaRecepcion> createState() => _PantallaRecepcionState();
}

class _PantallaRecepcionState extends State<PantallaRecepcion> {
  late Future<Carta> _carta;
  FormularioVenta? _formulario;

  bool _enviando = false;
  String? _errorDeEnvio;

  @override
  void initState() {
    super.initState();
    _carta = widget.cargarCarta();
  }

  @override
  void dispose() {
    _formulario?.dispose();
    super.dispose();
  }

  // Con llaves: setState no acepta un callback que devuelva un Future.
  void _recargar() => setState(() {
    _carta = widget.cargarCarta();
  });

  /// Una venta por carta cargada: si la carta se recarga, la venta empieza de nuevo.
  FormularioVenta _formularioPara(Carta carta) {
    if (_formulario?.carta != carta) {
      _formulario?.dispose();
      _formulario = FormularioVenta(carta);
    }
    return _formulario!;
  }

  Future<void> _confirmar(FormularioVenta formulario) async {
    setState(() {
      _enviando = true;
      _errorDeEnvio = null;
    });
    try {
      final pedido = await widget.enviarPedido!(formulario.aPedido());
      if (!mounted) return;
      // Guardado: el formulario queda limpio para el siguiente cliente, y un aviso lo confirma.
      formulario.limpiar();
      setState(() => _enviando = false);
      _avisar(pedido);
    } catch (error) {
      if (!mounted) return;
      // No se guardó: la venta queda tal cual, para corregirla o volver a enviarla.
      setState(() {
        _enviando = false;
        _errorDeEnvio = explicarErrorDeEnvio(error);
      });
    }
  }

  Future<void> _venderBebidas(Carta carta) async {
    final guardada = await mostrarVentaDeBebidas(
      context,
      carta: carta,
      imagen: widget.imagen,
      cobrar: widget.enviarPedido!,
      explicarError: explicarErrorDeEnvio,
    );
    if (guardada != null && mounted) _avisar(guardada);
  }

  /// El aviso de la venta guardada, que se cierra solo. Uno nuevo reemplaza al anterior.
  void _avisar(Map<String, dynamic> pedido) {
    final ancha = MediaQuery.sizeOf(context).width >= anchoConPanelLateral;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(avisoDeVentaGuardada(pedido, ancha: ancha));
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
          final formulario = _formularioPara(carta);
          final hayEnvio = widget.enviarPedido != null;
          return FormularioDeVenta(
            formulario: formulario,
            imagen: widget.imagen,
            alConfirmar: hayEnvio ? () => _confirmar(formulario) : null,
            alVenderBebidas: hayEnvio ? () => _venderBebidas(carta) : null,
            enviando: _enviando,
            errorDeEnvio: _errorDeEnvio,
          );
        },
      ),
    );
  }
}

/// Qué decirle a la vendedora cuando la venta no se guardó. Los mensajes de la API van sin
/// tildes; los casos que la app sabe resolver se explican aquí, con lo que hay que hacer.
String explicarErrorDeEnvio(Object error) {
  if (error is! ErrorApi) return 'No se pudo enviar la venta. Intenta de nuevo.';
  switch (error.codigo) {
    case 'PRODUCTO_NO_DISPONIBLE':
      final producto = error.datos['producto'];
      final nombre = producto is Map ? producto['nombre'] : null;
      return '${nombre ?? 'Un producto'} se agotó. Quítalo de la venta y vuelve a enviarla.';
    case 'PRECIO_CAMBIADO':
      final correcto = error.datos['totalCorrecto'];
      final total = correcto is num ? ' El total correcto es ${formatoBs((correcto * 100).round())}.' : '';
      return 'La carta cambió mientras se armaba la venta y no se guardó nada.$total '
          'Cancela esta venta y vuelve a armarla.';
    case 'SIN_CONEXION':
      return 'No se pudo enviar: no hay conexión con el servidor. La venta sigue aquí; vuelve a intentarlo.';
    default:
      return error.mensaje;
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
