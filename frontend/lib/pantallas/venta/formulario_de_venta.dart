import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../carta/producto.dart';
import '../../carta/venta.dart';
import '../../tema.dart';
import 'comunes.dart';
import 'modal_bebidas.dart';
import 'modal_pizza.dart';

/// Desde este ancho, el pedido con el total va a la derecha del formulario; por debajo (el
/// celular, la tableta vertical), una barra fija abajo con el total y *Confirmar venta*.
const anchoConPanelLateral = 900.0;

/// En una pantalla muy ancha, la venta no se estira más que esto: el resto queda de margen.
const anchoMaximoDeVenta = 1280.0;

/// Desde este alto, en la computadora, el formulario ocupa la pantalla entera sin
/// desplazarse: el cliente arriba, las bebidas abajo y las pizzas en el medio, estirándose.
/// Si se agregan tantas pizzas que no caben, se desplaza solo la lista de pizzas.
const altoParaLlenar = 520.0;

/// Por debajo de este alto, los campos y las tarjetas se ajustan un poco para caber.
const altoComodo = 640.0;

/// La venta en una sola pantalla (D-36), leída en F: arriba el cliente y "comer aquí o para
/// llevar"; debajo, las pizzas y las bebidas; y a la derecha, lo último que se mira: el
/// pedido, la observación para cocina, el total y *Confirmar venta*.
///
/// En la computadora, el formulario ocupa toda la pantalla, sin desplazarse. En el celular
/// se desplaza, con el total y *Confirmar* siempre abajo; al enviar o cancelar, vuelve arriba.
class FormularioDeVenta extends StatefulWidget {
  const FormularioDeVenta({
    super.key,
    required this.formulario,
    required this.imagen,
    required this.alConfirmar,
    required this.alVenderBebidas,
    this.enviando = false,
    this.errorDeEnvio,
  });

  final FormularioVenta formulario;
  final ConstructorImagen imagen;

  /// Nulo si no hay cómo enviar: el botón se ve, deshabilitado.
  final VoidCallback? alConfirmar;
  final VoidCallback? alVenderBebidas;

  /// Mientras la venta viaja al servidor, y lo que salió mal si no llegó.
  final bool enviando;
  final String? errorDeEnvio;

  @override
  State<FormularioDeVenta> createState() => _FormularioDeVentaState();
}

class _FormularioDeVentaState extends State<FormularioDeVenta> {
  final _nombre = TextEditingController();
  final _celular = TextEditingController();
  final _observacion = TextEditingController();
  final _desplazamiento = ScrollController();

  /// Los problemas se muestran recién después de tocar *Confirmar*: antes serían regaños
  /// sobre algo que la vendedora todavía no terminó de escribir.
  bool _intentado = false;
  bool _estabaVacia = true;

  FormularioVenta get _f => widget.formulario;

  @override
  void initState() {
    super.initState();
    _f.addListener(_sincronizar);
  }

  @override
  void didUpdateWidget(FormularioDeVenta anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.formulario != widget.formulario) {
      anterior.formulario.removeListener(_sincronizar);
      widget.formulario.addListener(_sincronizar);
      _sincronizar();
    }
  }

  @override
  void dispose() {
    _f.removeListener(_sincronizar);
    _nombre.dispose();
    _celular.dispose();
    _observacion.dispose();
    _desplazamiento.dispose();
    super.dispose();
  }

  /// Si la venta se limpió (se envió o se canceló), los campos también, y el formulario
  /// vuelve arriba, listo para el siguiente cliente.
  void _sincronizar() {
    if (_nombre.text != _f.nombre) _nombre.text = _f.nombre;
    if (_celular.text != _f.celular) _celular.text = _f.celular;
    if (_observacion.text != _f.observacion) _observacion.text = _f.observacion;
    final vacia = _f.vacia;
    if (vacia) {
      _intentado = false;
      if (!_estabaVacia && _desplazamiento.hasClients) {
        _desplazamiento.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    }
    _estabaVacia = vacia;
    setState(() {});
  }

  void _confirmar() {
    if (_f.problemas.isNotEmpty) {
      setState(() => _intentado = true);
      return;
    }
    widget.alConfirmar?.call();
  }

  Future<void> _agregarPizza() async {
    final r = await mostrarModalPizza(context, carta: _f.carta, imagen: widget.imagen);
    if (r != null && !r.quitada) _f.agregarPizza(r.pizza!, r.cantidad);
  }

  Future<void> _corregirPizza(int indice) async {
    final grupo = _f.grupos[indice];
    final r = await mostrarModalPizza(
      context,
      carta: _f.carta,
      imagen: widget.imagen,
      desde: grupo.pizza,
      cantidad: grupo.cantidad,
    );
    if (r == null) return;
    if (r.quitada) {
      _f.quitarPizza(indice);
    } else {
      _f.reemplazarPizza(indice, r.pizza!, r.cantidad);
    }
  }

  Future<void> _cancelarVenta() async {
    final si = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar la venta?'),
        content: const Text('Se borra todo lo que se anotó.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Seguir con la venta')),
          TextButton(
            key: const Key('confirmar-cancelar'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar la venta'),
          ),
        ],
      ),
    );
    if (si == true) _f.limpiar();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, lados) {
        final lateral = lados.maxWidth >= anchoConPanelLateral;
        final llenar = lateral && lados.maxHeight >= altoParaLlenar;
        final denso = lateral && lados.maxHeight < altoComodo;
        final problemas = _intentado ? _f.problemas : const <String>[];
        final observacion = _CampoObservacion(formulario: _f, controlador: _observacion, denso: denso);
        final separacion = SizedBox(height: denso ? 10 : 16);
        final cliente = _SeccionCliente(
          formulario: _f,
          nombre: _nombre,
          celular: _celular,
          marcarNombre: _intentado && _f.nombre.trim().isEmpty,
          marcarLlevar: _intentado && _f.paraLlevar == null,
          alVenderBebidas: widget.alVenderBebidas,
          denso: denso,
        );
        final pizzas = _SeccionPizzas(
          formulario: _f,
          marcar: _intentado && _f.grupos.isEmpty,
          alAgregar: _agregarPizza,
          alCorregir: _corregirPizza,
          llenar: llenar,
          denso: denso,
        );
        final bebidas = _SeccionBebidas(formulario: _f, imagen: widget.imagen, denso: denso);
        final Widget secciones = llenar
            // La pantalla entera, sin desplazarse: las pizzas ocupan el alto que sobra.
            ? Padding(
                key: const Key('formulario-venta'),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    cliente,
                    separacion,
                    Expanded(child: pizzas),
                    separacion,
                    bebidas,
                  ],
                ),
              )
            : ListView(
                key: const Key('formulario-venta'),
                controller: _desplazamiento,
                padding: EdgeInsets.fromLTRB(lateral ? 0 : 12, 12, lateral ? 0 : 12, 12),
                children: [
                  cliente,
                  separacion,
                  pizzas,
                  separacion,
                  bebidas,
                  // En el celular, la observación va al final del formulario; en la computadora,
                  // en el pedido, justo antes de confirmar.
                  if (!lateral) ...[
                    separacion,
                    Seccion(titulo: '4 · Observación para cocina', hijos: [observacion]),
                  ],
                ],
              );
        final confirmar = _BotonConfirmar(
          total: _f.total,
          enviando: widget.enviando,
          alConfirmar: widget.alConfirmar == null || widget.enviando ? null : _confirmar,
        );
        final alCancelar = _f.vacia || widget.enviando ? null : _cancelarVenta;

        if (!lateral) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: secciones),
              _BarraInferior(
                formulario: _f,
                problemas: problemas,
                errorDeEnvio: widget.errorDeEnvio,
                confirmar: confirmar,
                alCancelar: alCancelar,
              ),
            ],
          );
        }
        // En una pantalla ancha, todo en un contenedor centrado: el formulario y el pedido quedan
        // juntos, y el pedido es una tarjeta al lado, fija si el formulario se desplaza.
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: anchoMaximoDeVenta),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: secciones),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 380,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: llenar ? 16 : 12),
                      child: PanelPedido(
                        formulario: _f,
                        problemas: problemas,
                        errorDeEnvio: widget.errorDeEnvio,
                        observacion: observacion,
                        confirmar: confirmar,
                        alCancelar: alCancelar,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- 1. El cliente ------------------------------------------------------------------------

class _SeccionCliente extends StatelessWidget {
  const _SeccionCliente({
    required this.formulario,
    required this.nombre,
    required this.celular,
    required this.marcarNombre,
    required this.marcarLlevar,
    required this.alVenderBebidas,
    required this.denso,
  });

  final FormularioVenta formulario;
  final TextEditingController nombre;
  final TextEditingController celular;
  final bool marcarNombre;
  final bool marcarLlevar;
  final VoidCallback? alVenderBebidas;
  final bool denso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final paraLlevar = formulario.paraLlevar;
    final celularEscrito = formulario.celular.trim();
    final campoNombre = TextField(
      key: const Key('cliente-nombre'),
      controller: nombre,
      maxLength: FormularioVenta.largoNombre,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Nombre del cliente',
        isDense: denso,
        border: const OutlineInputBorder(),
        counterText: '',
        errorText: marcarNombre ? 'Con este nombre se anuncia el pedido.' : null,
      ),
      onChanged: formulario.escribirNombre,
    );
    final campoCelular = TextField(
      key: const Key('cliente-celular'),
      controller: celular,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
      decoration: InputDecoration(
        labelText: 'Celular (opcional)',
        isDense: denso,
        border: const OutlineInputBorder(),
        // Para llevar es cuando más sirve: si el cliente se va, se lo llama al estar listo.
        helperText: paraLlevar == true && celularEscrito.isEmpty ? 'Conviene pedirlo, para avisarle.' : null,
        errorText: celularEscrito.length == 8 && !celularValido.hasMatch(celularEscrito) ? 'Empieza con 6 o 7.' : null,
      ),
      onChanged: formulario.escribirCelular,
    );
    return Seccion(
      titulo: '1 · Cliente',
      denso: denso,
      // La primera decisión del mostrador: ¿es un pedido a nombre de alguien, o solo una
      // soda al paso? La venta directa no pide nada de lo de abajo (D-38).
      accion: OutlinedButton.icon(
        key: const Key('vender-bebidas'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        onPressed: alVenderBebidas,
        icon: const Icon(Icons.local_drink_outlined, size: 18),
        label: const Text('Vender bebidas'),
      ),
      hijos: [
        LayoutBuilder(
          builder: (context, lados) => lados.maxWidth >= 520
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: campoNombre),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: campoCelular),
                  ],
                )
              : Column(children: [campoNombre, const SizedBox(height: 10), campoCelular]),
        ),
        SizedBox(height: denso ? 10 : 16),
        Text(
          '¿Para comer aquí o para llevar?',
          style: tema.textTheme.titleSmall?.copyWith(color: marcarLlevar ? tema.colorScheme.error : null),
        ),
        SizedBox(height: denso ? 6 : 8),
        // Las dos del mismo alto, aunque una ocupe dos renglones en el celular.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: BotonEleccion(
                  key: const Key('comer-aqui'),
                  icono: Icons.restaurant,
                  texto: 'Para comer aquí',
                  elegido: paraLlevar == false,
                  alTocar: () => formulario.elegirParaLlevar(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BotonEleccion(
                  key: const Key('para-llevar'),
                  icono: Icons.takeout_dining,
                  texto: 'Para llevar',
                  elegido: paraLlevar == true,
                  alTocar: () => formulario.elegirParaLlevar(true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- 2. Las pizzas -------------------------------------------------------------------------

class _SeccionPizzas extends StatelessWidget {
  const _SeccionPizzas({
    required this.formulario,
    required this.marcar,
    required this.alAgregar,
    required this.alCorregir,
    required this.llenar,
    required this.denso,
  });

  final FormularioVenta formulario;
  final bool marcar;
  final VoidCallback alAgregar;
  final ValueChanged<int> alCorregir;

  /// Ocupa el alto que le den, con su propia lista, y el botón siempre a la vista abajo.
  final bool llenar;
  final bool denso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final grupos = formulario.grupos;
    final lineas = [
      for (final (i, g) in grupos.indexed)
        _LineaPizza(
          key: Key('pizza-$i'),
          indice: i,
          grupo: g,
          alCambiarCantidad: (n) => formulario.cambiarCantidadDeGrupo(i, n),
          alCorregir: () => alCorregir(i),
        ),
    ];
    final boton = SizedBox(
      height: denso ? 44 : 52,
      child: OutlinedButton.icon(
        key: const Key('agregar-pizza'),
        onPressed: alAgregar,
        icon: const Icon(Icons.add),
        label: Text(grupos.isEmpty ? 'Agregar pizza' : 'Agregar otra pizza'),
      ),
    );
    final falta = Text('Un pedido lleva al menos una pizza.', style: TextStyle(color: tema.colorScheme.error));

    if (!llenar) {
      return Seccion(
        titulo: '2 · Pizzas',
        denso: denso,
        hijos: [
          if (grupos.isEmpty && marcar) Padding(padding: const EdgeInsets.only(bottom: 8), child: falta),
          ...lineas,
          boton,
        ],
      );
    }
    return Seccion(
      titulo: '2 · Pizzas',
      denso: denso,
      hijos: [
        Expanded(
          child: grupos.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_pizza_outlined, size: denso ? 32 : 44, color: tema.colorScheme.outline),
                        const SizedBox(height: 6),
                        if (marcar)
                          falta
                        else
                          Text(
                            'Todavía no hay pizzas.',
                            style: tema.textTheme.titleSmall?.copyWith(color: textoSecundario),
                          ),
                        Text(
                          'Entera o mitad y mitad, con sus extras.',
                          style: tema.textTheme.bodySmall?.copyWith(color: textoSecundario),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(key: const Key('lista-pizzas'), children: lineas),
        ),
        const SizedBox(height: 8),
        boton,
      ],
    );
  }
}

/// Una línea de pizzas: − n +, qué es (tocarla la abre para corregirla) y cuánto suma.
class _LineaPizza extends StatelessWidget {
  const _LineaPizza({
    super.key,
    required this.indice,
    required this.grupo,
    required this.alCambiarCantidad,
    required this.alCorregir,
  });

  final int indice;
  final GrupoPizzas grupo;
  final ValueChanged<int> alCambiarCantidad;
  final VoidCallback alCorregir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final pizza = grupo.pizza;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bordeSuave),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Contador(
            clave: 'pizza-$indice',
            valor: grupo.cantidad,
            minimo: 0,
            maximo: maximoPorLinea,
            denso: MediaQuery.sizeOf(context).width < 420,
            alCambiar: alCambiarCantidad,
          ),
          Expanded(
            child: InkWell(
              key: Key('corregir-pizza-$indice'),
              onTap: alCorregir,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pizza.titulo, style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          for (final extra in pizza.extras)
                            Text(
                              '+ ${extra.nombre}',
                              style: tema.textTheme.bodySmall?.copyWith(color: textoSecundario),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // En un celular angosto, el precio se achica antes que desbordar la línea.
                    Flexible(
                      child: FittedBox(fit: BoxFit.scaleDown, child: EtiquetaPrecio(formatoBs(grupo.subtotal))),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, size: 18, color: textoSecundario),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- 3. Las bebidas ------------------------------------------------------------------------

class _SeccionBebidas extends StatelessWidget {
  const _SeccionBebidas({required this.formulario, required this.imagen, required this.denso});
  final FormularioVenta formulario;
  final ConstructorImagen imagen;
  final bool denso;

  @override
  Widget build(BuildContext context) {
    final bebidas = formulario.carta.bebidas;
    return Seccion(
      titulo: '3 · Bebidas',
      denso: denso,
      hijos: [
        if (bebidas.isEmpty) const Text('La carta no tiene bebidas.', style: TextStyle(color: textoSecundario)),
        LayoutBuilder(
          builder: (context, lados) {
            final columnas = lados.maxWidth >= 720 ? 3 : (lados.maxWidth >= 440 ? 2 : 1);
            final ancho = (lados.maxWidth - (columnas - 1) * 12) / columnas;
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final bebida in bebidas)
                  SizedBox(
                    width: ancho,
                    child: FilaBebida(
                      bebida: bebida,
                      imagen: imagen,
                      cantidad: formulario.cantidadDeBebida(bebida),
                      clave: 'bebida-${bebida.id}',
                      // Siempre compacta: van tres en una línea, y el nombre necesita el ancho.
                      denso: true,
                      alCambiar: (v) => formulario.cambiarBebida(bebida, v),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// --- La observación ------------------------------------------------------------------------

class _CampoObservacion extends StatelessWidget {
  const _CampoObservacion({required this.formulario, required this.controlador, required this.denso});
  final FormularioVenta formulario;
  final TextEditingController controlador;
  final bool denso;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('observacion'),
      controller: controlador,
      maxLength: FormularioVenta.largoObservacion,
      minLines: 1,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'Observación para cocina',
        hintText: 'Sin cebolla, bien cocida… (opcional)',
        isDense: denso,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      onChanged: formulario.escribirObservacion,
    );
  }
}

// --- El pedido y el botón de confirmar -----------------------------------------------------

class _BotonConfirmar extends StatelessWidget {
  const _BotonConfirmar({required this.total, required this.enviando, required this.alConfirmar});

  final int total;
  final bool enviando;
  final VoidCallback? alConfirmar;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const Key('confirmar-venta'),
      style: estiloBotonRojo(),
      onPressed: alConfirmar,
      icon: enviando
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : const Icon(Icons.send),
      label: Text(enviando ? 'Enviando a cocina…' : 'Confirmar venta · ${formatoBs(total)}'),
    );
  }
}

/// Lo que falta para confirmar, y el error del envío si no llegó.
class _Avisos extends StatelessWidget {
  const _Avisos({required this.problemas, required this.errorDeEnvio});
  final List<String> problemas;
  final String? errorDeEnvio;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorDeEnvio != null)
          Card(
            key: const Key('error-envio'),
            color: tema.colorScheme.errorContainer,
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(errorDeEnvio!, style: TextStyle(color: tema.colorScheme.onErrorContainer)),
            ),
          ),
        if (problemas.isNotEmpty)
          Padding(
            key: const Key('problemas'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in problemas)
                  Text(
                    '• $p',
                    style: TextStyle(color: tema.colorScheme.error, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// El pedido, a la derecha en una pantalla ancha: a nombre de quién (con su celular, si lo
/// dio) y si es para llevar; cada línea con su precio; la observación para cocina; el total
/// y *Confirmar venta*.
class PanelPedido extends StatelessWidget {
  const PanelPedido({
    super.key,
    required this.formulario,
    required this.problemas,
    required this.errorDeEnvio,
    required this.observacion,
    required this.confirmar,
    required this.alCancelar,
  });

  final FormularioVenta formulario;
  final List<String> problemas;
  final String? errorDeEnvio;
  final Widget observacion;
  final Widget confirmar;
  final VoidCallback? alCancelar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final f = formulario;
    final nombre = f.nombre.trim();
    final celular = f.celular.trim();
    Widget linea(String texto, int centavos, {String? detalle}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: tema.textTheme.bodyLarge),
                if (detalle != null) Text(detalle, style: tema.textTheme.bodySmall?.copyWith(color: textoSecundario)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatoBs(centavos), style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return Card(
      key: const Key('panel-pedido'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: rojoSuave,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedido', style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                // El nombre y, al lado, el celular si lo dio; debajo, si es para llevar.
                Text(
                  nombre.isEmpty ? 'Sin nombre todavía' : [nombre, if (celular.isNotEmpty) celular].join(' · '),
                  key: const Key('cliente-resumen'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: nombre.isEmpty ? textoSecundario : textoPrincipal,
                  ),
                ),
                Text(
                  switch (f.paraLlevar) {
                    true => '– Para llevar',
                    false => '– Para comer aquí',
                    null => '– Sin elegir si es para comer aquí o para llevar',
                  },
                  key: const Key('llevar-resumen'),
                  style: tema.textTheme.bodyMedium?.copyWith(color: textoSecundario),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                if (f.grupos.isEmpty && f.bebidas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aún no hay nada en el pedido.', style: TextStyle(color: textoSecundario)),
                  ),
                for (final g in f.grupos)
                  linea(
                    '${g.cantidad} × ${g.pizza.titulo}',
                    g.subtotal,
                    detalle: g.pizza.extras.isEmpty ? null : g.pizza.extras.map((e) => '+ ${e.nombre}').join('  '),
                  ),
                for (final b in f.bebidas) linea('${b.cantidad} × ${b.bebida.nombre}', b.subtotal),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                observacion,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: Text('Total', style: tema.textTheme.titleLarge)),
                    Text(
                      formatoBs(f.total),
                      key: const Key('total-venta'),
                      style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _Avisos(problemas: problemas, errorDeEnvio: errorDeEnvio),
                confirmar,
                // El lugar queda reservado aunque no haya nada que cancelar: así el panel no
                // cambia de alto al empezar una venta.
                SizedBox(
                  height: 40,
                  child: alCancelar == null
                      ? null
                      : TextButton(
                          key: const Key('cancelar-venta'),
                          onPressed: alCancelar,
                          child: const Text('Cancelar venta'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// En el celular: el total y *Confirmar venta*, siempre a la vista, abajo.
class _BarraInferior extends StatelessWidget {
  const _BarraInferior({
    required this.formulario,
    required this.problemas,
    required this.errorDeEnvio,
    required this.confirmar,
    required this.alCancelar,
  });

  final FormularioVenta formulario;
  final List<String> problemas;
  final String? errorDeEnvio;
  final Widget confirmar;
  final VoidCallback? alCancelar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final bebidas = formulario.bebidas.fold(0, (s, b) => s + b.cantidad);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: bordeSuave)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Avisos(problemas: problemas, errorDeEnvio: errorDeEnvio),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formulario.unidadesDePizza} pizza${formulario.unidadesDePizza == 1 ? '' : 's'}'
                    '${bebidas == 0 ? '' : ' · $bebidas bebida${bebidas == 1 ? '' : 's'}'}',
                    style: tema.textTheme.bodyMedium?.copyWith(color: textoSecundario),
                  ),
                ),
                if (alCancelar != null)
                  IconButton(
                    key: const Key('cancelar-venta'),
                    tooltip: 'Cancelar venta',
                    color: rojoLadrillo,
                    onPressed: alCancelar,
                    icon: const Icon(Icons.delete_outline),
                  ),
                const SizedBox(width: 8),
                Text(
                  formatoBs(formulario.total),
                  key: const Key('total-venta'),
                  style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            confirmar,
          ],
        ),
      ),
    );
  }
}
