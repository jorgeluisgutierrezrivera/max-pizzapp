#!/usr/bin/env python3
"""
Dibuja las ilustraciones de la carta ficticia en frontend/web/carta/.

POR QUÉ UN SCRIPT Y NO IMÁGENES DESCARGADAS
  Las ilustraciones se dibujaron para el proyecto: formas simples (círculos,
  polígonos, trazos) combinadas en capas. Así no hay derechos de terceros de por
  medio, cualquiera puede regenerarlas, y cambiar un color o agregar un producto
  es editar una línea. Cuando llegue la carta real con sus fotos, este script
  deja de hacer falta.

CÓMO SE USA (desde la raíz del repositorio)
  pip install pillow==12.3.0
  python scripts/dibujar-carta.py

  El resultado es el mismo en cada ejecución: el azar de cada imagen parte de
  una semilla fija derivada del nombre del archivo.

CÓMO SE DIBUJA
  Todo se describe en un lienzo de 600 × 600 unidades, se pinta 4 veces más
  grande y al final se reduce: así los bordes quedan suaves. El fondo es
  transparente, para que la tarjeta de la app ponga el suyo.
"""

import math
import random
import zlib
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

LADO = 600          # tamaño final, en píxeles
K = 4               # factor de sobremuestreo
C = LADO / 2        # centro del lienzo

DESTINO = Path(__file__).resolve().parent.parent / "frontend" / "web" / "carta"

# Paleta
QUESO = (244, 207, 106)
SALSA = (184, 52, 32)
OREGANO = (80, 110, 45)


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


def mancha(x, y, r, rng, irregular=0.12, lados=48):
    """Un contorno redondeado e irregular: queso derretido, carne, pollo."""
    fases = [rng.uniform(0, 2 * math.pi) for _ in range(3)]
    puntos = []
    for i in range(lados):
        t = 2 * math.pi * i / lados
        f = 1 + irregular * (0.6 * math.sin(2 * t + fases[0])
                             + 0.3 * math.sin(3 * t + fases[1])
                             + 0.2 * math.sin(5 * t + fases[2]))
        puntos.append((x + r * f * math.cos(t), y + r * f * math.sin(t)))
    return puntos


def recortar(capa, puntos):
    """Deja visible de la capa solo lo que cae dentro del polígono."""
    mascara = Image.new("L", capa.size, 0)
    ImageDraw.Draw(mascara).polygon([(x * K, y * K) for x, y in puntos], fill=255)
    capa.putalpha(ImageChops.multiply(capa.getchannel("A"), mascara))
    return capa


def repartir(rng, cantidad, radio, separacion, ocupados):
    """Posiciones al azar dentro de un círculo, sin encimarse con las ya puestas."""
    puntos = []
    for _ in range(6000):
        if len(puntos) == cantidad:
            break
        angulo = rng.uniform(0, 2 * math.pi)
        distancia = radio * math.sqrt(rng.random())
        x, y = C + distancia * math.cos(angulo), C + distancia * math.sin(angulo)
        if all((x - a) ** 2 + (y - b) ** 2 >= separacion ** 2 for a, b in ocupados):
            puntos.append((x, y))
            ocupados.append((x, y))
    return puntos


# ---------------------------------------------------------------------------
# La pizza: base e ingredientes
# ---------------------------------------------------------------------------

R_BORDE = 262       # radio del borde de masa
R_INGREDIENTES = 205


def base_pizza(lz, rng):
    """Sombra, masa, salsa y queso. Devuelve el contorno del queso."""
    capa, d = lz.capa()
    circulo(d, C + 5, C + 11, R_BORDE, (60, 30, 10, 95))
    lz.pegar(capa, desenfoque=9)

    capa, d = lz.capa()
    circulo(d, C, C, R_BORDE, (176, 108, 46))
    circulo(d, C, C, R_BORDE - 6, (212, 150, 78))
    circulo(d, C, C, R_BORDE - 17, (232, 180, 104))
    for _ in range(46):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(R_BORDE - 22, R_BORDE - 8)
        circulo(d, C + r * math.cos(a), C + r * math.sin(a), rng.uniform(2.5, 6), (196, 128, 60))
    poligono(d, mancha(C, C, R_BORDE - 30, rng, 0.025, 90), SALSA)
    contorno_queso = mancha(C, C, R_BORDE - 40, rng, 0.045, 90)
    poligono(d, contorno_queso, QUESO)
    lz.pegar(capa)

    # Textura del queso: zonas más claras y otras doradas por el horno.
    capa, d = lz.capa()
    for _ in range(14):
        x, y = repartir(rng, 1, R_INGREDIENTES, 0, [])[0]
        poligono(d, mancha(x, y, rng.uniform(10, 22), rng, 0.3, 24), (251, 230, 165, 110))
    for _ in range(18):
        x, y = repartir(rng, 1, R_INGREDIENTES + 10, 0, [])[0]
        poligono(d, mancha(x, y, rng.uniform(5, 12), rng, 0.3, 20), (222, 160, 68, 130))
    lz.pegar(recortar(capa, contorno_queso), desenfoque=1.2)
    return contorno_queso


def sombras(lz, huellas):
    """Una sombra suave bajo cada ingrediente: le da volumen."""
    capa, d = lz.capa()
    for x, y, r in huellas:
        circulo(d, x + 1.5, y + 3, r, (70, 30, 5, 70))
    lz.pegar(capa, desenfoque=2.5)


def cortes(lz, rng):
    capa, d = lz.capa()
    giro = rng.uniform(0, math.pi / 8)
    for i in range(4):
        a = giro + i * math.pi / 4
        dx, dy = math.cos(a) * (R_BORDE - 34), math.sin(a) * (R_BORDE - 34)
        trazo(d, [(C - dx, C - dy), (C + dx, C + dy)], (120, 70, 20, 60), 1.6)
    lz.pegar(capa)


def oregano(d, rng, cantidad=70):
    for x, y in repartir(rng, cantidad, R_INGREDIENTES + 15, 0, []):
        circulo(d, x, y, rng.uniform(1.0, 2.2), OREGANO)


def pepperoni(d, x, y, rng, r=31):
    circulo(d, x, y, r, (150, 40, 25))
    circulo(d, x, y, r - 3, (192, 62, 38))
    for _ in range(6):
        a, dist = rng.uniform(0, 2 * math.pi), rng.uniform(0, r * 0.6)
        circulo(d, x + dist * math.cos(a), y + dist * math.sin(a), rng.uniform(1.8, 3.6), (158, 44, 28))
    arco(d, x, y, r - 7, 200, 250, (232, 125, 95), 2.2)


def jamon(d, x, y, rng, lado=46):
    m = lado / 2
    esquinas = [(x - m + rng.uniform(-4, 4), y - m + rng.uniform(-4, 4)),
                (x + m + rng.uniform(-4, 4), y - m + rng.uniform(-4, 4)),
                (x + m + rng.uniform(-4, 4), y + m + rng.uniform(-4, 4)),
                (x - m + rng.uniform(-4, 4), y + m + rng.uniform(-4, 4))]
    esquinas = girar(esquinas, x, y, rng.uniform(0, math.pi))
    poligono(d, esquinas, (214, 118, 124))
    interior = [(x + (a - x) * 0.78, y + (b - y) * 0.78) for a, b in esquinas]
    poligono(d, interior, (240, 162, 162))
    trazo(d, [interior[0], interior[2]], (248, 196, 192), 2.5)


def pina(d, x, y, rng, t=29):
    forma = [(x - t, y - t * 0.55), (x + t, y - t * 0.55),
             (x + t * 0.55, y + t * 0.7), (x - t * 0.55, y + t * 0.7)]
    forma = girar(forma, x, y, rng.uniform(0, 2 * math.pi))
    poligono(d, forma, (228, 178, 38))
    poligono(d, [(x + (a - x) * 0.8, y + (b - y) * 0.8) for a, b in forma], (249, 214, 70))
    trazo(d, [((forma[0][0] + forma[3][0]) / 2, (forma[0][1] + forma[3][1]) / 2),
              ((forma[1][0] + forma[2][0]) / 2, (forma[1][1] + forma[2][1]) / 2)],
          (232, 186, 45), 1.5)


def tomate(d, x, y, rng, r=39):
    circulo(d, x, y, r, (196, 42, 32))
    circulo(d, x, y, r - 4, (228, 78, 58))
    giro = rng.uniform(0, 2 * math.pi)
    for i in range(5):
        a = giro + i * 2 * math.pi / 5
        elipse(d, x + r * 0.5 * math.cos(a), y + r * 0.5 * math.sin(a), 7, 7, (246, 172, 132))
    circulo(d, x, y, r * 0.2, (236, 118, 88))


def hoja(d, x, y, rng, largo=30, ancho=13, color=(58, 128, 52)):
    puntos = []
    for i in range(21):
        t = i / 20
        puntos.append((x - largo + 2 * largo * t, y - ancho * math.sin(math.pi * t)))
    for i in range(20, -1, -1):
        t = i / 20
        puntos.append((x - largo + 2 * largo * t, y + ancho * 0.8 * math.sin(math.pi * t)))
    angulo = rng.uniform(0, 2 * math.pi)
    poligono(d, girar(puntos, x, y, angulo), color)
    trazo(d, girar([(x - largo * 0.8, y), (x + largo * 0.8, y)], x, y, angulo), (112, 170, 92), 1.4)


def aceituna(d, x, y, r=15, verde=True):
    if verde:
        circulo(d, x, y, r, (104, 130, 46))
        circulo(d, x, y, r * 0.45, (200, 70, 55))
    else:
        circulo(d, x, y, r, (42, 36, 36))
        circulo(d, x, y, r * 0.42, QUESO)


def cebolla(d, x, y, rng, r, color=(238, 228, 238), filo=(176, 136, 178)):
    if rng.random() < 0.35:
        desde = rng.uniform(0, 360)
        arco(d, x, y, r, desde, desde + rng.uniform(150, 260), color, 7)
        arco(d, x, y, r + 3, desde, desde + rng.uniform(150, 260), filo, 1.3)
    else:
        circulo(d, x, y, r, borde=color, ancho=7)
        circulo(d, x, y, r + 3, borde=filo, ancho=1.3)


def salchicha(d, x, y, rng, r=17):
    poligono(d, mancha(x, y, r, rng, 0.28, 24), (116, 66, 42))
    poligono(d, mancha(x - 2, y - 2, r * 0.55, rng, 0.3, 18), (152, 96, 62))


def tocino(d, x, y, rng, largo=60):
    angulo = rng.uniform(0, math.pi)
    puntos = [(x - largo / 2 + largo * i / 16, y + 5 * math.sin(i * 0.9)) for i in range(17)]
    puntos = girar(puntos, x, y, angulo)
    trazo(d, puntos, (168, 68, 50), 15)
    trazo(d, girar([(px, py + 2) for px, py in
                    [(x - largo / 2 + largo * i / 16, y + 5 * math.sin(i * 0.9)) for i in range(17)]],
                   x, y, angulo), (240, 196, 176), 4)


def pollo(d, x, y, rng, r=24):
    poligono(d, mancha(x, y, r, rng, 0.26, 26), (178, 118, 64))
    poligono(d, mancha(x - 1.5, y - 1.5, r * 0.72, rng, 0.26, 22), (222, 172, 112))


def llovizna_barbacoa(d, rng):
    """Hilos de salsa barbacoa en diagonal, cortados en el borde del queso."""
    inclinacion = math.radians(rng.uniform(20, 35))
    for k in range(4):
        base = (k - 1.5) * 92 + rng.uniform(-10, 10)
        fase = rng.uniform(0, 2 * math.pi)
        amplitud = rng.uniform(10, 16)
        crudos = [(i, base + amplitud * math.sin(i * 0.07 + fase)) for i in range(-240, 241, 3)]
        tramo = []
        for px, py in girar([(C + a, C + b) for a, b in crudos], C, C, inclinacion):
            if (px - C) ** 2 + (py - C) ** 2 < (R_INGREDIENTES + 12) ** 2:
                tramo.append((px, py))
            elif len(tramo) > 1:
                trazo(d, tramo, (92, 38, 18), 4.5)
                tramo = []
        if len(tramo) > 1:
            trazo(d, tramo, (92, 38, 18), 4.5)


def pizza(nombre, ingredientes):
    """Dibuja una pizza: la base y encima lo que ponga la función ingredientes."""
    rng = random.Random(zlib.crc32(nombre.encode()))
    lz = Lienzo()
    contorno_queso = base_pizza(lz, rng)
    ingredientes(lz, rng, contorno_queso)
    cortes(lz, rng)
    lz.guardar(DESTINO / nombre)


def con_sombra(lz, rng, grupos):
    """grupos: lista de (función, cantidad, radio de huella, separación)."""
    ocupados = []
    colocados = []
    for funcion, cantidad, radio, separacion in grupos:
        for x, y in repartir(rng, cantidad, R_INGREDIENTES, separacion, ocupados):
            colocados.append((funcion, x, y, radio))
    rng.shuffle(colocados)
    sombras(lz, [(x, y, r) for _, x, y, r in colocados])
    capa, d = lz.capa()
    for funcion, x, y, _ in colocados:
        funcion(d, x, y, rng)
    return capa, d


# --- Las nueve pizzas -------------------------------------------------------

def muzzarella(lz, rng, _):
    capa, d = con_sombra(lz, rng, [(lambda d, x, y, r: aceituna(d, x, y), 9, 15, 62)])
    oregano(d, rng, 90)
    lz.pegar(capa)


def napolitana(lz, rng, _):
    capa, d = con_sombra(lz, rng, [(tomate, 7, 39, 84)])
    for x, y in repartir(rng, 5, R_INGREDIENTES - 10, 40, []):
        hoja(d, x, y, rng)
    for x, y in repartir(rng, 40, R_INGREDIENTES, 0, []):
        circulo(d, x, y, rng.uniform(1.5, 2.8), (250, 246, 232))
    oregano(d, rng, 50)
    lz.pegar(capa)


def pepperoni_pizza(lz, rng, _):
    capa, _d = con_sombra(lz, rng, [(pepperoni, 13, 31, 66)])
    lz.pegar(capa)


def jamon_y_queso(lz, rng, _):
    capa, d = con_sombra(lz, rng, [(jamon, 10, 28, 70)])
    oregano(d, rng, 40)
    lz.pegar(capa)


def fugazza(lz, rng, _):
    capa, d = lz.capa()
    ocupados = []
    for x, y in repartir(rng, 14, R_INGREDIENTES, 50, ocupados):
        cebolla(d, x, y, rng, rng.uniform(18, 30))
    oregano(d, rng, 110)
    lz.pegar(capa)


def carnivora(lz, rng, _):
    capa, _d = con_sombra(lz, rng, [
        (pepperoni, 5, 31, 62), (jamon, 3, 28, 62),
        (tocino, 4, 26, 62), (salchicha, 8, 17, 42),
    ])
    lz.pegar(capa)


def hawaiana(lz, rng, _):
    capa, _d = con_sombra(lz, rng, [(jamon, 6, 28, 66), (pina, 8, 24, 58)])
    lz.pegar(capa)


def cuatro_quesos(lz, rng, contorno_queso):
    capa, d = lz.capa()
    colores = [(250, 242, 220), (242, 176, 66), (236, 230, 206), (246, 222, 150)]
    giro = rng.uniform(0, 90)
    for i, color in enumerate(colores):
        d.pieslice(_caja(C, C, R_BORDE, R_BORDE), giro + i * 90, giro + (i + 1) * 90, fill=color)
    lz.pegar(recortar(capa, contorno_queso), desenfoque=2)

    def en_cuadrante(i, cantidad):
        salida = []
        while len(salida) < cantidad:
            a = math.radians(giro + i * 90 + rng.uniform(8, 82))
            r = R_INGREDIENTES * math.sqrt(rng.uniform(0.05, 1))
            salida.append((C + r * math.cos(a), C + r * math.sin(a)))
        return salida

    capa, d = lz.capa()
    for x, y in en_cuadrante(0, 10):                      # muzzarella: blanca y cremosa
        poligono(d, mancha(x, y, rng.uniform(9, 16), rng, 0.3, 20), (255, 252, 240))
    for x, y in en_cuadrante(1, 12):                      # cheddar: naranja
        poligono(d, mancha(x, y, rng.uniform(6, 12), rng, 0.3, 20), (228, 142, 40))
    for x, y in en_cuadrante(2, 26):                      # azul: vetas
        a = rng.uniform(0, math.pi)
        largo = rng.uniform(4, 10)
        trazo(d, [(x - largo * math.cos(a), y - largo * math.sin(a)),
                  (x + largo * math.cos(a), y + largo * math.sin(a))], (92, 124, 138), 2.4)
    for x, y in en_cuadrante(3, 40):                      # parmesano: rallado
        circulo(d, x, y, rng.uniform(1.4, 2.6), (255, 250, 228))
    oregano(d, rng, 35)
    lz.pegar(capa)


def pollo_barbacoa(lz, rng, _):
    capa, d = con_sombra(lz, rng, [(pollo, 10, 24, 60)])
    for x, y in repartir(rng, 9, R_INGREDIENTES, 30, []):
        desde = rng.uniform(0, 360)
        arco(d, x, y, rng.uniform(14, 20), desde, desde + 170, (140, 58, 120), 5)
    llovizna_barbacoa(d, rng)
    for x, y in repartir(rng, 26, R_INGREDIENTES, 0, []):
        hoja(d, x, y, rng, largo=5, ancho=3, color=(76, 140, 60))
    lz.pegar(capa)


# ---------------------------------------------------------------------------
# Las bebidas
# ---------------------------------------------------------------------------

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
    pizza("muzzarella.png", muzzarella)
    pizza("napolitana.png", napolitana)
    pizza("pepperoni.png", pepperoni_pizza)
    pizza("jamon-y-queso.png", jamon_y_queso)
    pizza("fugazza.png", fugazza)
    pizza("carnivora.png", carnivora)
    pizza("hawaiana.png", hawaiana)
    pizza("cuatro-quesos.png", cuatro_quesos)
    pizza("pollo-barbacoa.png", pollo_barbacoa)
    gaseosa()
    jugo_natural()
    agua_mineral()
    for archivo in sorted(DESTINO.glob("*.png")):
        print(f"{archivo.name:22} {archivo.stat().st_size / 1024:6.1f} KB")


if __name__ == "__main__":
    main()
