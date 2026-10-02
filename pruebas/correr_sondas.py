# -*- coding: utf-8 -*-
"""Corre las sondas contra un entorno real y guarda su salida como reporte (tarjeta 10, D-57).

Las sondas entran con las cuentas de prueba de verdad (PKCE contra Keycloak) y usan la API,
la base y el canal reales. Cada una deja su reporte en docs/pruebas/reportes/sonda-*.txt,
con la fecha y el entorno al principio:

    sonda-acceso.txt    identidad/probar_acceso_pkce.py  el acceso de las dos cuentas (RF-01)
    sonda-salud.txt     api/probar_salud_y_token.py      la ruta de salud, el token y el rol
    sonda-carta.txt     api/probar_carta.py              la carta que devuelve la base
    sonda-pedidos.txt   api/probar_pedidos.py            el ciclo de los pedidos, las carreras
    sonda-errores.txt   api/probar_errores.py            la matriz de 401, 403, 400, 413 y 415

Uso, con el entorno levantado:

    python pruebas/correr_sondas.py

Contra el despliegue publico, con la contrasena de alla en el entorno (nunca se imprime):

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        KEYCLOAK_DEMO_PASSWORD=... python pruebas/correr_sondas.py

La sonda de pedidos crea pedidos de prueba con datos ficticios y los cierra al terminar.
Contra produccion, fuera del horario de atencion (18:00 a 23:30).
"""
import datetime
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
REPORTES = os.path.join(AQUI, '..', 'docs', 'pruebas', 'reportes')
SONDAS = [
    ('acceso', os.path.join('identidad', 'probar_acceso_pkce.py')),
    ('salud', os.path.join('api', 'probar_salud_y_token.py')),
    ('carta', os.path.join('api', 'probar_carta.py')),
    ('pedidos', os.path.join('api', 'probar_pedidos.py')),
    ('errores', os.path.join('api', 'probar_errores.py')),
]


def main():
    os.makedirs(REPORTES, exist_ok=True)
    api = os.environ.get('API_URL', 'http://localhost:3001/api/v1 (desarrollo)')
    keycloak = os.environ.get('KEYCLOAK_URL', 'http://localhost:8082 (desarrollo)')
    entorno = dict(os.environ, PYTHONIOENCODING='utf-8')
    fallas = []
    for nombre, ruta in SONDAS:
        print('==> %s' % ruta, flush=True)
        inicio = datetime.datetime.now(datetime.timezone.utc)
        corrida = subprocess.run([sys.executable, os.path.join(AQUI, ruta)], env=entorno,
                                 capture_output=True, text=True, encoding='utf-8')
        salida = corrida.stdout + (('\n' + corrida.stderr) if corrida.stderr else '')
        duracion = (datetime.datetime.now(datetime.timezone.utc) - inicio).total_seconds()
        bien = corrida.returncode == 0
        if not bien:
            fallas.append(nombre)
        cabecera = '\n'.join([
            'Max Pizzapp - reporte de la sonda %s' % nombre,
            'Fecha:    %s (duro %.1f s)' % (inicio.isoformat(timespec='seconds'), duracion),
            'API:      %s' % api,
            'Keycloak: %s' % keycloak,
            'Comando:  python pruebas/%s   (todas: python pruebas/correr_sondas.py)' % ruta.replace(os.sep, '/'),
            'Cuentas de prueba reales por PKCE; la contrasena y los tokens no se imprimen.',
            'Resultado: %s' % ('TODO CORRECTO' if bien else 'HAY FALLOS'),
            '-' * 78,
            '',
        ])
        with open(os.path.join(REPORTES, 'sonda-%s.txt' % nombre), 'w', encoding='utf-8', newline='\n') as f:
            f.write(cabecera + salida)
        print('    %s (%.1f s)' % ('TODO CORRECTO' if bien else 'HAY FALLOS', duracion), flush=True)
    print('\nReportes en docs/pruebas/reportes/sonda-*.txt')
    print('TODAS CORRECTAS' if not fallas else 'CON FALLAS: %s' % ', '.join(fallas))
    return 0 if not fallas else 1


if __name__ == '__main__':
    sys.exit(main())
