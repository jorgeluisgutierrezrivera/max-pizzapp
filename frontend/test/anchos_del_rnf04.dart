// RNF-04: "interfaz adaptable verificada a 1366 px (escritorio) y 768 px (tableta), sin
// desplazamiento horizontal". Lo usan las pruebas de la venta, de los pedidos de recepción y
// de la cola de cocina (tarjeta 10, fase D). No es un archivo de pruebas: no termina en _test.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los dos tamaños del RNF-04: una computadora portátil de 1366 × 768 y una tableta vertical
/// de 768 × 1024.
const tamanosDelRnf04 = [(1366.0, 768.0), (768.0, 1024.0)];

/// Comprueba que nada se sale de la pantalla por los costados ni obliga a desplazarse de lado.
///
/// Tres cosas: que Flutter no haya reportado un desborde (en las pruebas es una excepción),
/// que ningún texto visible quede fuera del ancho de la pantalla y que nada se desplace de
/// lado. Dos cosas sí se desplazan de lado a propósito, y se dejan afuera porque no son la
/// página: la fila de extras del modal de la pizza, una tira de opciones, y cada campo de
/// texto de una línea, que corre su contenido cuando lo escrito es más largo que el campo,
/// como en cualquier formulario del navegador.
void sinDesplazamientoHorizontal(WidgetTester t, String donde) {
  expect(t.takeException(), isNull, reason: '$donde: algo se desborda');
  final ancho = t.view.physicalSize.width / t.view.devicePixelRatio;

  for (final elemento in find.byType(Scrollable).evaluate()) {
    final estado = (elemento as StatefulElement).state as ScrollableState;
    if (estado.position.axis != Axis.horizontal || _enLaTiraDeExtras(elemento)) continue;
    if (elemento.findAncestorWidgetOfExactType<EditableText>() != null) continue;
    expect(estado.position.maxScrollExtent, 0, reason: '$donde: se desplaza de lado ${_dentroDe(elemento)}');
  }

  for (final elemento in find.byType(Text).evaluate()) {
    if (_enLaTiraDeExtras(elemento)) continue;
    final caja = elemento.renderObject! as RenderBox;
    final izquierda = caja.localToGlobal(Offset.zero).dx;
    final derecha = caja.localToGlobal(caja.size.bottomRight(Offset.zero)).dx;
    final texto = (elemento.widget as Text).data ?? '(texto con estilos)';
    expect(izquierda, greaterThanOrEqualTo(-0.5), reason: '$donde: "$texto" se sale por la izquierda');
    expect(derecha, lessThanOrEqualTo(ancho + 0.5), reason: '$donde: "$texto" se sale por la derecha');
  }
}

/// El widget con clave más cercano, para que el mensaje de una falla diga dónde está.
String _dentroDe(Element elemento) {
  var donde = 'algo sin clave';
  elemento.visitAncestorElements((ancestro) {
    final clave = ancestro.widget.key;
    if (clave is ValueKey) donde = '${ancestro.widget.runtimeType} ${clave.value}';
    return clave is! ValueKey;
  });
  return donde;
}

bool _enLaTiraDeExtras(Element elemento) {
  var adentro = false;
  elemento.visitAncestorElements((ancestro) {
    adentro = ancestro.widget.key == const Key('fila-extras');
    return !adentro;
  });
  return adentro;
}
