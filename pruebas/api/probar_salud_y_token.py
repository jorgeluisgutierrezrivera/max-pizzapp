# -*- coding: utf-8 -*-
"""Comprueba la API de punta a punta con tokens REALES del realm.

Las pruebas del backend (npm test) usan un emisor falso para fabricar tokens expirados o
de otra audiencia. Esta prueba es la otra mitad: confirma que la API en marcha acepta los
tokens que emite el Keycloak de verdad, y rechaza lo que debe rechazar.

Uso, con el entorno levantado y las contrasenas de demostracion establecidas:

    python pruebas/api/probar_salud_y_token.py

Contra el despliegue publico:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \
        python3 pruebas/api/probar_salud_y_token.py

La contrasena se lee del .env y nunca se imprime; los tokens tampoco.
"""
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'identidad', os.path.join(AQUI, '..', 'identidad', 'probar_acceso_pkce.py'))
identidad = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(identidad)

API = (os.environ.get('API_URL')
       or 'http://localhost:%s/api/v1' % identidad.entorno('API_PORT', '3001')).rstrip('/')


def pedir(ruta, token=None):
    peticion = urllib.request.Request(API + ruta)
    if token:
        peticion.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(peticion, timeout=15) as r:
            return r.status, json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode('utf-8'))


resultados = []


def comprobar(descripcion, obtenido, esperado, detalle=''):
    correcto = obtenido == esperado
    resultados.append(correcto)
    print('  %s %-58s %s%s' % ('OK ' if correcto else 'MAL', descripcion, obtenido,
                              '' if correcto else '  (se esperaba %s)' % esperado)
          + ('  ' + detalle if detalle else ''))


if __name__ == '__main__':
    print('API:', API)
    print('Keycloak:', identidad.KC)

    print('\n--- ruta publica ---')
    estado, cuerpo = pedir('/salud')
    comprobar('GET /salud', estado, 200, json.dumps(cuerpo, ensure_ascii=False))

    print('\n--- sin credenciales ---')
    estado, cuerpo = pedir('/sesion')
    comprobar('GET /sesion sin token', estado, 401, cuerpo['error']['codigo'])
    estado, cuerpo = pedir('/sesion', 'esto.no.es-un-token')
    comprobar('GET /sesion con un token inventado', estado, 401, cuerpo['error']['codigo'])

    for usuario, rol in (('recepcion.demo', 'recepcion'), ('cocina.demo', 'cocina')):
        print('\n--- %s, token real ---' % usuario)
        token = identidad.obtener_token(usuario, informar=lambda *_: None)['access_token']

        estado, cuerpo = pedir('/sesion', token)
        comprobar('GET /sesion con su token', estado, 200)
        comprobar('  el servidor reconoce su rol', cuerpo.get('roles'), [rol])
        comprobar('  y su usuario', cuerpo.get('usuario'), usuario)

        cabecera, carga, firma = token.split('.')
        manipulada = firma[:-4] + ('AAAA' if not firma.endswith('AAAA') else 'BBBB')
        estado, cuerpo = pedir('/sesion', '.'.join([cabecera, carga, manipulada]))
        comprobar('GET /sesion con la firma manipulada', estado, 401, cuerpo['error']['codigo'])

    estado, cuerpo = pedir('/no-existe')
    print('\n--- formato de error ---')
    comprobar('ruta inexistente', estado, 404, cuerpo['error']['codigo'])

    print('\n' + ('TODO CORRECTO' if all(resultados) else 'HAY FALLOS'))
    sys.exit(0 if all(resultados) else 1)
