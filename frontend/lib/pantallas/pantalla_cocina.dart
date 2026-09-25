import 'dart:async';

import 'package:flutter/material.dart';

import '../api/canal_en_vivo.dart';
import '../api/cliente_api.dart';
import '../api/usuario.dart';
import '../pedidos/pedido.dart';
import '../tema.dart';
import 'boton_de_sonido.dart';
import 'esqueleto_rol.dart';
import 'timbre.dart';

/// La cola de cocina (RF-06, RF-07): los pedidos por preparar, en orden de llegada, que
/// aparecen solos cuando recepción termina una venta.
///
/// Cada pedido es una tarjeta grande con un solo botón: *Empezar* y, después, *Listo*.
/// Cuando un pedido queda listo, sale de la cola: lo entrega recepción.
///
/// La lista la da la API; el canal en vivo solo avisa. Si la conexión se corta y vuelve, la
/// lista se vuelve a leer: mientras estuvo cortada pudo perderse algún aviso.
///
/// Cada pedido se canta con su número del día (D-35). Lo que recepción agrega a un pedido
/// en cocina aparece marcado y suena (D-37); y al avanzar un pedido se manda la versión que
/// se tiene a la vista, para que nadie lo marque listo sin haber visto lo último.
class PantallaCocina extends StatefulWidget {
  const PantallaCocina({
    super.key,
    required this.usuario,
    required this.alCerrarSesion,
    required this.cargarCola,
    required this.cambiarEstado,
    required this.crearCanal,
    required this.timbre,
    this.reloj = DateTime.now,
  });

  final Usuario usuario;
  final VoidCallback alCerrarSesion;

  /// GET /api/v1/pedidos?estado=pendiente,en_preparacion
  final Future<List<Pedido>> Function() cargarCola;

  /// PATCH /api/v1/pedidos/:id/estado, con la versión del pedido que se ve. Devuelve el
  /// pedido como quedó.
  final Future<Pedido> Function(Pedido pedido, EstadoPedido hacia) cambiarEstado;
  final CanalEnVivo Function() crearCanal;
  final Timbre timbre;
  final DateTime Function() reloj;

  @override
  State<PantallaCocina> createState() => _PantallaCocinaState();
}

class _PantallaCocinaState extends State<PantallaCocina> {
  late final CanalEnVivo _canal = widget.crearCanal();
  final List<StreamSubscription<dynamic>> _suscripciones = [];
  Timer? _minutero;
  final List<Timer> _marcas = [];

  List<Pedido>? _cola;
  Object? _error;
  bool _conectado = false;

  /// Los que tienen un cambio viajando al servidor: su botón espera.
  final Set<int> _enCamino = {};

  /// Los recién llegados por el canal: llevan la marca "Nuevo" un rato.
  final Set<int> _nuevos = {};

  /// A los que recepción les acaba de agregar algo: llevan la marca "Se agregó" un rato.
  final Set<int> _conAgregado = {};

  /// Lo último que pasó y conviene decir: una cancelación, un cambio que otro hizo antes.
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _suscripciones
      ..add(_canal.pedidosNuevos.listen(_alLlegarPedido))
      ..add(_canal.cambiosDeEstado.listen(_alCambiarEstado))
      ..add(_canal.pedidosActualizados.listen(_alActualizarPedido))
      ..add(_canal.conexion.listen(_alCambiarConexion));
    _canal.conectar();
    _cargar();
    // Cada 30 s se redibuja "hace N min".
    _minutero = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minutero?.cancel();
    for (final m in _marcas) {
      m.cancel();
    }
    for (final s in _suscripciones) {
      s.cancel();
    }
    _canal.cerrar();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final cola = await widget.cargarCola();
      if (!mounted) return;
      setState(() => _cola = [...cola]..sort(_porLlegada));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  static int _porLlegada(Pedido a, Pedido b) {
    final c = a.creadoEn.compareTo(b.creadoEn);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  void _alLlegarPedido(Map<String, dynamic> json) {
    final pedido = Pedido.desdeJson(json);
    final cola = _cola;
    // Si la cola todavía no cargó, el pedido ya va a venir en ella.
    if (cola == null || !pedido.estado.enCocina || cola.any((p) => p.id == pedido.id)) return;
    widget.timbre.sonar();
    setState(() {
      _cola = [...cola, pedido]..sort(_porLlegada);
      _nuevos.add(pedido.id);
    });
    _marcas.add(
      Timer(const Duration(minutes: 1), () {
        if (mounted) setState(() => _nuevos.remove(pedido.id));
      }),
    );
  }

  /// Recepción le agregó algo a un pedido (D-37): la tarjeta se reemplaza, se marca y suena,
  /// porque puede haber una pizza más que preparar.
  void _alActualizarPedido(Map<String, dynamic> json) {
    final pedido = Pedido.desdeJson(json);
    final cola = _cola;
    if (cola == null) return;
    final i = cola.indexWhere((p) => p.id == pedido.id);
    if (i < 0 || !pedido.estado.enCocina) return;
    widget.timbre.sonar();
    setState(() {
      _cola = [...cola]..[i] = pedido;
      _conAgregado.add(pedido.id);
    });
    _marcas.add(
      Timer(const Duration(minutes: 1), () {
        if (mounted) setState(() => _conAgregado.remove(pedido.id));
      }),
    );
  }

  void _alCambiarEstado(Map<String, dynamic> aviso) {
    final cola = _cola;
    if (cola == null) return;
    final id = aviso['id'] as int;
    final nuevo = EstadoPedido.desdeApi(aviso['nuevo'] as String);
    final i = cola.indexWhere((p) => p.id == id);
    if (i < 0) return;
    setState(() {
      if (nuevo.enCocina) {
        _cola = [...cola]..[i] = cola[i].conEstado(nuevo);
      } else {
        _cola = [...cola]..removeAt(i);
        // Que se cancele un pedido en preparación es algo que cocina tiene que saber ya.
        if (nuevo == EstadoPedido.cancelado) {
          _aviso = 'Recepción canceló el ${cola[i].etiqueta} de ${cola[i].cliente}.';
        }
      }
    });
  }

  void _alCambiarConexion(bool conectado) {
    setState(() => _conectado = conectado);
    if (conectado) _cargar(); // al volver, ponerse al día con la API
  }

  Future<void> _avanzar(Pedido pedido) async {
    final hacia = pedido.estado == EstadoPedido.pendiente ? EstadoPedido.enPreparacion : EstadoPedido.listo;
    setState(() {
      _enCamino.add(pedido.id);
      _aviso = null;
    });
    try {
      final quedo = await widget.cambiarEstado(pedido, hacia);
      if (!mounted) return;
      setState(() {
        final cola = [...?_cola];
        final i = cola.indexWhere((p) => p.id == pedido.id);
        if (i >= 0) {
          if (quedo.estado.enCocina) {
            cola[i] = quedo;
          } else {
            cola.removeAt(i);
          }
        }
        _cola = cola;
      });
    } on ErrorApi catch (error) {
      if (!mounted) return;
      if (error.codigo == 'PEDIDO_CAMBIADO') {
        // Recepción le agregó algo que esta pantalla todavía no mostraba: se relee y se
        // avisa, para revisarlo antes de marcarlo listo.
        setState(() => _aviso = 'Al ${pedido.etiqueta} se le agregó algo. Revísalo antes de marcarlo listo.');
        await _cargar();
      } else if (error.estado == 409 || error.estado == 404) {
        // Otro dispositivo lo cambió antes, o recepción lo canceló: se relee la cola.
        setState(() => _aviso = 'El ${pedido.etiqueta} ya había cambiado. La cola se actualizó.');
        await _cargar();
      } else {
        setState(() => _aviso = error.mensaje);
      }
    } finally {
      if (mounted) setState(() => _enCamino.remove(pedido.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return EsqueletoRol(
      titulo: 'Cocina',
      usuario: widget.usuario,
      alCerrarSesion: widget.alCerrarSesion,
      acciones: [BotonDeSonido(timbre: widget.timbre)],
      cuerpo: _cuerpo(context),
    );
  }

  Widget _cuerpo(BuildContext context) {
    final cola = _cola;
    if (cola == null && _error == null) {
      return const _Centro(icono: null, texto: 'Cargando la cola…');
    }
    if (cola == null) {
      final error = _error;
      return _Centro(
        icono: Icons.error_outline,
        esError: true,
        texto: error is ErrorApi ? error.mensaje : 'No se pudo cargar la cola de pedidos.',
        alReintentar: _cargar,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Estado(cantidad: cola.length, conectado: _conectado),
        if (_aviso != null) _AvisoCocina(texto: _aviso!, alCerrar: () => setState(() => _aviso = null)),
        Expanded(
          child: cola.isEmpty
              ? const _Centro(
                  icono: Icons.soup_kitchen_outlined,
                  texto: 'No hay pedidos en cocina.\nLos nuevos aparecen aquí solos, en orden de llegada.',
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: _Tablero(
                    cola: cola,
                    ahora: widget.reloj(),
                    enCamino: _enCamino,
                    nuevos: _nuevos,
                    conAgregado: _conAgregado,
                    alAvanzar: _avanzar,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Arriba: cuántos pedidos hay y si el canal en vivo está conectado.
class _Estado extends StatelessWidget {
  const _Estado({required this.cantidad, required this.conectado});
  final int cantidad;
  final bool conectado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              cantidad == 1 ? '1 pedido en cocina' : '$cantidad pedidos en cocina',
              key: const Key('cantidad-cola'),
              style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: conectado ? const Color(0xFF2E9E5B) : const Color(0xFFD9A400),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            conectado ? 'En vivo' : 'Conectando…',
            key: const Key('estado-canal'),
            style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Los pedidos en tarjetas, en orden de llegada: de izquierda a derecha y de arriba abajo.
/// En una pantalla ancha (el monitor de cocina) van varias columnas; en el celular, una.
class _Tablero extends StatelessWidget {
  const _Tablero({
    required this.cola,
    required this.ahora,
    required this.enCamino,
    required this.nuevos,
    required this.conAgregado,
    required this.alAvanzar,
  });

  final List<Pedido> cola;
  final DateTime ahora;
  final Set<int> enCamino;
  final Set<int> nuevos;
  final Set<int> conAgregado;
  final void Function(Pedido) alAvanzar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, lados) {
        const margen = 16.0;
        const separacion = 16.0;
        final util = lados.maxWidth - 2 * margen;
        final columnas = (util / 360).floor().clamp(1, 6);
        final ancho = (util - separacion * (columnas - 1)) / columnas;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(margen, 8, margen, 24),
          child: Wrap(
            spacing: separacion,
            runSpacing: separacion,
            children: [
              for (final pedido in cola)
                SizedBox(
                  width: ancho,
                  child: TarjetaDeCocina(
                    pedido: pedido,
                    ahora: ahora,
                    nuevo: nuevos.contains(pedido.id),
                    conAgregado: conAgregado.contains(pedido.id),
                    enCamino: enCamino.contains(pedido.id),
                    alAvanzar: () => alAvanzar(pedido),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Un pedido en la cola: qué hay que preparar, para quién y un solo botón.
class TarjetaDeCocina extends StatelessWidget {
  const TarjetaDeCocina({
    super.key,
    required this.pedido,
    required this.ahora,
    required this.nuevo,
    required this.enCamino,
    required this.alAvanzar,
    this.conAgregado = false,
  });

  final Pedido pedido;
  final DateTime ahora;
  final bool nuevo;
  final bool conAgregado;
  final bool enCamino;
  final VoidCallback alAvanzar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final enPreparacion = pedido.estado == EstadoPedido.enPreparacion;
    return Card(
      key: Key('pedido-${pedido.id}'),
      margin: EdgeInsets.zero,
      // El que ya se está preparando lleva el borde rojo: se ve de lejos qué está en marcha.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: enPreparacion ? rojoLadrillo : bordeSuave, width: enPreparacion ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pedido.numero == null ? '#${pedido.id}' : '${pedido.numero}',
                  key: Key('numero-${pedido.id}'),
                  style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: rojoLadrillo),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pedido.cliente,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        haceCuanto(pedido.creadoEn, ahora),
                        key: Key('hace-${pedido.id}'),
                        style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (nuevo) const _Chip(texto: 'Nuevo', fondo: amarilloSuave, letra: textoSobreAmarillo),
                if (conAgregado && !nuevo)
                  const _Chip(texto: 'Se agregó algo', fondo: amarilloSuave, letra: textoSobreAmarillo),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  texto: pedido.paraLlevar ? 'Para llevar' : 'Para comer aquí',
                  icono: pedido.paraLlevar ? Icons.takeout_dining : Icons.restaurant,
                  fondo: rojoSuave,
                  letra: const Color(0xFF7A2219),
                ),
                if (enPreparacion)
                  const _Chip(texto: 'En preparación', fondo: amarilloSuave, letra: textoSobreAmarillo),
              ],
            ),
            const Divider(height: 24),
            for (final linea in pedido.pizzas) _LineaDeCocina(linea: linea),
            if (pedido.otros.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                pedido.otros
                    .map(
                      (l) =>
                          '${l.cantidad} × ${l.titulo}${l.agregada ? ' (agregada ${horaCorta(l.agregadoEn!)})' : ''}',
                    )
                    .join(' · '),
                style: tema.textTheme.bodyMedium?.copyWith(color: colores.onSurfaceVariant),
              ),
            ],
            if (pedido.observacion != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: amarilloSuave, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sticky_note_2_outlined, size: 18, color: textoSobreAmarillo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pedido.observacion!,
                        style: const TextStyle(color: textoSobreAmarillo, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (enPreparacion)
              FilledButton.icon(
                onPressed: enCamino ? null : alAvanzar,
                icon: const Icon(Icons.check),
                label: const Text('Listo'),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: enCamino ? null : alAvanzar,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Empezar'),
              ),
          ],
        ),
      ),
    );
  }
}

/// "2 × Mitad Salame / mitad Peperoni", con sus extras debajo.
class _LineaDeCocina extends StatelessWidget {
  const _LineaDeCocina({required this.linea});
  final LineaDePedido linea;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lo que recepción agregó después (D-37) va marcado con su hora: el cocinero puede
          // haber leído la tarjeta antes.
          if (linea.agregada)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _Chip(
                texto: 'Agregada ${horaCorta(linea.agregadoEn!)}',
                icono: Icons.add_circle_outline,
                fondo: amarilloSuave,
                letra: textoSobreAmarillo,
              ),
            ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${linea.cantidad} × ',
                  style: const TextStyle(color: rojoLadrillo),
                ),
                TextSpan(text: linea.titulo),
              ],
            ),
            style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          for (final extra in linea.extras)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text('+ ${extra.nombre}', style: tema.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.fondo, required this.letra, this.icono});
  final String texto;
  final Color fondo;
  final Color letra;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 16, color: letra), const SizedBox(width: 4)],
          Text(
            texto,
            style: TextStyle(color: letra, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Un aviso que se queda hasta que la persona lo cierra: una cancelación no se puede perder
/// porque desaparezca sola.
class _AvisoCocina extends StatelessWidget {
  const _AvisoCocina({required this.texto, required this.alCerrar});
  final String texto;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: colores.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colores.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  key: const Key('aviso-cocina'),
                  style: TextStyle(color: colores.onErrorContainer, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(tooltip: 'Cerrar aviso', onPressed: alCerrar, icon: const Icon(Icons.close)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Centro extends StatelessWidget {
  const _Centro({required this.icono, required this.texto, this.alReintentar, this.esError = false});
  final IconData? icono;
  final String texto;
  final VoidCallback? alReintentar;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono == null)
              const CircularProgressIndicator()
            else
              Icon(icono, size: 56, color: esError ? tema.colorScheme.error : tema.colorScheme.outline),
            const SizedBox(height: 16),
            Text(texto, textAlign: TextAlign.center, style: tema.textTheme.bodyLarge),
            if (alReintentar != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
                onPressed: alReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
