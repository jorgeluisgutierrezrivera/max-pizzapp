import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../carta/producto.dart';
import '../../carta/venta.dart';
import '../../tema.dart';
import 'comunes.dart';

/// Ancho máximo del contenido de un paso de preguntas: en una pantalla ancha, los botones
/// no se estiran de lado a lado.
const _anchoDePregunta = 560.0;

/// Un paso de preguntas: centrado, con ancho máximo y desplazable si no cabe.
class _Centrado extends StatelessWidget {
  const _Centrado({required this.hijos});
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _anchoDePregunta),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
        ),
      ),
    );
  }
}

// --- 1. ¿Cuántas pizzas? -----------------------------------------------------------

class PasoCantidad extends StatefulWidget {
  const PasoCantidad({super.key, required this.recorrido});
  final RecorridoVenta recorrido;

  @override
  State<PasoCantidad> createState() => _PasoCantidadState();
}

class _PasoCantidadState extends State<PasoCantidad> {
  final _texto = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  int? get _valor => int.tryParse(_texto.text);

  void _poner(int valor) => setState(() {
        _texto.text = '$valor';
        _error = null;
      });

  void _continuar() {
    final valor = _valor;
    if (valor == null || valor < 1 || valor > RecorridoVenta.maximoPorTanda) {
      setState(() => _error = 'Escribe un número de 1 a ${RecorridoVenta.maximoPorTanda}.');
      return;
    }
    widget.recorrido.elegirCantidad(valor);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final valor = _valor ?? 0;
    final primeraTanda = widget.recorrido.estado.grupos.isEmpty;
    return _Centrado(hijos: [
      Pregunta(
        primeraTanda ? '¿Cuántas pizzas?' : '¿Cuántas pizzas más?',
        aclaracion: 'Todas enteras, de 1 a ${RecorridoVenta.maximoPorTanda}.',
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            key: const Key('cantidad-menos'),
            tooltip: 'Una menos',
            iconSize: 28,
            constraints: const BoxConstraints.tightFor(width: 60, height: 60),
            onPressed: valor > 1 ? () => _poner(valor - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: TextField(
              key: const Key('cantidad-texto'),
              controller: _texto,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              style: tema.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _continuar(),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(
            key: const Key('cantidad-mas'),
            tooltip: 'Una más',
            iconSize: 28,
            constraints: const BoxConstraints.tightFor(width: 60, height: 60),
            onPressed: valor < RecorridoVenta.maximoPorTanda ? () => _poner(valor + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: tema.colorScheme.error)),
        ),
      const SizedBox(height: 28),
      FilledButton(onPressed: _continuar, child: const Text('Continuar')),
      if (primeraTanda) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: widget.recorrido.soloBebidas,
          icon: const Icon(Icons.local_drink_outlined),
          label: const Text('Sin pizza, solo bebidas'),
        ),
      ],
    ]);
  }
}

// --- 2. ¿Todas iguales? --------------------------------------------------------------

class PasoIguales extends StatelessWidget {
  const PasoIguales({super.key, required this.recorrido});
  final RecorridoVenta recorrido;

  @override
  Widget build(BuildContext context) {
    final n = recorrido.estado.cantidadDelTramo;
    return _Centrado(hijos: [
      Pregunta('¿Las $n pizzas son todas iguales?', aclaracion: 'Iguales: el mismo sabor y los mismos extras.'),
      OpcionGrande(
        icono: Icons.copy_all,
        titulo: 'Sí, todas iguales',
        detalle: 'Se arma una sola vez y vale para las $n.',
        alTocar: () => recorrido.elegirIguales(true),
      ),
      const SizedBox(height: 12),
      OpcionGrande(
        icono: Icons.call_split,
        titulo: 'No, son distintas',
        detalle: 'Se arma cada una y se dice cuántas van de cada una.',
        alTocar: () => recorrido.elegirIguales(false),
      ),
    ]);
  }
}

// --- 3. ¿Un sabor o mitad y mitad? ---------------------------------------------------

class PasoTipo extends StatelessWidget {
  const PasoTipo({super.key, required this.recorrido});
  final RecorridoVenta recorrido;

  @override
  Widget build(BuildContext context) {
    final estado = recorrido.estado;
    final anterior = estado.ultimaPizza;
    final distintas = !estado.iguales && estado.cantidadDelTramo > 1;
    return _Centrado(hijos: [
      Pregunta(distintas ? '¿Cómo es la pizza ${estado.pizzaActual}?' : '¿Un solo sabor o mitad y mitad?'),
      // Desde la segunda pizza distinta: repetir la anterior con un toque.
      if (recorrido.puedeRepetirAnterior && anterior != null) ...[
        OpcionGrande(
          icono: Icons.copy_all,
          titulo: 'Igual a la pizza anterior',
          detalle: [
            anterior.titulo,
            ...anterior.extras.map((e) => '+ ${e.nombre}'),
            formatoBs(anterior.precioUnitario),
          ].join(' · '),
          alTocar: recorrido.repetirAnterior,
        ),
        const SizedBox(height: 12),
      ],
      OpcionGrande(
        icono: Icons.local_pizza_outlined,
        titulo: 'Un solo sabor',
        detalle: 'Entera, toda del mismo sabor.',
        alTocar: () => recorrido.elegirTipo(mitades: false),
      ),
      const SizedBox(height: 12),
      OpcionGrande(
        icono: Icons.contrast,
        titulo: 'Mitad y mitad',
        detalle: 'Dos medias de sabores distintos: cada una vale la mitad de su precio.',
        alTocar: () => recorrido.elegirTipo(mitades: true),
      ),
    ]);
  }
}

// --- 4. El sabor, o las dos mitades --------------------------------------------------

/// La lista de sabores, en orden alfabético y sin grupos (D-30). Cada uno con un solo
/// precio: el de la pizza, o el de su mitad si se está eligiendo una mitad.
class PasoSabor extends StatelessWidget {
  const PasoSabor({super.key, required this.recorrido, required this.imagen});
  final RecorridoVenta recorrido;
  final ConstructorImagen imagen;

  @override
  Widget build(BuildContext context) {
    final estado = recorrido.estado;
    final (String pregunta, String? aclaracion, List<Producto> sabores, bool esMitad, void Function(Producto) elegir) =
        switch (estado.paso) {
      Paso.primeraMitad => (
          'Primera mitad',
          'Cada mitad vale la mitad del precio de su pizza.',
          recorrido.carta.pizzas,
          true,
          recorrido.elegirPrimeraMitad,
        ),
      Paso.segundaMitad => (
          'Segunda mitad',
          'La primera mitad es ${estado.enCurso.sabor!.nombre}.',
          recorrido.opcionesSegundaMitad,
          true,
          recorrido.elegirSegundaMitad,
        ),
      _ => ('¿Qué sabor?', null, recorrido.carta.pizzas, false, recorrido.elegirSabor),
    };

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverToBoxAdapter(child: Pregunta(pregunta, aclaracion: aclaracion)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.64,
          ),
          itemCount: sabores.length,
          itemBuilder: (context, i) {
            final sabor = sabores[i];
            return TarjetaSabor(
              sabor: sabor,
              precio: esMitad ? sabor.precioDeMitad : sabor.precio,
              etiquetaPrecio: esMitad ? 'la mitad' : null,
              imagen: imagen,
              alTocar: sabor.disponible ? () => elegir(sabor) : null,
            );
          },
        ),
      ),
    ]);
  }
}

/// Un sabor de la carta, grande para tocarlo. Un agotado se ve atenuado y no responde.
class TarjetaSabor extends StatelessWidget {
  const TarjetaSabor({
    super.key,
    required this.sabor,
    required this.precio,
    required this.imagen,
    required this.alTocar,
    this.etiquetaPrecio,
  });

  final Producto sabor;
  final int precio;
  final String? etiquetaPrecio;
  final ConstructorImagen imagen;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final agotado = !sabor.disponible;
    return Semantics(
      button: true,
      enabled: !agotado,
      label: '${sabor.nombre}. ${agotado ? 'Agotada' : formatoBs(precio)}',
      excludeSemantics: true,
      child: Opacity(
        opacity: agotado ? 0.4 : 1,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: alTocar,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // La foto de borde a borde: es lo primero que se reconoce.
                Expanded(
                  child: ColoredBox(
                    color: colores.surfaceContainer,
                    child: IlustracionProducto(producto: sabor, imagen: imagen, ajuste: BoxFit.cover),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sabor.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 32,
                        child: Text(sabor.descripcion ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant, height: 1.2)),
                      ),
                      const SizedBox(height: 6),
                      if (agotado)
                        Text('Agotada',
                            style: tema.textTheme.titleSmall?.copyWith(color: colores.error, fontWeight: FontWeight.w700))
                      else
                        Row(
                          children: [
                            // En una tarjeta angosta, la etiqueta se achica antes que desbordar.
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: EtiquetaPrecio(formatoBs(precio)),
                              ),
                            ),
                            if (etiquetaPrecio != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(etiquetaPrecio ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant)),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- 5. Extras ---------------------------------------------------------------------

class PasoExtras extends StatefulWidget {
  const PasoExtras({super.key, required this.recorrido});
  final RecorridoVenta recorrido;

  @override
  State<PasoExtras> createState() => _PasoExtrasState();
}

class _PasoExtrasState extends State<PasoExtras> {
  final _elegidos = <Producto>{};

  /// Confirmar pizza · Confirmar pizza 2 · Confirmar las 3 pizzas
  String _confirmar(EstadoVenta e, int cuantas) {
    if (cuantas > 1) return 'Confirmar las $cuantas pizzas';
    if (e.iguales) return 'Confirmar pizza';
    return 'Confirmar pizza ${e.pizzaActual}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final pizza = widget.recorrido.pizzaConExtras(_elegidos);
    final cuantas = widget.recorrido.pizzasQueConfirma;
    return _Centrado(hijos: [
      const Pregunta('¿Algún extra?', aclaracion: 'Se puede elegir más de uno, o ninguno.'),
      _ResumenPizza(pizza: pizza),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final extra in widget.recorrido.carta.extras)
            FilterChip(
              label: Text('${extra.nombre} · ${formatoBs(extra.precio)}'),
              labelStyle: tema.textTheme.titleSmall,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              selected: _elegidos.contains(extra),
              onSelected: extra.disponible
                  ? (si) => setState(() => si ? _elegidos.add(extra) : _elegidos.remove(extra))
                  : null,
            ),
        ],
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        onPressed: () => widget.recorrido.confirmarExtras(_elegidos),
        icon: const Icon(Icons.check),
        label: Text('${_confirmar(widget.recorrido.estado, cuantas)} · ${formatoBs(pizza.precioUnitario * cuantas)}'),
      ),
    ]);
  }
}

/// La pizza que se está armando: qué es y cuánto cuesta.
class _ResumenPizza extends StatelessWidget {
  const _ResumenPizza({required this.pizza});
  final PizzaElegida pizza;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pizza.titulo, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (pizza.esMitadYMitad)
                    Text(
                      '${formatoBs(pizza.sabor.precioDeMitad)} + ${formatoBs(pizza.segundaMitad!.precioDeMitad)}',
                      style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant),
                    ),
                  for (final extra in pizza.extras)
                    Text('+ ${extra.nombre}', style: tema.textTheme.bodySmall?.copyWith(color: colores.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // En un celular angosto, el precio se achica antes que empujar el nombre fuera.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: EtiquetaPrecio(formatoBs(pizza.precioUnitario), grande: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 7. Bebidas ------------------------------------------------------------------------

class PasoBebidas extends StatelessWidget {
  const PasoBebidas({super.key, required this.recorrido, required this.imagen});
  final RecorridoVenta recorrido;
  final ConstructorImagen imagen;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vacia = recorrido.estado.vacia;
    return _Centrado(hijos: [
      const Pregunta('¿Alguna bebida?'),
      for (final bebida in recorrido.carta.bebidas)
        Opacity(
          opacity: bebida.disponible ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    SizedBox.square(dimension: 48, child: IlustracionProducto(producto: bebida, imagen: imagen)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(bebida.nombre, style: tema.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          if (bebida.disponible)
                            EtiquetaPrecio(formatoBs(bebida.precio))
                          else
                            Text('Agotada', style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.error)),
                        ],
                      ),
                    ),
                    Contador(
                      clave: 'bebida-${bebida.id}',
                      valor: recorrido.cantidadDeBebida(bebida),
                      minimo: 0,
                      maximo: bebida.disponible ? 99 : recorrido.cantidadDeBebida(bebida),
                      alCambiar: (v) => recorrido.cambiarBebida(bebida, v),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 20),
      if (vacia)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Elige al menos una bebida.',
              textAlign: TextAlign.center, style: TextStyle(color: tema.colorScheme.onSurfaceVariant)),
        ),
      FilledButton(
        onPressed: vacia ? null : recorrido.continuarDeBebidas,
        child: Text(recorrido.estado.unidadesDeBebida == 0 ? 'Sin bebidas' : 'Continuar'),
      ),
    ]);
  }
}

// --- 8. Observación ----------------------------------------------------------------

class PasoObservacion extends StatefulWidget {
  const PasoObservacion({super.key, required this.recorrido});
  final RecorridoVenta recorrido;

  @override
  State<PasoObservacion> createState() => _PasoObservacionState();
}

class _PasoObservacionState extends State<PasoObservacion> {
  late final _texto = TextEditingController(text: widget.recorrido.estado.observacion);

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Centrado(hijos: [
      const Pregunta('¿Alguna indicación para cocina?', aclaracion: 'Es opcional.'),
      TextField(
        key: const Key('observacion'),
        controller: _texto,
        maxLength: RecorridoVenta.largoObservacion,
        maxLines: 3,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Sin cebolla, bien cocida…',
          border: OutlineInputBorder(),
        ),
        onChanged: widget.recorrido.escribirObservacion,
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: widget.recorrido.continuarDeObservacion, child: const Text('Ver resumen')),
    ]);
  }
}
