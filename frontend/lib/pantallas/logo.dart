import 'package:flutter/material.dart';

import '../tema.dart';

/// El logo de Max's Pizzas, usado con autorización del local (D-29).
///
/// Va sobre un círculo negro, como en el original: amarillo sobre un fondo claro no se lee.
/// Va incluido en la app (assets/marca/), no se descarga aparte: aparece en el primer
/// cuadro, aunque la red esté lenta.
class LogoMaxPizzas extends StatelessWidget {
  const LogoMaxPizzas({super.key, this.tamano = 32});

  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      padding: EdgeInsets.all(tamano * 0.1),
      decoration: const BoxDecoration(color: negroMarca, shape: BoxShape.circle),
      child: Image.asset(
        'assets/marca/logo-mp.png',
        semanticLabel: "Logo de Max's Pizzas",
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
