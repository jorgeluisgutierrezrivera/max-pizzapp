import 'package:flutter/material.dart';

/// La identidad de Max's Pizzas (D-29), tomada de su logo y de sus publicaciones.
///
/// Tema oscuro FIJO: el local trabaja de noche, y un fondo claro encandila en el mostrador.
/// La app no sigue el modo claro u oscuro del dispositivo; siempre se ve igual.
const negroCarbon = Color(0xFF141414);
const amarilloMarca = Color(0xFFFAF126); // el amarillo del logo
const rojoMarca = Color(0xFFF90304); // el rojo de los puntos del logo y de los afiches
const blancoTexto = Color(0xFFF2F2F2);

/// Cómo se usa cada color, para que ninguno pierda su significado:
///   - amarillo, con texto negro: la acción principal de cada pantalla;
///   - rojo: solo lo que cierra una venta y los avisos que importan;
///   - todo lo demás, en grises sobre el carbón.
ThemeData temaMaxPizzas() {
  const colores = ColorScheme(
    brightness: Brightness.dark,
    primary: amarilloMarca,
    onPrimary: negroCarbon,
    primaryContainer: Color(0xFF3A3812),
    onPrimaryContainer: amarilloMarca,
    secondary: rojoMarca,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF4D1210),
    onSecondaryContainer: Color(0xFFFFDAD6),
    // El rojo de error es más claro que el de la marca: sobre el carbón, un texto en
    // #F90304 se lee con dificultad.
    error: Color(0xFFFF6B5E),
    onError: negroCarbon,
    errorContainer: Color(0xFF5C1B16),
    onErrorContainer: Color(0xFFFFDAD4),
    surface: negroCarbon,
    onSurface: blancoTexto,
    surfaceContainerLowest: Color(0xFF0B0B0B),
    surfaceContainerLow: Color(0xFF1B1B1B),
    surfaceContainer: Color(0xFF212121),
    surfaceContainerHigh: Color(0xFF292929),
    surfaceContainerHighest: Color(0xFF323232),
    onSurfaceVariant: Color(0xFFB8B8B8),
    outline: Color(0xFF6E6E6E),
    outlineVariant: Color(0xFF383838),
    inverseSurface: blancoTexto,
    onInverseSurface: negroCarbon,
    inversePrimary: Color(0xFF6B6700),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  return ThemeData(
    colorScheme: colores,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: negroCarbon,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0B0B0B),
      foregroundColor: blancoTexto,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: blancoTexto),
    ),
    cardTheme: const CardThemeData(color: Color(0xFF1B1B1B), surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: Color(0xFF383838)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: amarilloMarca,
        side: const BorderSide(color: amarilloMarca),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: amarilloMarca),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: amarilloMarca),
  );
}

/// El botón que cierra algo importante, como *Terminar venta*: rojo de la marca con texto
/// blanco y letra grande, que así se lee bien (contraste para texto grande).
ButtonStyle estiloBotonRojo() => FilledButton.styleFrom(
      backgroundColor: rojoMarca,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(56),
      textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
    );
