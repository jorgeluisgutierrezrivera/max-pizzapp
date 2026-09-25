# -*- coding: utf-8 -*-
"""Mide cuanto tarda el aviso en vivo, con tokens REALES, contra la API y el canal de verdad.

Obtiene los tokens de recepcion.demo y cocina.demo en Keycloak y lanza medir-aviso.js, que
crea pedidos, mide del envio de la venta al aviso en cocina (el "menos de 2 segundos" del
E2), del cambio de estado al aviso en recepcion y de lo agregado al aviso en cocina, y al
final cierra lo que creo.

Uso, con el entorno levantado (necesita Node y el backend con sus dependencias instaladas):

    python pruebas/tiempo-real/medir_aviso.py

Contra el despliegue publico, desde cualquier maquina con la contrasena de alla:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
    KEYCLOAK_DEMO_PASSWORD=... python pruebas/tiempo-real/medir_aviso.py

VECES=20 cambia la cantidad de mediciones (por defecto, 10). Los tokens pasan a Node por
el entorno del proceso y nunca se imprimen.
"""
import importlib.util
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'identidad', os.path.join(AQUI, '..', 'identidad', 'probar_acceso_pkce.py'))
identidad = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(identidad)

API = (os.environ.get('API_URL')
       or 'http://localhost:%s/api/v1' % identidad.entorno('API_PORT', '3001')).rstrip('/')

if __name__ == '__main__':
    print('API:', API, flush=True)
    print('Keycloak:', identidad.KC, flush=True)
    entorno = dict(os.environ)
    entorno['API_URL'] = API
    entorno['TOKEN_RECEPCION'] = identidad.obtener_token('recepcion.demo', informar=lambda *_: None)['access_token']
    entorno['TOKEN_COCINA'] = identidad.obtener_token('cocina.demo', informar=lambda *_: None)['access_token']
    resultado = subprocess.run(['node', os.path.join(AQUI, 'medir-aviso.js')], env=entorno)
    sys.exit(resultado.returncode)
