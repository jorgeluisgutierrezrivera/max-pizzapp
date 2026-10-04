# -*- coding: utf-8 -*-
"""Mide cuanto tarda el aviso en vivo, con tokens REALES, contra la API y el canal de verdad.

Obtiene los tokens de recepcion.demo y cocina.demo en Keycloak y lanza medir-aviso.js, que
crea pedidos, mide del envio de la venta al aviso en cocina (el "menos de 2 segundos" del
E2), del cambio de estado al aviso en recepcion, de lo agregado al aviso en cocina y de la
marca de una bebida agotada o disponible al aviso en recepcion (CA-13.1, tarjeta 08), y al
final cierra lo que creo y deja la bebida como estaba. El reporte queda en docs/pruebas/reportes/tiempo-real.txt, con la
fecha y el entorno al principio (tarjeta 10, D-57).

Uso, con el entorno levantado (necesita Node y el backend con sus dependencias instaladas):

    python pruebas/tiempo-real/medir_aviso.py

Contra el despliegue publico, desde cualquier maquina con la contrasena de alla:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
    KEYCLOAK_DEMO_PASSWORD=... python pruebas/tiempo-real/medir_aviso.py

Por defecto son 30 mediciones, las que pide el RNF-01; VECES=10 cambia la cantidad. Los
tokens pasan a Node por el entorno del proceso y nunca se imprimen.
"""
import datetime
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
REPORTE = os.path.join(AQUI, '..', '..', 'docs', 'pruebas', 'reportes', 'tiempo-real.txt')

if __name__ == '__main__':
    # La salida de Node trae caracteres como "·": en una consola de Windows, sin esto, se
    # verian mal.
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    print('API:', API, flush=True)
    print('Keycloak:', identidad.KC, flush=True)
    entorno = dict(os.environ)
    entorno['API_URL'] = API
    entorno['TOKEN_RECEPCION'] = identidad.obtener_token('recepcion.demo', informar=lambda *_: None)['access_token']
    entorno['TOKEN_COCINA'] = identidad.obtener_token('cocina.demo', informar=lambda *_: None)['access_token']
    inicio = datetime.datetime.now(datetime.timezone.utc)
    resultado = subprocess.run(['node', os.path.join(AQUI, 'medir-aviso.js')], env=entorno,
                               capture_output=True, text=True, encoding='utf-8')
    salida = resultado.stdout + (('\n' + resultado.stderr) if resultado.stderr else '')
    duracion = (datetime.datetime.now(datetime.timezone.utc) - inicio).total_seconds()
    print(salida, end='', flush=True)
    bien = resultado.returncode == 0
    cabecera = '\n'.join([
        'Max Pizzapp - reporte de la propagacion del aviso en vivo (RNF-01 y CA-13.1)',
        'Fecha:    %s (duro %.1f s)' % (inicio.isoformat(timespec='seconds'), duracion),
        'API:      %s' % API,
        'Keycloak: %s' % identidad.KC,
        'Comando:  python pruebas/tiempo-real/medir_aviso.py   (las mediciones: medir-aviso.js, con socket.io-client)',
        'Prueba:   %s repeticiones; de la peticion a la llegada del evento en la otra pantalla.' % entorno.get('VECES', '30'),
        '          Umbral: el peor caso de cada aviso, menos de 2 s.',
        'Cuentas de prueba reales por PKCE; la contrasena y los tokens no se imprimen.',
        'Resultado: %s' % ('TODO BAJO 2 s' if bien else 'HAY MEDICIONES DE 2 s O MAS, O LA MEDICION FALLO'),
        '-' * 78,
        '',
    ])
    os.makedirs(os.path.dirname(REPORTE), exist_ok=True)
    with open(REPORTE, 'w', encoding='utf-8', newline='\n') as f:
        f.write(cabecera + salida)
    print('Reporte: docs/pruebas/reportes/tiempo-real.txt')
    sys.exit(resultado.returncode)
