#!/usr/bin/env python3
"""
Prepara las fotos de las pizzas para la app: frontend/web/carta/<pizza>.webp.

POR QUÉ
  Las fotos originales pesan unos 3 MB cada una. La app las muestra en tarjetas de
  unos 200 px: con 640 × 640 en WebP alcanza para pantallas de alta densidad, y cada
  una queda en decenas de KB. Así la carta carga rápido también con datos móviles.

CÓMO SE USA (desde la raíz del repositorio)
  pip install pillow==12.3.0
  python scripts/preparar-fotos.py "C:/ruta/a/la/carpeta/de/fotos"

  Cada archivo se asigna a una pizza por su nombre, sin mirar mayúsculas ni tildes:
  «CLÁSICA.jpg» es la imagen «clasica» de la carta. Los nombres que el local usa distinto
  van en ALIAS. Al final se informa qué pizzas de la carta quedaron sin foto y qué
  archivos no correspondían a ninguna.

  Las fotos originales NO se versionan: solo el resultado.
"""

import re
import sys
import unicodedata
from pathlib import Path

from PIL import Image, ImageOps

RAIZ = Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "frontend" / "web" / "carta"
CARTA = RAIZ / "docker" / "postgres" / "init" / "05_carta.sql"

LADO = 640
CALIDAD = 80

# Nombres de archivo del local que no coinciden con el de la imagen en la carta.
ALIAS = {
    "3-estaciones": "tres-estaciones",
    "4-quesos": "cuatro-quesos",
    "la-carnivora": "carnivora",
    "la-espanola": "espanola",
    "pizza-dos-estaciones": "dos-estaciones",
}


def a_nombre_simple(texto):
    """«LA CARNÍVORA» → «la-carnivora»: minúsculas, sin tildes, con guiones."""
    sin_tildes = "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "-", sin_tildes.lower()).strip("-")


def imagenes_de_pizzas():
    """Los nombres de imagen de las pizzas de la carta, leídos de 05_carta.sql."""
    nombres = set()
    for linea in CARTA.read_text(encoding="utf-8").splitlines():
        m = re.search(r"'pizza',.*'([a-z0-9-]+)\.(?:png|jpg|webp)'\)", linea)
        if m:
            nombres.add(m.group(1))
    return nombres


def preparar(origen, destino):
    with Image.open(origen) as foto:
        foto = ImageOps.exif_transpose(foto).convert("RGB")
        lado = min(foto.size)
        foto = ImageOps.fit(foto, (lado, lado), centering=(0.5, 0.5))   # cuadrada, centrada
        foto = foto.resize((LADO, LADO), Image.LANCZOS)
        foto.save(destino, "WEBP", quality=CALIDAD, method=6)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    carpeta = Path(sys.argv[1])
    esperadas = imagenes_de_pizzas()
    hechas, sobrantes = set(), []
    for archivo in sorted(carpeta.iterdir()):
        if archivo.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
            continue
        nombre = a_nombre_simple(archivo.stem)
        nombre = ALIAS.get(nombre, nombre)
        if nombre not in esperadas:
            sobrantes.append(archivo.name)
            continue
        destino = DESTINO / f"{nombre}.webp"
        preparar(archivo, destino)
        hechas.add(nombre)
        print(f"  {archivo.name:28} -> {destino.name:24} {destino.stat().st_size / 1024:5.1f} KB")
    print(f"\n{len(hechas)} de {len(esperadas)} pizzas con foto.")
    if esperadas - hechas:
        print("Sin foto:", ", ".join(sorted(esperadas - hechas)))
    if sobrantes:
        print("Archivos que no corresponden a ninguna pizza de la carta:", ", ".join(sobrantes))


if __name__ == "__main__":
    main()
