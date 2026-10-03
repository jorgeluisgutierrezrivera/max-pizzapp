# -*- coding: utf-8 -*-
"""Mide la carga del listado de pedidos con k6 (RNF-01, tarjeta 10, D-58) y guarda el reporte.

Obtiene los tokens de recepcion.demo y cocina.demo en Keycloak, por PKCE, y corre
listado-pedidos.k6.js en la imagen oficial de k6, en Docker: crea 50 pedidos activos, 5
usuarios leen el listado durante 60 s y al final se cancelan los 50. El reporte queda en
docs/pruebas/reportes/carga-k6.txt, con la fecha y el entorno al principio.

Uso, con el entorno levantado (necesita Docker; k6 no se instala):

    python pruebas/carga/medir_carga.py

Contra el despliegue publico, con la contrasena de alla en el entorno:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        KEYCLOAK_DEMO_PASSWORD=... python pruebas/carga/medir_carga.py

Contra produccion, fuera del horario de atencion (18:00 a 23:30): los 50 pedidos aparecen
en la cocina mientras dura la prueba. Los tokens pasan a k6 por el entorno del proceso y
nunca se imprimen ni quedan en la linea de comandos.
"""
import datetime
import importlib.util
import os
import subprocess
import sys
import urllib.parse

AQUI = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'identidad', os.path.join(AQUI, '..', 'identidad', 'probar_acceso_pkce.py'))
identidad = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(identidad)

IMAGEN = 'grafana/k6:2.3.0'
SCRIPT = os.path.join(AQUI, 'listado-pedidos.k6.js')
REPORTE = os.path.join(AQUI, '..', '..', 'docs', 'pruebas', 'reportes', 'carga-k6.txt')
API = (os.environ.get('API_URL')
       or 'http://localhost:%s/api/v1' % identidad.entorno('API_PORT', '3001')).rstrip('/')


def desde_docker(url):
    # k6 corre dentro de un contenedor: ahi, "localhost" es el propio contenedor, y la API
    # local se alcanza como host.docker.internal.
    partes = urllib.parse.urlsplit(url)
    if partes.hostname in ('localhost', '127.0.0.1'):
        partes = partes._replace(netloc=partes.netloc.replace(partes.hostname, 'host.docker.internal', 1))
    return urllib.parse.urlunsplit(partes)


def main():
    # El resumen de k6 trae caracteres como ✓ y ✗: en una consola de Windows, sin esto,
    # imprimirlo fallaria.
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    print('API:', API, flush=True)
    print('Keycloak:', identidad.KC, flush=True)
    entorno = dict(os.environ)
    entorno['API_URL'] = desde_docker(API)
    entorno['TOKEN_RECEPCION'] = identidad.obtener_token('recepcion.demo', informar=lambda *_: None)['access_token']
    entorno['TOKEN_COCINA'] = identidad.obtener_token('cocina.demo', informar=lambda *_: None)['access_token']

    inicio = datetime.datetime.now(datetime.timezone.utc)
    # "-e NOMBRE" sin valor: Docker toma el valor del entorno de este proceso, asi el token
    # no aparece en la linea de comandos. El script entra por la entrada estandar ("run -").
    with open(SCRIPT, 'rb') as script:
        corrida = subprocess.run(
            ['docker', 'run', '--rm', '-i', '-e', 'API_URL', '-e', 'TOKEN_RECEPCION', '-e', 'TOKEN_COCINA',
             IMAGEN, 'run', '--quiet', '--no-color', '-'],
            env=entorno, stdin=script, capture_output=True)
    salida = (corrida.stdout + corrida.stderr).decode('utf-8', 'replace')
    duracion = (datetime.datetime.now(datetime.timezone.utc) - inicio).total_seconds()
    for token in (entorno['TOKEN_RECEPCION'], entorno['TOKEN_COCINA']):
        salida = salida.replace(token, '[token]')
    print(salida, flush=True)

    bien = corrida.returncode == 0
    cabecera = '\n'.join([
        'Max Pizzapp - reporte de la carga del listado (RNF-01), con k6',
        'Fecha:    %s (duro %.1f s)' % (inicio.isoformat(timespec='seconds'), duracion),
        'API:      %s' % API,
        'Keycloak: %s' % identidad.KC,
        'Herramienta: %s, en Docker' % IMAGEN,
        'Comando:  python pruebas/carga/medir_carga.py   (el script: pruebas/carga/listado-pedidos.k6.js)',
        'Prueba:   50 pedidos activos, 5 usuarios a la vez (3 de recepcion y 2 de cocina) leyendo',
        '          GET /api/v1/pedidos una vez por segundo durante 60 s. Umbral: p(95) < 2 s.',
        'Cuentas de prueba reales por PKCE; la contrasena y los tokens no se imprimen.',
        'Resultado: %s' % ('UMBRAL CUMPLIDO' if bien else 'UMBRAL NO CUMPLIDO O PRUEBA CON FALLAS (k6 salio con %d)' % corrida.returncode),
        '-' * 78,
        '',
    ])
    os.makedirs(os.path.dirname(REPORTE), exist_ok=True)
    with open(REPORTE, 'w', encoding='utf-8', newline='\n') as f:
        f.write(cabecera + salida.replace('\r\n', '\n'))
    print('Reporte: docs/pruebas/reportes/carga-k6.txt')
    print('UMBRAL CUMPLIDO' if bien else 'UMBRAL NO CUMPLIDO O PRUEBA CON FALLAS')
    return 0 if bien else 1


if __name__ == '__main__':
    sys.exit(main())
