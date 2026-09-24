import 'package:flutter/material.dart';

/// El logo de Max's Pizzas, usado con autorización del local (D-29).
///
/// Va incluido en la app (assets/marca/), no se descarga aparte: aparece en el primer
/// cuadro, aunque la red esté lenta.
class LogoMaxPizzas extends StatelessWidget {
  const LogoMaxPizzas({super.key, this.tamano = 32});

  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/marca/logo-mp.png',
      width: tamano,
      height: tamano,
      semanticLabel: "Logo de Max's Pizzas",
      filterQuality: FilterQuality.medium,
    );
  }
}
