#!/usr/bin/env python3
"""
Dibuja las ilustraciones de las bebidas de la carta en frontend/web/carta/.

Las pizzas ya no se dibujan: usan las fotos del local (scripts/preparar-fotos.py). Sus
dibujos provisorios quedaron en el historial, en el commit que cargó la carta real.

POR QUÉ UN SCRIPT Y NO IMÁGENES DESCARGADAS
  Las ilustraciones se dibujaron para el proyecto: formas simples (círculos,
  polígonos, trazos) combinadas en capas. Así no hay derechos de terceros de por
  medio, cualquiera puede regenerarlas, y cambiar un color o agregar un producto
  es editar una línea. Cuando lleguen las fotos reales de las bebidas, este script deja
  de hacer falta.

CÓMO SE USA (desde la raíz del repositorio)
  pip install pillow==12.3.0
  python scripts/dibujar-carta.py

  El resultado es el mismo en cada ejecución: los dibujos no usan azar.

CÓMO SE DIBUJA
  Todo se describe en un lienzo de 600 × 600 unidades, se pinta 4 veces más
  grande y al final se reduce: así los bordes quedan suaves. El fondo es
  transparente, para que la tarjeta de la app ponga el suyo.
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

LADO = 600          # tamaño final, en píxeles
K = 4               # factor de sobremuestreo
C = LADO / 2        # centro del lienzo

DESTINO = Path(__file__).resolve().parent.parent / "frontend" / "web" / "carta"



# ---------------------------------------------------------------------------
# El lienzo y las primitivas (todas reciben coordenadas en unidades de 600)
# ---------------------------------------------------------------------------

class Lienzo:
    def __init__(self):
        self.img = Image.new("RGBA", (LADO * K, LADO * K), (0, 0, 0, 0))

    def capa(self):
        capa = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        return capa, ImageDraw.Draw(capa)

    def pegar(self, capa, desenfoque=0):
        if desenfoque:
            capa = capa.filter(ImageFilter.GaussianBlur(desenfoque * K))
        self.img = Image.alpha_composite(self.img, capa)

    def guardar(self, ruta):
        final = self.img.resize((LADO, LADO), Image.LANCZOS)
        # 256 colores con transparencia: la ilustración es plana y el archivo
        # queda en una fracción del tamaño.
        final = final.quantize(256, method=Image.Quantize.FASTOCTREE)
        final.save(ruta, optimize=True)


def _caja(x, y, rx, ry):
    return [(x - rx) * K, (y - ry) * K, (x + rx) * K, (y + ry) * K]


def circulo(d, x, y, r, relleno=None, borde=None, ancho=0):
    d.ellipse(_caja(x, y, r, r), fill=relleno, outline=borde, width=round(ancho * K))


def elipse(d, x, y, rx, ry, relleno=None, borde=None, ancho=0):
    d.ellipse(_caja(x, y, rx, ry), fill=relleno, outline=borde, width=round(ancho * K))


def poligono(d, puntos, relleno):
    d.polygon([(x * K, y * K) for x, y in puntos], fill=relleno)


def trazo(d, puntos, color, ancho):
    """Una línea gruesa con las puntas redondeadas."""
    d.line([(x * K, y * K) for x, y in puntos], fill=color,
           width=max(1, round(ancho * K)), joint="curve")
    for x, y in (puntos[0], puntos[-1]):
        circulo(d, x, y, ancho / 2, color)


def arco(d, x, y, r, desde, hasta, color, ancho):
    d.arc(_caja(x, y, r, r), desde, hasta, fill=color, width=round(ancho * K))


def girar(puntos, cx, cy, angulo):
    c, s = math.cos(angulo), math.sin(angulo)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c)
            for x, y in puntos]


def recortar(capa, puntos):
    """Deja visible de la capa solo lo que cae dentro del polígono."""
    mascara = Image.new("L", capa.size, 0)
    ImageDraw.Draw(mascara).polygon([(x * K, y * K) for x, y in puntos], fill=255)
    capa.putalpha(ImageChops.multiply(capa.getchannel("A"), mascara))
    return capa


def perfil(tramos, cx=C, paso=1.5):
    """Contorno simétrico de un envase a partir de pares (altura, semiancho)."""
    izquierda, derecha = [], []
    for (y0, w0), (y1, w1) in zip(tramos, tramos[1:]):
        pasos = max(2, int(abs(y1 - y0) / paso))
        for i in range(pasos):
            t = i / pasos
            suave = t * t * (3 - 2 * t)
            y, w = y0 + (y1 - y0) * t, w0 + (w1 - w0) * suave
            izquierda.append((cx - w, y))
            derecha.append((cx + w, y))
    y, w = tramos[-1]
    izquierda.append((cx - w, y))
    derecha.append((cx + w, y))
    return izquierda + derecha[::-1]


def sombra_suelo(lz, x, y, rx, ry=13):
    capa, d = lz.capa()
    elipse(d, x, y, rx, ry, (40, 30, 20, 90))
    lz.pegar(capa, desenfoque=6)


def botella(nombre, tramos, nivel, liquido, plastico, filo, tapa, etiqueta, dibujar_etiqueta):
    lz = Lienzo()
    y_tapa, semiancho_tapa = tramos[0][0], tramos[0][1] + 8
    sombra_suelo(lz, C, tramos[-1][0] + 2, tramos[-2][1] + 8)
    contorno = perfil(tramos)

    capa, d = lz.capa()
    poligono(d, contorno, plastico)
    lz.pegar(capa)

    capa, d = lz.capa()
    poligono(d, contorno, liquido)
    d.rectangle([0, 0, LADO * K, nivel * K], fill=(0, 0, 0, 0))
    lz.pegar(capa)

    capa, d = lz.capa()
    y0, y1 = etiqueta
    d.rectangle([0, y0 * K, LADO * K, y1 * K], fill=dibujar_etiqueta["color"])
    dibujar_etiqueta["dibujo"](d, y0, y1)
    lz.pegar(recortar(capa, contorno))

    capa, d = lz.capa()
    d.line([(x * K, y * K) for x, y in contorno + [contorno[0]]], fill=filo, width=round(2.2 * K), joint="curve")
    lz.pegar(capa)

    # Brillo vertical: da la idea de plástico.
    capa, d = lz.capa()
    ancho = tramos[-2][1]
    d.rounded_rectangle([(C - ancho * 0.72) * K, (tramos[2][0] + 12) * K,
                         (C - ancho * 0.52) * K, (tramos[-2][0] - 14) * K],
                        radius=6 * K, fill=(255, 255, 255, 80))
    lz.pegar(recortar(capa, contorno))

    # Tapa con estrías y el anillo del cuello.
    capa, d = lz.capa()
    d.rounded_rectangle([(C - semiancho_tapa) * K, (y_tapa - 42) * K,
                         (C + semiancho_tapa) * K, (y_tapa - 6) * K], radius=5 * K, fill=tapa)
    oscuro = tuple(max(0, v - 35) for v in tapa[:3])
    for i in range(1, 9):
        x = C - semiancho_tapa + i * (2 * semiancho_tapa) / 9
        trazo(d, [(x, y_tapa - 36), (x, y_tapa - 12)], oscuro, 1.6)
    d.rectangle([(C - semiancho_tapa - 3) * K, (y_tapa - 7) * K,
                 (C + semiancho_tapa + 3) * K, (y_tapa + 1) * K], fill=oscuro)
    lz.pegar(capa)
    lz.guardar(DESTINO / nombre)


def ola(d, y, color, ancho, amplitud=8, fase=0.0):
    trazo(d, [(x, y + amplitud * math.sin(x * 0.04 + fase)) for x in range(80, 521, 4)], color, ancho)


def gaseosa():
    botella(
        "gaseosa.png",
        tramos=[(118, 36), (150, 38), (238, 106), (500, 106), (532, 100), (548, 86)],
        nivel=178, liquido=(66, 30, 18), plastico=(214, 224, 232, 120),
        filo=(140, 150, 160), tapa=(36, 128, 76), etiqueta=(300, 402),
        dibujar_etiqueta={"color": (36, 128, 76), "dibujo": burbujas},
    )


def burbujas(d, y0, y1):
    """Etiqueta genérica: dos franjas y burbujas. Ninguna marca real."""
    for y in (y0 + 14, y1 - 14):
        trazo(d, [(80, y), (520, y)], (250, 214, 80), 4)
    for x, y, r in [(236, 348, 13), (268, 336, 8), (300, 356, 17), (334, 340, 10),
                    (362, 360, 7), (254, 368, 6), (320, 372, 5)]:
        circulo(d, x, y, r, borde=(255, 255, 255), ancho=3)


def agua_mineral():
    def gota(d, y0, y1):
        ola(d, y1 - 22, (255, 255, 255), 5, 6, 1.0)
        cy = (y0 + y1) / 2 - 8
        puntos = [(C + 16 * math.sin(t) * (1 - math.cos(t)) / 1.3,
                   cy - 18 + 18 * (1 - math.cos(t)))
                  for t in [i * 2 * math.pi / 40 for i in range(41)]]
        poligono(d, puntos, (255, 255, 255))

    botella(
        "agua-mineral.png",
        tramos=[(150, 27), (175, 29), (240, 80), (320, 80), (355, 73), (390, 80),
                (518, 80), (536, 75), (548, 64)],
        nivel=196, liquido=(150, 206, 236, 150), plastico=(226, 238, 246, 120),
        filo=(128, 168, 196), tapa=(40, 110, 186), etiqueta=(400, 484),
        dibujar_etiqueta={"color": (70, 150, 214), "dibujo": gota},
    )


def jugo_natural():
    lz = Lienzo()
    sombra_suelo(lz, C + 10, 548, 175)
    cx = C + 30
    contorno = perfil([(160, 112), (172, 114), (505, 142), (530, 134), (544, 116)], cx)

    capa, d = lz.capa()
    arco(d, cx + 128, 318, 92, 280, 440, (196, 218, 232, 230), 22)     # asa
    lz.pegar(capa)

    capa, d = lz.capa()
    poligono(d, [(cx - 110, 162), (cx - 158, 138), (cx - 96, 186)], (214, 230, 240, 200))  # pico
    poligono(d, contorno, (226, 238, 246, 130))
    lz.pegar(capa)

    capa, d = lz.capa()
    poligono(d, contorno, (245, 150, 34))
    d.rectangle([0, 0, LADO * K, 214 * K], fill=(0, 0, 0, 0))
    elipse(d, cx, 214, 120, 11, (251, 186, 80))
    lz.pegar(recortar(capa, contorno))

    capa, d = lz.capa()
    d.line([(x * K, y * K) for x, y in contorno + [contorno[0]]],
           fill=(132, 166, 188), width=round(2.4 * K), joint="curve")
    elipse(d, cx, 162, 112, 10, borde=(132, 166, 188), ancho=2.4)
    d.rounded_rectangle([(cx - 92) * K, 232 * K, (cx - 74) * K, 486 * K],
                        radius=6 * K, fill=(255, 255, 255, 85))
    lz.pegar(capa)

    # Una rodaja de naranja delante.
    capa, d = lz.capa()
    circulo(d, 160 + 4, 468 + 8, 96, (40, 30, 20, 90))
    lz.pegar(capa, desenfoque=5)
    capa, d = lz.capa()
    x, y = 160, 468
    circulo(d, x, y, 96, (238, 128, 20))
    circulo(d, x, y, 88, (252, 236, 204))
    circulo(d, x, y, 81, (248, 162, 42))
    for i in range(10):
        a = math.radians(i * 36)
        d.pieslice(_caja(x, y, 74, 74), i * 36 + 4, (i + 1) * 36 - 4, fill=(252, 192, 84))
        trazo(d, [(x, y), (x + 80 * math.cos(a), y + 80 * math.sin(a))], (252, 236, 204), 3)
    circulo(d, x, y, 9, (252, 236, 204))
    lz.pegar(capa)
    lz.guardar(DESTINO / "jugo-natural.png")


# ---------------------------------------------------------------------------

def main():
    DESTINO.mkdir(parents=True, exist_ok=True)
    gaseosa()
    jugo_natural()
    agua_mineral()
    for archivo in sorted(DESTINO.glob("*.png")):
        print(f"{archivo.name:22} {archivo.stat().st_size / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
