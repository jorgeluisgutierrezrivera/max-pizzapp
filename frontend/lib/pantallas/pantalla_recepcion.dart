import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/canal_en_vivo.dart';
import '../api/cliente_api.dart';
import '../api/usuario.dart';
import '../carta/producto.dart';
import '../carta/venta.dart';
import '../pedidos/pedido.dart';
import '../pedidos/pedidos_en_vivo.dart';
import '../tema.dart';
import 'aviso_sin_conexion.dart';
import 'aviso_sin_sonido.dart';
import 'boton_de_sonido.dart';
import 'esqueleto_rol.dart';
import 'panel_de_carta.dart';
import 'pedidos_de_recepcion.dart';
import 'red.dart';
import 'timbre.dart';
import 'venta/comunes.dart';
import 'venta/formulario_de_venta.dart';
import 'venta/modal_bebidas.dart';
import 'venta/pedido_enviado.dart';

Future<List<Pedido>> _sinPedidos() async => const [];
Future<Pedido> _sinApi(Pedido pedido, [Object? _]) =>
    Future.error(const ErrorApi(0, 'SIN_API', 'Esta pantalla no tiene cómo cambiar pedidos.'));
CanalEnVivo _sinCanal() => const CanalApagado();
void _sinTelefono(String numero) {}

/// El título de la pestaña del navegador: con pedidos listos, se ve aunque la vendedora esté
/// en otra pestaña (pedido del autor, 24-sep).
void ponerTituloDeLaPestana(int listos) {
  SystemChrome.setApplicationSwitcherDescription(
    ApplicationSwitcherDescription(
      label: listos == 0 ? 'Max Pizzapp' : '($listos) ${listos == 1 ? 'Pedido listo' : 'Pedidos listos'} · Max Pizzapp',
      primaryColor: rojoLadrillo.toARGB32(),
    ),
  );
}

/// La pantalla de recepción, con dos pestañas en la barra:
///
/// - *Nueva venta*: arma la venta en un solo formulario (D-36) y la envía a cocina; o vende
///   bebidas sueltas, sin nombre (D-38).
/// - *Pedidos*: los que están en cocina y los listos, en vivo, con *Entregar*, *Cancelar*,
///   *Llamar* y *Agregar*. Cuando cocina marca uno listo, suena, se avisa y el título de la
///   pestaña del navegador lo dice, aunque se esté en *Nueva venta*.
///
/// Las dos quedan vivas al cambiar de pestaña: una venta a medio armar no se pierde por ir a
/// entregar un pedido.
///
/// Si el canal en vivo se cae, una banda sobre las dos pestañas lo dice y ofrece *Recargar*
/// (D-45): también en *Nueva venta*, porque sin canal no llega el aviso de pedido listo.
/// *Recargar* vuelve a leer los pedidos, no la carta: recargar la carta reiniciaría la venta
/// que se está armando.
///
/// La carta se mantiene al día sin reiniciar la venta (RF-13, D-67): el botón *Carta* de la
/// barra marca lo que se agotó; el aviso en vivo apaga o repone el producto en la misma
/// carta, y si lo marcó cocina, un aviso lo dice; y al volver el canal después de un corte,
/// se relee solo la disponibilidad.
class PantallaRecepcion extends StatefulWidget {
  const PantallaRecepcion({
    super.key,
    required this.usuario,
    required this.alCerrarSesion,
    required this.cargarCarta,
    this.imagen = imagenDeRed,
    this.enviarPedido,
    this.cargarPedidos = _sinPedidos,
    this.cambiarEstado = _sinApi,
    this.cancelarPedido = _sinApi,
    this.agregarAlPedido = _sinApi,
    this.marcarDisponibilidad = sinMarcarDisponibilidad,
    this.marcarCategoria = sinMarcarCategoria,
    this.crearCanal = _sinCanal,
    this.timbre,
    this.red = const RedSiempreEnLinea(),
    this.llamar = _sinTelefono,
    this.ponerTitulo = ponerTituloDeLaPestana,
    this.reloj = DateTime.now,
  });

  final Usuario usuario;
  final VoidCallback alCerrarSesion;
  final Future<Carta> Function() cargarCarta;
  final ConstructorImagen imagen;

  /// Envía el cuerpo de POST /api/v1/pedidos y devuelve el pedido guardado; también la
  /// venta directa de bebidas. Nulo si no hay cómo enviarlo: los botones se ven, deshabilitados.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> pedido)? enviarPedido;

  /// GET /api/v1/pedidos: los activos.
  final Future<List<Pedido>> Function() cargarPedidos;

  /// PATCH /api/v1/pedidos/:id/estado, con la versión que se ve.
  final Future<Pedido> Function(Pedido pedido, EstadoPedido hacia) cambiarEstado;

  /// POST /api/v1/pedidos/:id/cancelacion, con el motivo.
  final Future<Pedido> Function(Pedido pedido, String motivo) cancelarPedido;

  /// POST /api/v1/pedidos/:id/lineas.
  final Future<Pedido> Function(Pedido pedido, Map<String, dynamic> cuerpo) agregarAlPedido;

  /// PATCH /api/v1/productos/:id/disponibilidad (RF-13).
  final MarcarDisponibilidad marcarDisponibilidad;

  /// PATCH /api/v1/productos/disponibilidad: una categoría entera (D-70).
  final MarcarCategoria marcarCategoria;
  final CanalEnVivo Function() crearCanal;
  final Timbre? timbre;
  final Red red;

  /// Abre el marcador del teléfono con ese número.
  final void Function(String numero) llamar;
  final void Function(int listos) ponerTitulo;
  final DateTime Function() reloj;

  @override
  State<PantallaRecepcion> createState() => _PantallaRecepcionState();
}

class _PantallaRecepcionState extends State<PantallaRecepcion> with SingleTickerProviderStateMixin {
  late Future<Carta> _carta;
  Carta? _cartaCargada;
  FormularioVenta? _formulario;

  bool _enviando = false;
  String? _errorDeEnvio;

  late final TabController _pestanas = TabController(length: 2, vsync: this);
  late final PedidosEnVivo _pedidos = PedidosEnVivo(cargar: widget.cargarPedidos, canal: widget.crearCanal());
  late final VigiaDelCanal _vigia;
  late final Timbre _timbre = widget.timbre ?? TimbreMudo();
  StreamSubscription<Pedido>? _listos;
  StreamSubscription<Map<String, dynamic>>? _disponibilidades;
  StreamSubscription<Map<String, dynamic>>? _categorias;
  StreamSubscription<bool>? _conexion;
  bool _seCorto = false;
  int _listosEnElTitulo = 0;

  @override
  void initState() {
    super.initState();
    _cargarCarta();
    _pestanas.addListener(() => setState(() {}));
    _listos = _pedidos.quedaronListos.listen(_alQuedarListo);
    _pedidos.addListener(_alCambiarPedidos);
    // Antes de iniciar, que es cuando se conecta el canal: así no se pierde el primer "conectado".
    _vigia = VigiaDelCanal(conexion: _pedidos.canal.conexion, conectado: _pedidos.canal.conectado, red: widget.red);
    _disponibilidades = _pedidos.canal.disponibilidades.listen(_alCambiarDisponibilidad);
    _categorias = _pedidos.canal.disponibilidadesDeCategoria.listen(_alCambiarCategoria);
    _conexion = _pedidos.canal.conexion.listen(_alCambiarConexion);
    _pedidos.iniciar();
  }

  @override
  void dispose() {
    _listos?.cancel();
    _disponibilidades?.cancel();
    _categorias?.cancel();
    _conexion?.cancel();
    _vigia.dispose();
    _pedidos.removeListener(_alCambiarPedidos);
    _pedidos.dispose();
    _pestanas.dispose();
    _formulario?.dispose();
    widget.ponerTitulo(0);
    super.dispose();
  }

  void _cargarCarta() {
    _carta = widget.cargarCarta();
    _carta.then((carta) {
      if (mounted) setState(() => _cartaCargada = carta);
    }, onError: (_) {});
  }

  // Con llaves: setState no acepta un callback que devuelva un Future.
  void _recargar() => setState(_cargarCarta);

  /// El contador de la pestaña y el título del navegador siguen a los listos.
  void _alCambiarPedidos() {
    final listos = _pedidos.listos;
    if (listos != _listosEnElTitulo) {
      _listosEnElTitulo = listos;
      widget.ponerTitulo(listos);
    }
    if (mounted) setState(() {});
  }

  /// Un producto se agotó o se repuso (D-67): cambia en la misma carta, sin reiniciar la venta.
  /// Si lo marcó cocina, un aviso lo dice; va en fila detrás del que se esté mostrando, para
  /// no tapar un pedido listo. Si el cambio ya estaba (lo marcó esta pantalla), no se avisa.
  void _alCambiarDisponibilidad(Map<String, dynamic> aviso) {
    final id = aviso['id'];
    final disponible = aviso['disponible'];
    if (id is! int || disponible is! bool) return;
    final cambio = _cartaCargada?.marcarDisponibilidad(id, disponible) ?? false;
    if (!cambio || aviso['por'] != 'cocina' || !mounted) return;
    final nombre = aviso['nombre'] is String ? aviso['nombre'] as String : 'un producto';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('aviso-disponibilidad'),
        behavior: SnackBarBehavior.floating,
        width: MediaQuery.sizeOf(context).width >= anchoConPanelLateral ? 560 : null,
        duration: const Duration(seconds: 6),
        content: Text(
          disponible ? 'Cocina volvió a ofrecer: $nombre' : 'Cocina marcó agotado: $nombre',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Una categoría entera se agotó o se repuso (D-70): un solo aviso, aunque sean quince
  /// pizzas. Si fue cocina, lo dice: "Cocina marcó agotadas todas las pizzas".
  void _alCambiarCategoria(Map<String, dynamic> aviso) {
    final nombre = aviso['categoria'];
    final disponible = aviso['disponible'];
    final categoria = Categoria.values.where((c) => c.name == nombre).firstOrNull;
    if (categoria == null || disponible is! bool) return;
    final cambiados = _cartaCargada?.marcarCategoria(categoria, disponible) ?? 0;
    if (cambiados == 0 || aviso['por'] != 'cocina' || !mounted) return;
    final todas = todosLos(categoria);
    final agotadas = esFemenina(categoria) ? 'agotadas' : 'agotados';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('aviso-categoria'),
        behavior: SnackBarBehavior.floating,
        width: MediaQuery.sizeOf(context).width >= anchoConPanelLateral ? 560 : null,
        duration: const Duration(seconds: 8),
        content: Text(
          disponible ? 'Cocina volvió a ofrecer $todas' : 'Cocina marcó $agotadas $todas',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Al volver el canal después de un corte, pudo perderse un aviso: se relee la carta y se
  /// aplica solo su disponibilidad, sin reiniciar la venta.
  void _alCambiarConexion(bool conectado) {
    if (!conectado) {
      _seCorto = true;
      return;
    }
    if (!_seCorto) return;
    _seCorto = false;
    final carta = _cartaCargada;
    if (carta == null) return;
    widget.cargarCarta().then(carta.aplicarDisponibilidadDe, onError: (_) {});
  }

  void _abrirCarta() => mostrarPanelDeCarta(
    context,
    carta: _carta,
    categorias: categoriasDeRecepcion,
    marcar: widget.marcarDisponibilidad,
    marcarCategoria: widget.marcarCategoria,
  );

  /// Cocina marcó un pedido listo: suena, y un aviso lo dice con un botón para ir a verlo.
  void _alQuedarListo(Pedido pedido) {
    _timbre.sonar();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('aviso-listo'),
          behavior: SnackBarBehavior.floating,
          width: MediaQuery.sizeOf(context).width >= anchoConPanelLateral ? 560 : null,
          duration: const Duration(seconds: 10),
          backgroundColor: rojoLadrillo,
          showCloseIcon: true,
          closeIconColor: Colors.white,
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${pedido.etiqueta} de ${pedido.cliente} está listo',
                  key: const Key('texto-listo'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
          action: _pestanas.index == 1
              ? null
              : SnackBarAction(label: 'Ver pedidos', textColor: amarilloSuave, onPressed: () => _pestanas.animateTo(1)),
        ),
      );
  }

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
      // Un producto se agotó y esta pantalla no se había enterado: la carta lo marca, y la
      // línea queda señalada.
      if (error is ErrorApi && error.codigo == 'PRODUCTO_NO_DISPONIBLE') {
        final producto = error.datos['producto'];
        if (producto is Map && producto['id'] is int) {
          _cartaCargada?.marcarDisponibilidad(producto['id'] as int, false);
        }
      }
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
    final listos = _pedidos.listos;
    final activos = _pedidos.pedidos?.length ?? 0;
    // En el celular, las dos pestañas se reparten el ancho: las dos siempre a la vista.
    final angosta = MediaQuery.sizeOf(context).width < 600;
    final enLaBarra = MediaQuery.sizeOf(context).width >= EsqueletoRol.anchoPestanasEnLaBarra;
    return EsqueletoRol(
      titulo: 'Recepción',
      usuario: widget.usuario,
      alCerrarSesion: widget.alCerrarSesion,
      acciones: [BotonCarta(alTocar: _abrirCarta), BotonDeSonido(timbre: _timbre)],
      pestanas: TabBar(
        controller: _pestanas,
        isScrollable: !angosta,
        tabAlignment: angosta ? TabAlignment.fill : TabAlignment.start,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: amarilloSuave,
        indicatorWeight: 4,
        // En la barra, a la altura del título; debajo, el alto de siempre.
        indicatorSize: enLaBarra ? TabBarIndicatorSize.label : TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        tabs: [
          const Tab(
            key: Key('pestana-venta'),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text('Nueva venta')),
          ),
          Tab(
            key: const Key('pestana-pedidos'),
            // Si no cabe, se achica antes que desbordar.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(activos == 0 ? 'Pedidos' : 'Pedidos ($activos)'),
                  if (listos > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      key: const Key('contador-listos'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: amarilloSuave, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        listos == 1 ? '1 listo' : '$listos listos',
                        style: const TextStyle(color: textoSobreAmarillo, fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      cuerpo: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: _vigia,
            builder: (context, _) =>
                _vigia.mostrar ? AvisoSinConexion(alRecargar: _pedidos.leer) : const SizedBox.shrink(),
          ),
          AvisoSinSonido(timbre: _timbre),
          // Las dos pestañas quedan vivas: la venta a medio armar no se pierde al ir a entregar.
          Expanded(
            child: IndexedStack(
              index: _pestanas.index,
              children: [
                _venta(),
                PedidosDeRecepcion(
                  pedidos: _pedidos,
                  cambiarEstado: widget.cambiarEstado,
                  cancelar: widget.cancelarPedido,
                  agregar: widget.agregarAlPedido,
                  llamar: widget.llamar,
                  carta: _cartaCargada,
                  imagen: widget.imagen,
                  reloj: widget.reloj,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _venta() {
    return FutureBuilder<Carta>(
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
