# -*- coding: utf-8 -*-
"""Mide cuanto tarda una pantalla en notar que el canal en vivo se corto (RNF-05: < 10 s).

Lanza medir-caida.js. En el modo de por defecto obtiene el token de cocina.demo en Keycloak
y mide, contra la API local, cuanto tarda el cliente de Socket.IO en dar por perdida una
conexion cuya red se colgo sin cerrarse: la corta un "tapon" TCP en un momento al azar del
ciclo del latido. Tiene que quedar bajo 10 s.

Uso, con el entorno local levantado (necesita Node y el backend con sus dependencias):

    python pruebas/tiempo-real/medir_caida.py

Contra el despliegue publico solo se lee el latido que anuncia el servidor (no hace falta
contrasena):

    MODO=saludo API_URL=https://maxpizzapp.tech/api/v1 python pruebas/tiempo-real/medir_caida.py

VECES=20 cambia la cantidad de cortes (por defecto, 10). El token pasa a Node por el entorno
del proceso y nunca se imprime.
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
    entorno = dict(os.environ)
    entorno['API_URL'] = API
    if entorno.get('MODO', 'corte') != 'saludo':
        print('Keycloak:', identidad.KC, flush=True)
        entorno['TOKEN_COCINA'] = identidad.obtener_token('cocina.demo', informar=lambda *_: None)['access_token']
    resultado = subprocess.run(['node', os.path.join(AQUI, 'medir-caida.js')], env=entorno)
    sys.exit(resultado.returncode)
