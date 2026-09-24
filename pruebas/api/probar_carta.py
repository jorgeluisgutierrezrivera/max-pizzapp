# -*- coding: utf-8 -*-
"""Comprueba GET /api/v1/productos de punta a punta: token REAL y base REAL.

Las pruebas del backend (npm test) simulan la base para ver QUE le llega. Esta es la otra
mitad: que la consulta funcione contra el esquema de verdad, con la carta cargada, y que los
dos roles la lean.

Uso, con el entorno levantado, la carta cargada y las contrasenas de demostracion:

    python pruebas/api/probar_carta.py

Contra el despliegue publico:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        python3 pruebas/api/probar_carta.py

La contrasena se lee del .env y nunca se imprime; los tokens tampoco.
"""
import importlib.util
import os
import re
import sys
import unicodedata

AQUI = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'base_api', os.path.join(AQUI, 'probar_salud_y_token.py'))
base_api = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base_api)

identidad, pedir, comprobar, resultados = (
    base_api.identidad, base_api.pedir, base_api.comprobar, base_api.resultados)

NOMBRE_DE_ARCHIVO = re.compile(r'^[a-z0-9-]+\.(png|jpg|webp)$')
ORDEN_CATEGORIAS = ['pizza', 'entrada', 'bebida', 'postre', 'extra']


def sin_tildes(texto):
    return ''.join(c for c in unicodedata.normalize('NFD', texto.casefold())
                   if unicodedata.category(c) != 'Mn')


def clave_de_orden(p):
    # Por categoria y, dentro de ella, por nombre sin mirar tildes ni mayusculas: asi
    # ordena PostgreSQL con la intercalacion del idioma.
    return (ORDEN_CATEGORIAS.index(p['categoria']), sin_tildes(p['nombre']))


if __name__ == '__main__':
    print('API:', base_api.API)
    print('Keycloak:', identidad.KC)

    print('\n--- sin credenciales ---')
    estado, cuerpo = pedir('/productos')
    comprobar('GET /productos sin token', estado, 401, cuerpo['error']['codigo'])

    for usuario in ('recepcion.demo', 'cocina.demo'):
        print('\n--- %s, token real ---' % usuario)
        token = identidad.obtener_token(usuario, informar=lambda *_: None)['access_token']
        estado, cuerpo = pedir('/productos', token)
        comprobar('GET /productos', estado, 200)
    carta = cuerpo.get('productos', [])

    print('\n--- la carta que devuelve la base ---')
    pizzas = [p for p in carta if p['categoria'] == 'pizza']
    comprobar('hay carta cargada', len(carta) > 0, True, '%d productos' % len(carta))
    comprobar('ordenada: primero las pizzas, cada categoria por nombre',
              [clave_de_orden(p) for p in carta] == sorted(clave_de_orden(p) for p in carta), True)
    comprobar('sin gama ni precio de media: solo pizzas enteras (D-27)',
              all('gama' not in p and 'precioMedia' not in p for p in carta), True)
    comprobar('toda pizza trae sus ingredientes en la descripcion',
              all(isinstance(p.get('descripcion'), str) and p['descripcion'].strip() for p in pizzas), True)
    comprobar('los precios llegan como numeros',
              all(isinstance(p['precio'], (int, float)) for p in carta), True)
    comprobar('la imagen es solo un nombre de archivo',
              all(p['imagen'] is None or NOMBRE_DE_ARCHIVO.match(p['imagen']) for p in carta), True)

    print('\n--- los filtros, contra el esquema real ---')
    estado, cuerpo = pedir('/productos?categoria=pizza', token)
    comprobar('?categoria=pizza', estado, 200)
    comprobar('  devuelve solo pizzas', [p['categoria'] for p in cuerpo['productos']],
              ['pizza'] * len(pizzas))
    estado, cuerpo = pedir('/productos?categoria=bebida&disponible=true', token)
    comprobar('?categoria=bebida&disponible=true', estado, 200)
    comprobar('  solo bebidas disponibles',
              all(p['categoria'] == 'bebida' and p['disponible'] for p in cuerpo['productos']), True)
    estado, cuerpo = pedir('/productos?disponible=false', token)
    comprobar('?disponible=false', estado, 200,
              '%d agotados' % len(cuerpo.get('productos', [])))
    estado, cuerpo = pedir('/productos?categoria=extra', token)
    extras = cuerpo.get('productos', [])
    comprobar('?categoria=extra', estado, 200, '%d extras' % len(extras))
    comprobar('  solo extras, y hay al menos uno',
              len(extras) > 0 and all(p['categoria'] == 'extra' for p in extras), True)
    estado, cuerpo = pedir('/productos?categoria=pasta', token)
    comprobar('?categoria=pasta', estado, 400, cuerpo['error']['codigo'])

    print('\n' + ('TODO CORRECTO' if all(resultados) else 'HAY FALLOS'))
    sys.exit(0 if all(resultados) else 1)
