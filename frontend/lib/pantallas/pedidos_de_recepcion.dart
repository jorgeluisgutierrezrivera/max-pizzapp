import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/cliente_api.dart';
import '../carta/producto.dart';
import '../pedidos/pedido.dart';
import '../pedidos/pedidos_en_vivo.dart';
import '../tema.dart';
import 'venta/comunes.dart';
import 'venta/modal_agregar.dart';

/// Los motivos más comunes de una cancelación: un toque en vez de escribir (D-33).
const motivosDeCancelacion = ['El cliente se fue', 'El cliente cambió de idea', 'Error al tomar el pedido'];

/// La pestaña *Pedidos* de recepción (RF-03, RF-04, RF-05, RF-09, RF-14): los pedidos en
/// cocina y los listos, en vivo. Los listos van primero y resaltados: son los que hay que
/// entregar.
///
/// - Listo: *Entregar*, *Llamar* si dio celular, y *Agregar* bebidas.
/// - En cocina: *Agregar* (pizzas o bebidas) y *Cancelar*, con motivo.
///
/// Quien decide si una acción vale es el servidor: si otro dispositivo cambió el pedido
/// antes, responde 409, se avisa y la lista se vuelve a leer.
class PedidosDeRecepcion extends StatefulWidget {
  const PedidosDeRecepcion({
    super.key,
    required this.pedidos,
    required this.cambiarEstado,
    required this.cancelar,
    required this.agregar,
    required this.llamar,
    required this.carta,
    required this.imagen,
    this.reloj = DateTime.now,
  });

  final PedidosEnVivo pedidos;

  /// PATCH /api/v1/pedidos/:id/estado, con la versión que se ve.
  final Future<Pedido> Function(Pedido pedido, EstadoPedido hacia) cambiarEstado;

  /// POST /api/v1/pedidos/:id/cancelacion.
  final Future<Pedido> Function(Pedido pedido, String motivo) cancelar;

  /// POST /api/v1/pedidos/:id/lineas.
  final Future<Pedido> Function(Pedido pedido, Map<String, dynamic> cuerpo) agregar;

  /// Abre el marcador del teléfono con ese número.
  final void Function(String numero) llamar;

  /// Para *Agregar*: nula mientras no cargó.
  final Carta? carta;
  final ConstructorImagen imagen;
  final DateTime Function() reloj;

  @override
  State<PedidosDeRecepcion> createState() => _PedidosDeRecepcionState();
}

class _PedidosDeRecepcionState extends State<PedidosDeRecepcion> {
  /// Los que tienen una acción viajando al servidor: sus botones esperan.
  final Set<int> _enCamino = {};

  /// Lo que salió mal o conviene decir, hasta que se cierra.
  String? _aviso;
  Timer? _minutero;

  @override
  void initState() {
    super.initState();
    // Cada 30 s se redibuja "hace N min".
    _minutero = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minutero?.cancel();
    super.dispose();
  }

  void _confirmar(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: MediaQuery.sizeOf(context).width >= 700 ? 520 : null,
          duration: const Duration(seconds: 4),
          showCloseIcon: true,
          content: Text(texto, key: const Key('aviso-pedidos')),
        ),
      );
  }

  /// Hace la acción con el botón del pedido esperando. Si el servidor dice que el pedido ya
  /// había cambiado, se avisa y se relee la lista.
  Future<void> _conPedido(Pedido pedido, Future<void> Function() accion) async {
    setState(() {
      _enCamino.add(pedido.id);
      _aviso = null;
    });
    try {
      await accion();
    } on ErrorApi catch (error) {
      if (!mounted) return;
      if (error.codigo == 'PEDIDO_CAMBIADO') {
        setState(() => _aviso = 'Al ${pedido.etiqueta} se le agregó algo. Revísalo antes de entregarlo.');
        await widget.pedidos.leer();
      } else if (error.estado == 409 || error.estado == 404) {
        setState(() => _aviso = 'El ${pedido.etiqueta} ya había cambiado. La lista se actualizó.');
        await widget.pedidos.leer();
      } else {
        setState(() => _aviso = error.mensaje);
      }
    } finally {
      if (mounted) setState(() => _enCamino.remove(pedido.id));
    }
  }

  Future<void> _entregar(Pedido pedido) => _conPedido(pedido, () async {
    final quedo = await widget.cambiarEstado(pedido, EstadoPedido.entregado);
    widget.pedidos.reemplazar(quedo);
    if (mounted) _confirmar('${pedido.etiqueta} de ${pedido.cliente} entregado.');
  });

  Future<void> _cancelar(Pedido pedido) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) => _DialogoCancelar(pedido: pedido),
    );
    if (motivo == null || !mounted) return;
    await _conPedido(pedido, () async {
      final quedo = await widget.cancelar(pedido, motivo);
      widget.pedidos.reemplazar(quedo);
      if (mounted) _confirmar('${pedido.etiqueta} cancelado: $motivo.');
    });
  }

  Future<void> _llamar(Pedido pedido) => showDialog<void>(
    context: context,
    builder: (context) => _DialogoLlamar(pedido: pedido, llamar: widget.llamar),
  );

  Future<void> _agregar(Pedido pedido) async {
    final carta = widget.carta;
    if (carta == null) return;
    final quedo = await mostrarAgregado(
      context,
      pedido: pedido,
      carta: carta,
      imagen: widget.imagen,
      agregar: (cuerpo) => widget.agregar(pedido, cuerpo),
    );
    if (quedo == null || !mounted) return;
    widget.pedidos.reemplazar(quedo);
    _confirmar('Se agregó al ${pedido.etiqueta}. Nuevo total: ${formatoBs(quedo.total)}.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pedidos,
      builder: (context, _) {
        final vivos = widget.pedidos;
        if (vivos.pedidos == null && vivos.error == null) {
          return const _Centro(icono: null, texto: 'Cargando los pedidos…');
        }
        if (vivos.pedidos == null) {
          final error = vivos.error;
          return _Centro(
            icono: Icons.error_outline,
            esError: true,
            texto: error is ErrorApi ? error.mensaje : 'No se pudieron cargar los pedidos.',
            alReintentar: vivos.leer,
          );
        }
        final ordenados = vivos.ordenados;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Resumen(total: ordenados.length, listos: vivos.listos, conectado: vivos.conectado),
            if (_aviso != null) _Aviso(texto: _aviso!, alCerrar: () => setState(() => _aviso = null)),
            Expanded(
              child: ordenados.isEmpty
                  ? const _Centro(
                      icono: Icons.receipt_long_outlined,
                      texto:
                          'No hay pedidos por atender.\nLos que envíes a cocina aparecen aquí, y suenan cuando están listos.',
                    )
                  : RefreshIndicator(
                      onRefresh: vivos.leer,
                      child: LayoutBuilder(
                        builder: (context, lados) {
                          const margen = 16.0;
                          const separacion = 16.0;
                          final util = lados.maxWidth - 2 * margen;
                          final columnas = (util / 360).floor().clamp(1, 5);
                          final ancho = (util - separacion * (columnas - 1)) / columnas;
                          return SingleChildScrollView(
                            key: const Key('lista-pedidos'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(margen, 8, margen, 24),
                            child: Wrap(
                              spacing: separacion,
                              runSpacing: separacion,
                              children: [
                                for (final pedido in ordenados)
                                  SizedBox(
                                    width: ancho,
                                    child: TarjetaDeRecepcion(
                                      pedido: pedido,
                                      ahora: widget.reloj(),
                                      enCamino: _enCamino.contains(pedido.id),
                                      puedeAgregar: widget.carta != null,
                                      alEntregar: () => _entregar(pedido),
                                      alCancelar: () => _cancelar(pedido),
                                      alLlamar: () => _llamar(pedido),
                                      alAgregar: () => _agregar(pedido),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Arriba: cuántos hay, cuántos listos y si el canal en vivo está conectado.
class _Resumen extends StatelessWidget {
  const _Resumen({required this.total, required this.listos, required this.conectado});
  final int total;
  final int listos;
  final bool conectado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: total == 1 ? '1 pedido por atender' : '$total pedidos por atender'),
                  if (listos > 0)
                    TextSpan(
                      text: listos == 1 ? ' · 1 listo para entregar' : ' · $listos listos para entregar',
                      style: const TextStyle(color: rojoLadrillo),
                    ),
                ],
              ),
              key: const Key('resumen-pedidos'),
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
            key: const Key('estado-canal-recepcion'),
            style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Un pedido por atender: qué lleva, para quién, en qué va y lo que se puede hacer con él.
class TarjetaDeRecepcion extends StatelessWidget {
  const TarjetaDeRecepcion({
    super.key,
    required this.pedido,
    required this.ahora,
    required this.enCamino,
    required this.puedeAgregar,
    required this.alEntregar,
    required this.alCancelar,
    required this.alLlamar,
    required this.alAgregar,
  });

  final Pedido pedido;
  final DateTime ahora;
  final bool enCamino;
  final bool puedeAgregar;
  final VoidCallback alEntregar;
  final VoidCallback alCancelar;
  final VoidCallback alLlamar;
  final VoidCallback alAgregar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final listo = pedido.estado == EstadoPedido.listo;
    final id = pedido.id;
    final celular = pedido.celular;
    return Card(
      key: Key('recepcion-pedido-$id'),
      margin: EdgeInsets.zero,
      // El listo resalta: es el que hay que entregar.
      color: listo ? const Color(0xFFFFF7D6) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: listo ? rojoLadrillo : bordeSuave, width: listo ? 3 : 1),
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
                  pedido.numero == null ? '#$id' : '${pedido.numero}',
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
                        '– ${pedido.paraLlevar ? 'Para llevar' : 'Para comer aquí'}',
                        style: tema.textTheme.bodyMedium?.copyWith(color: colores.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _ChipEstado(estado: pedido.estado, clave: 'estado-$id'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [haceCuanto(pedido.creadoEn, ahora), ?celular].join(' · '),
              style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
            ),
            const Divider(height: 20),
            for (final linea in pedido.pizzas)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  [
                    '${linea.cantidad} × ${linea.titulo}',
                    for (final e in linea.extras) '+ ${e.nombre}',
                    if (linea.agregada) '(agregada ${horaCorta(linea.agregadoEn!)})',
                  ].join('  '),
                  style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            for (final linea in pedido.otros)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${linea.cantidad} × ${linea.titulo}${linea.agregada ? '  (agregada ${horaCorta(linea.agregadoEn!)})' : ''}',
                  style: tema.textTheme.bodyMedium?.copyWith(color: colores.onSurfaceVariant),
                ),
              ),
            if (pedido.observacion != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '«${pedido.observacion}»',
                  style: tema.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colores.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Total', style: tema.textTheme.titleSmall),
                const SizedBox(width: 8),
                EtiquetaPrecio(formatoBs(pedido.total)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (listo) ...[
                  FilledButton.icon(
                    key: Key('entregar-$id'),
                    style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
                    onPressed: enCamino ? null : alEntregar,
                    icon: const Icon(Icons.check),
                    label: const Text('Entregar'),
                  ),
                  if (celular != null)
                    OutlinedButton.icon(
                      key: Key('llamar-$id'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: alLlamar,
                      icon: const Icon(Icons.phone),
                      label: const Text('Llamar'),
                    ),
                ],
                OutlinedButton.icon(
                  key: Key('agregar-$id'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: enCamino || !puedeAgregar ? null : alAgregar,
                  icon: const Icon(Icons.add),
                  label: Text(listo ? 'Agregar bebida' : 'Agregar'),
                ),
                if (!listo)
                  TextButton.icon(
                    key: Key('cancelar-$id'),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: colores.error),
                    onPressed: enCamino ? null : alCancelar,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.estado, required this.clave});
  final EstadoPedido estado;
  final String clave;

  @override
  Widget build(BuildContext context) {
    final (Color fondo, Color letra, IconData icono) = switch (estado) {
      EstadoPedido.listo => (rojoLadrillo, Colors.white, Icons.notifications_active),
      EstadoPedido.enPreparacion => (amarilloSuave, textoSobreAmarillo, Icons.local_fire_department),
      _ => (rojoSuave, const Color(0xFF7A2219), Icons.schedule),
    };
    return Container(
      key: Key(clave),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: letra),
          const SizedBox(width: 4),
          Text(
            estado.etiqueta,
            style: TextStyle(color: letra, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// ¿Por qué se cancela? Los motivos comunes con un toque, u otro escrito (D-33).
class _DialogoCancelar extends StatefulWidget {
  const _DialogoCancelar({required this.pedido});
  final Pedido pedido;

  @override
  State<_DialogoCancelar> createState() => _DialogoCancelarState();
}

class _DialogoCancelarState extends State<_DialogoCancelar> {
  String? _elegido;
  final _otro = TextEditingController();

  @override
  void dispose() {
    _otro.dispose();
    super.dispose();
  }

  String get _motivo => (_elegido ?? _otro.text).trim();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return AlertDialog(
      title: Text('Cancelar el ${widget.pedido.etiqueta}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¿Por qué se cancela? Queda anotado en el pedido.', style: tema.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, motivo) in motivosDeCancelacion.indexed)
                  ChoiceChip(
                    key: Key('motivo-$i'),
                    label: Text(motivo),
                    selected: _elegido == motivo,
                    onSelected: (si) => setState(() => _elegido = si ? motivo : null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('motivo-otro'),
              controller: _otro,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Otro motivo', border: OutlineInputBorder()),
              onChanged: (_) => setState(() => _elegido = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver')),
        FilledButton(
          key: const Key('confirmar-cancelacion'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: tema.colorScheme.error),
          onPressed: _motivo.isEmpty ? null : () => Navigator.of(context).pop(_motivo),
          child: const Text('Cancelar pedido'),
        ),
      ],
    );
  }
}

/// El número para llamar: grande, para leerlo y marcarlo, con *Copiar* y *Llamar*, que en el
/// celular abre el marcador.
class _DialogoLlamar extends StatelessWidget {
  const _DialogoLlamar({required this.pedido, required this.llamar});
  final Pedido pedido;
  final void Function(String numero) llamar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final numero = pedido.celular!;
    return AlertDialog(
      title: Text('Llamar a ${pedido.cliente}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${pedido.etiqueta} · listo para entregar', style: tema.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SelectableText(
            numero,
            key: const Key('numero-a-llamar'),
            style: tema.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          key: const Key('copiar-numero'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: numero));
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
        ),
        FilledButton.icon(
          key: const Key('marcar-numero'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            llamar(numero);
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.phone),
          label: const Text('Llamar'),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.alCerrar});
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
                  key: const Key('aviso-recepcion'),
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
  final Future<void> Function()? alReintentar;
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
