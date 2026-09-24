// La identidad visual de Max's Pizzas (D-29): el tema, el logo y que los colores se lean.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxpizzapp/api/usuario.dart';
import 'package:maxpizzapp/carta/producto.dart';
import 'package:maxpizzapp/pantallas/pantalla_acceso.dart';
import 'package:maxpizzapp/pantallas/segun_rol.dart';
import 'package:maxpizzapp/tema.dart';

/// Contraste entre dos colores, con la fórmula de WCAG 2: de 1 (iguales) a 21 (negro y
/// blanco). 4,5 es el mínimo para texto normal; 3, para texto grande.
double contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
  return (claro + 0.05) / (oscuro + 0.05);
}

final logo = find.bySemanticsLabel("Logo de Max's Pizzas");

void main() {
  final tema = temaMaxPizzas();
  final colores = tema.colorScheme;

  group('el tema', () {
    test('es claro, con el negro, el amarillo y el rojo del logo', () {
      expect(colores.brightness, Brightness.light);
      expect(colores.primary, negroMarca);
      expect(colores.onPrimary, amarilloMarca);
      expect(colores.surface, cremaFondo);
      expect(tema.scaffoldBackgroundColor, cremaFondo);
      expect(tema.appBarTheme.backgroundColor, negroMarca);
      expect(amarilloMarca, const Color(0xFFFAF126));
      expect(rojoMarca, const Color(0xFFF90304));
    });

    test('el texto sobre el crema y sobre las tarjetas blancas se lee de sobra (al menos 7 a 1)', () {
      expect(contraste(colores.onSurface, colores.surface), greaterThanOrEqualTo(7));
      expect(contraste(colores.onSurface, Colors.white), greaterThanOrEqualTo(7));
    });

    test('la letra amarilla sobre el botón negro, y los precios negros sobre amarillo, también', () {
      expect(contraste(colores.onPrimary, colores.primary), greaterThanOrEqualTo(7));
      expect(contraste(negroMarca, amarilloMarca), greaterThanOrEqualTo(7));
    });

    test('la barra superior negra: título blanco y nombre en blanco atenuado', () {
      expect(contraste(Colors.white, negroMarca), greaterThanOrEqualTo(7));
      expect(contraste(Colors.white70, negroMarca), greaterThanOrEqualTo(4.5));
    });

    test('el texto secundario y los errores cumplen el mínimo para texto normal', () {
      expect(contraste(colores.onSurfaceVariant, colores.surface), greaterThanOrEqualTo(4.5));
      expect(contraste(colores.error, colores.surface), greaterThanOrEqualTo(4.5));
      expect(contraste(colores.onErrorContainer, colores.errorContainer), greaterThanOrEqualTo(4.5));
    });

    test('el botón rojo lleva texto blanco grande, que así cumple el mínimo', () {
      final estilo = estiloBotonRojo();
      final fondo = estilo.backgroundColor!.resolve({})!;
      final texto = estilo.foregroundColor!.resolve({})!;
      final letra = estilo.textStyle!.resolve({})!;
      expect(contraste(texto, fondo), greaterThanOrEqualTo(3));
      // Texto grande según WCAG: 14 pt en negrita, es decir unos 18,7 px.
      expect(letra.fontSize, greaterThanOrEqualTo(18.7));
      expect(letra.fontWeight, FontWeight.w700);
    });
  });

  group('el logo', () {
    testWidgets('en la pantalla de acceso, con el nombre del local', (t) async {
      await t.pumpWidget(MaterialApp(theme: tema, home: const PantallaAcceso()));
      await t.pumpAndSettle();
      expect(logo, findsOneWidget);
      expect(find.text("Max's Pizzas · Villa Fátima, Tarija"), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('en la barra de cada rol', (t) async {
      for (final rol in ['recepcion', 'cocina']) {
        final usuario = Usuario.desdeJson({'sub': 'x', 'nombre': 'Ana', 'usuario': 'a', 'roles': [rol]});
        await t.pumpWidget(MaterialApp(
          theme: tema,
          home: PantallaSegunRol(
            cargarUsuario: () async => usuario,
            cargarCarta: () async => Carta(const []),
            alCerrarSesion: () {},
          ),
        ));
        await t.pumpAndSettle();
        expect(find.descendant(of: find.byType(AppBar), matching: logo), findsOneWidget);
      }
    });

    testWidgets('la pantalla de acceso cabe en un celular angosto', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: tema, home: const PantallaAcceso(mensaje: 'Tu sesión expiró.')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
