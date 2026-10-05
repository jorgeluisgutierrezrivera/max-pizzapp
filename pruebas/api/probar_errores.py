# -*- coding: utf-8 -*-
"""La matriz de errores de la API: 401, 403, 400, 404, 413 y 415, con tokens REALES (tarjetas 10 y 08).

Cada caso pide algo que el sistema tiene que rechazar y comprueba el codigo y el error del
formato unico. NINGUN caso crea nada en la base: todos se cortan antes, en el acceso, en el
token, en el rol o en la validacion. Ademas, un acceso con la contrasena equivocada (CA-01.2):
Keycloak no entrega codigo ni token.

Uso, con el entorno levantado:

    python pruebas/api/probar_errores.py

Contra el despliegue publico, con la contrasena de alla en el entorno:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        KEYCLOAK_DEMO_PASSWORD=... python pruebas/api/probar_errores.py

Un solo intento con la contrasena equivocada, y despues de pedir los tokens buenos: dos
fallos en menos de un segundo bloquearian la cuenta 60 s (tarjeta 09). La contrasena y los
tokens nunca se imprimen.
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


def pedir(metodo, ruta, token=None, cuerpo=None, crudo=None, cabeceras=None):
    datos = crudo if crudo is not None else (None if cuerpo is None else json.dumps(cuerpo).encode('utf-8'))
    h = {'Content-Type': 'application/json'}
    h.update(cabeceras or {})
    if token:
        h['Authorization'] = 'Bearer ' + token
    peticion = urllib.request.Request(API + ruta, method=metodo, data=datos, headers=h)
    try:
        with urllib.request.urlopen(peticion, timeout=15) as r:
            return r.status, json.loads(r.read().decode('utf-8') or '{}')
    except urllib.error.HTTPError as e:
        cuerpo = e.read().decode('utf-8')
        try:
            return e.code, json.loads(cuerpo or '{}')
        except ValueError:
            return e.code, {}


def callado(*_):
    pass


if __name__ == '__main__':
    print('API:', API)
    print('Keycloak:', identidad.KC)
    recepcion = identidad.obtener_token('recepcion.demo', informar=callado)['access_token']
    cocina = identidad.obtener_token('cocina.demo', informar=callado)['access_token']
    alterado = recepcion[:-4] + ('AAAA' if not recepcion.endswith('AAAA') else 'BBBB')

    venta = {'paraLlevar': True, 'cliente': {'nombre': 'Ana Prueba', 'celular': '70000001'},
             'lineas': [{'productoId': 1, 'cantidad': 1}], 'totalEsperado': 1}
    grande = json.dumps({'relleno': 'x' * (150 * 1024)}).encode('utf-8')
    casos = [
        # (esperado, codigo esperado, caso, metodo, ruta, token, cuerpo, crudo, cabeceras)
        (401, 'TOKEN_AUSENTE', 'Sin token', 'GET', '/pedidos', None, None, None, None),
        (401, 'TOKEN_INVALIDO', 'Token con la firma alterada', 'GET', '/pedidos', alterado, None, None, None),
        (403, 'ROL_SIN_PERMISO', 'Cocina intenta vender', 'POST', '/pedidos', cocina, venta, None, None),
        (403, 'ROL_SIN_PERMISO', 'Cocina intenta cancelar', 'POST', '/pedidos/1/cancelacion', cocina,
         {'motivo': 'prueba'}, None, None),
        (403, 'ROL_SIN_PERMISO', 'Cocina intenta agregar a un pedido', 'POST', '/pedidos/1/lineas', cocina,
         {'lineas': [], 'totalEsperado': 0}, None, None),
        (400, 'VENTA_INVALIDA', 'Celular que no es boliviano', 'POST', '/pedidos', recepcion,
         dict(venta, cliente={'nombre': 'Ana Prueba', 'celular': '12345678'}), None, None),
        (400, 'VENTA_INVALIDA', 'Nombre con un caracter nulo', 'POST', '/pedidos', recepcion,
         dict(venta, cliente={'nombre': 'Ana\u0000Prueba'}), None, None),
        (400, 'VENTA_INVALIDA', 'Venta sin productos (CA-02.2)', 'POST', '/pedidos', recepcion,
         dict(venta, lineas=[]), None, None),
        (400, 'VENTA_INVALIDA', 'Cantidad fuera de rango (1000)', 'POST', '/pedidos', recepcion,
         dict(venta, lineas=[{'productoId': 1, 'cantidad': 1000}]), None, None),
        (400, 'JSON_INVALIDO', 'Cuerpo que no es JSON', 'POST', '/pedidos', recepcion, None,
         b'{esto no es json', None),
        (400, 'FILTRO_INVALIDO', 'Filtro de estado que no existe', 'GET', '/pedidos?estado=quemado',
         recepcion, None, None, None),
        (400, 'ID_INVALIDO', 'Numero de pedido que no es valido', 'GET', '/pedidos/abc', recepcion,
         None, None, None),
        (400, 'MOTIVO_INVALIDO', 'Cancelar sin motivo', 'POST', '/pedidos/1/cancelacion', recepcion,
         {'motivo': '   '}, None, None),
        (413, 'CUERPO_DEMASIADO_GRANDE', 'Cuerpo de 150 KB, sin token', 'POST', '/pedidos', None, None,
         grande, None),
        (415, 'FORMATO_NO_SOPORTADO', 'Cuerpo con otro juego de caracteres, sin token', 'POST', '/pedidos',
         None, None, b'{}', {'Content-Type': 'application/json; charset=latin9'}),
        # La disponibilidad de los productos (RF-13, tarjeta 08). Ninguno de estos cambia la carta.
        (401, 'TOKEN_AUSENTE', 'Marcar un producto agotado sin token', 'PATCH', '/productos/1/disponibilidad',
         None, {'disponible': False}, None, None),
        (400, 'ID_INVALIDO', 'Numero de producto que no es valido', 'PATCH', '/productos/abc/disponibilidad',
         cocina, {'disponible': False}, None, None),
        (400, 'DISPONIBILIDAD_INVALIDA', 'Marcar con un campo de mas (el precio)', 'PATCH',
         '/productos/1/disponibilidad', cocina, {'disponible': False, 'precio': 1}, None, None),
        (404, 'PRODUCTO_NO_ENCONTRADO', 'Marcar un producto que no existe', 'PATCH',
         '/productos/2147483647/disponibilidad', recepcion, {'disponible': False}, None, None),
        (400, 'DISPONIBILIDAD_INVALIDA', 'Agotar una categoria que no existe', 'PATCH',
         '/productos/disponibilidad', cocina, {'categoria': 'pasta', 'disponible': False}, None, None),
    ]

    print('\n| Esperado | Caso | Peticion | Obtenido | Resultado |')
    print('|---|---|---|---|---|')
    bien = 0
    for esperado, codigo, que, metodo, ruta, token, cuerpo, crudo, cabeceras in casos:
        estado, resp = pedir(metodo, ruta, token, cuerpo, crudo, cabeceras)
        obtenido = (resp.get('error') or {}).get('codigo', '')
        ok = estado == esperado and obtenido == codigo
        bien += ok
        print('| %s %s | %s | `%s %s` | %s %s | %s |' % (
            esperado, codigo, que, metodo, ruta, estado, obtenido, 'OK' if ok else 'DISTINTO'))

    # CA-01.2: la contrasena equivocada. Un solo intento, el ultimo (ver arriba).
    os.environ['KEYCLOAK_DEMO_PASSWORD'] = 'equivocada-%s' % os.getpid()
    try:
        identidad.obtener_token('recepcion.demo', informar=callado)
        rechazado, detalle = False, 'Keycloak entrego un token'
    except SystemExit as salida:
        rechazado, detalle = True, str(salida).strip()
    bien += rechazado
    print('| sin token | Acceso con la contrasena equivocada (CA-01.2) | Keycloak, recepcion.demo | %s | %s |'
          % (detalle, 'OK' if rechazado else 'DISTINTO'))

    total = len(casos) + 1
    print('\n%d de %d como se esperaba' % (bien, total))
    print('TODO CORRECTO' if bien == total else 'HAY FALLOS')
    sys.exit(0 if bien == total else 1)
