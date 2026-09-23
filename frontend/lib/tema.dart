import 'package:flutter/material.dart';

/// El rojo de la marca, el mismo de la pagina de cortesia y del manifiesto.
const colorMarca = Color(0xFFC0392B);

ThemeData temaClaro() => _tema(Brightness.light);
ThemeData temaOscuro() => _tema(Brightness.dark);

ThemeData _tema(Brightness brillo) {
  final colores = ColorScheme.fromSeed(seedColor: colorMarca, brightness: brillo);
  return ThemeData(
    colorScheme: colores,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
