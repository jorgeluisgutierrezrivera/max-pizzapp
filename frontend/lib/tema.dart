import 'package:flutter/material.dart';

/// La identidad de Max's Pizzas (D-29), tomada de su logo y de sus publicaciones.
///
/// Fondo CLARO y cálido, para que luzcan las fotos de las pizzas, con el ROJO LADRILLO en la
/// barra superior y en las acciones, y un amarillo suave en los precios. Son los colores de
/// la marca, bajados de tono: el negro, el amarillo y el rojo puros del logo quedan solo en
/// el logo. (Revisado con el autor el 24-sep: el negro de la barra y los botones desentonaba.)
/// La app no sigue el modo claro u oscuro del dispositivo: siempre se ve igual.
const negroMarca = Color(0xFF141414); // el fondo del logo
const amarilloMarca = Color(0xFFFAF126); // el amarillo del logo
const rojoMarca = Color(0xFFF90304); // el rojo de los puntos del logo y de los afiches

const rojoLadrillo = Color(0xFFC0392B); // la barra, los botones y los íconos
const rojoSuave = Color(0xFFFBE3DF); // el fondo de los íconos
const amarilloSuave = Color(0xFFFFE58A); // los precios y lo que está elegido
const textoSobreAmarillo = Color(0xFF4F3F00);
const cremaFondo = Color(0xFFFBF6EE);
const bordeSuave = Color(0xFFE8DCC8);
const textoPrincipal = Color(0xFF1B1B1B);
const textoSecundario = Color(0xFF5E574C);

/// Cómo se usa cada color, para que ninguno pierda su significado:
///   - rojo ladrillo con letra blanca: la barra superior y las acciones;
///   - amarillo suave con letra oscura: los precios y lo que está elegido;
///   - lo demás, texto oscuro sobre crema y tarjetas blancas.
ThemeData temaMaxPizzas() {
  const colores = ColorScheme(
    brightness: Brightness.light,
    primary: rojoLadrillo,
    onPrimary: Colors.white,
    primaryContainer: rojoSuave,
    onPrimaryContainer: Color(0xFF5C1A12),
    secondary: amarilloSuave,
    onSecondary: textoSobreAmarillo,
    secondaryContainer: amarilloSuave,
    onSecondaryContainer: textoSobreAmarillo,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: cremaFondo,
    onSurface: textoPrincipal,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Color(0xFFF6EFE3),
    surfaceContainerHigh: Color(0xFFF1E8DA),
    surfaceContainerHighest: Color(0xFFEADFCB),
    onSurfaceVariant: textoSecundario,
    outline: Color(0xFF8C8374),
    outlineVariant: bordeSuave,
    inverseSurface: textoPrincipal,
    onInverseSurface: cremaFondo,
    inversePrimary: rojoSuave,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  return ThemeData(
    colorScheme: colores,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: cremaFondo,
    appBarTheme: const AppBarTheme(
      backgroundColor: rojoLadrillo,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: bordeSuave),
      ),
    ),
    dividerTheme: const DividerThemeData(color: bordeSuave),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: rojoLadrillo,
        side: const BorderSide(color: rojoLadrillo, width: 1.2),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: rojoLadrillo)),
    chipTheme: const ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: amarilloSuave,
      checkmarkColor: textoSobreAmarillo,
      side: BorderSide(color: bordeSuave),
      labelStyle: TextStyle(color: textoPrincipal),
    ),
    inputDecorationTheme: const InputDecorationTheme(filled: true, fillColor: Colors.white),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: rojoLadrillo, linearTrackColor: bordeSuave),
  );
}

/// El botón que cierra algo importante, como *Terminar venta*: el rojo de las acciones, más
/// alto y con letra grande, para que se distinga de los demás.
ButtonStyle estiloBotonRojo() => FilledButton.styleFrom(
      backgroundColor: rojoLadrillo,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(56),
      textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
    );

/// Un precio en una etiqueta amarilla, como los precios de los afiches, en un amarillo suave.
class EtiquetaPrecio extends StatelessWidget {
  const EtiquetaPrecio(this.texto, {super.key, this.grande = false});

  final String texto;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: grande ? 12 : 8, vertical: grande ? 5 : 3),
      decoration: BoxDecoration(color: amarilloSuave, borderRadius: BorderRadius.circular(8)),
      child: Text(
        texto,
        style: TextStyle(
          color: textoSobreAmarillo,
          fontWeight: FontWeight.w800,
          fontSize: grande ? 20 : 15,
        ),
      ),
    );
  }
}
