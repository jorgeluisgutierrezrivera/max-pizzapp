# -*- coding: utf-8 -*-
"""Comprueba la disponibilidad de los productos (RF-13) con tokens REALES y la base REAL.

Las pruebas del backend (npm test) simulan la base. Esta es la otra mitad: que la consulta
funcione contra el esquema de verdad, que los dos roles marquen y repongan, y los dos
criterios de aceptacion:

  * CA-13.1: marcado agotado, deja de poder venderse (409 PRODUCTO_NO_DISPONIBLE);
  * CA-13.2: un pedido que ya lo llevaba sigue igual.

Uso, con el entorno levantado y las contrasenas de demostracion:

    python pruebas/api/probar_disponibilidad.py

Contra el despliegue publico (fuera del horario de atencion, de 18:00 a 23:30):

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        python3 pruebas/api/probar_disponibilidad.py

Usa UNA BEBIDA, que en la carta son ficticias (por omision, "Gaseosa 2 L"; otra con
PRODUCTO="..."), y una pizza para el pedido de prueba, que nunca se marca. Al terminar deja la
bebida como estaba y cancela el pedido que creo ("Prueba Disponibilidad", 70000009). La
contrasena se lee del .env y nunca se imprime; los tokens tampoco.
"""
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'base_api', os.path.join(AQUI, 'probar_salud_y_token.py'))
base_api = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base_api)
identidad, pedir, comprobar, resultados = (
    base_api.identidad, base_api.pedir, base_api.comprobar, base_api.resultados)
API = base_api.API

BEBIDA = os.environ.get('PRODUCTO', 'Gaseosa 2 L')
PIZZA = 'Peperoni'


def llamar(metodo, ruta, token, cuerpo=None, crudo=None):
    datos = crudo if crudo is not None else (None if cuerpo is None else json.dumps(cuerpo).encode('utf-8'))
    peticion = urllib.request.Request(API + ruta, method=metodo, data=datos)
    peticion.add_header('Content-Type', 'application/json')
    if token:
        peticion.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(peticion, timeout=15) as r:
            return r.status, json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode('utf-8'))


def codigo(cuerpo):
    return cuerpo.get('error', {}).get('codigo')


def marcar(producto_id, token, disponible):
    return llamar('PATCH', '/productos/%s/disponibilidad' % producto_id, token, {'disponible': disponible})


def carta(token):
    _, cuerpo = pedir('/productos', token)
    return {p['nombre']: p for p in cuerpo['productos']}


def venta(lineas, total):
    return {
        'paraLlevar': True,
        'cliente': {'nombre': 'Prueba Disponibilidad', 'celular': '70000009'},
        'observacion': 'prueba de la tarjeta 08',
        'lineas': lineas,
        'totalEsperado': total,
    }


if __name__ == '__main__':
    print('API:', API)
    print('Keycloak:', identidad.KC)

    recepcion = identidad.obtener_token('recepcion.demo', informar=lambda *_: None)['access_token']
    cocina = identidad.obtener_token('cocina.demo', informar=lambda *_: None)['access_token']

    productos = carta(recepcion)
    for nombre in (BEBIDA, PIZZA):
        if nombre not in productos:
            sys.exit('Falta en la carta: %s' % nombre)
    bebida, pizza = productos[BEBIDA], productos[PIZZA]
    if bebida['categoria'] != 'bebida':
        sys.exit('%s no es una bebida: esta prueba solo marca bebidas.' % BEBIDA)
    original = bebida['disponible']
    pedido_id = None
    print('Producto de la prueba: %s (id %s), %s al empezar.' % (
        BEBIDA, bebida['id'], 'disponible' if original else 'agotado'))

    try:
        if not original:
            estado, _ = marcar(bebida['id'], recepcion, True)
            comprobar('se repone para empezar desde disponible', estado, 200)

        print('\n--- CA-13.2: el pedido que ya la lleva ---')
        lineas = [{'productoId': pizza['id'], 'cantidad': 1}, {'productoId': bebida['id'], 'cantidad': 1}]
        total = round(pizza['precio'] + bebida['precio'], 2)
        estado, cuerpo = llamar('POST', '/pedidos', recepcion, venta(lineas, total))
        comprobar('recepcion vende una pizza y la bebida', estado, 201)
        pedido_id = cuerpo['pedido']['id']
        antes = cuerpo['pedido']

        print('\n--- marcar y reponer, con los dos roles ---')
        estado, cuerpo = marcar(bebida['id'], cocina, False)
        comprobar('cocina la marca agotada', (estado, cuerpo.get('producto', {}).get('disponible')), (200, False))
        comprobar('  la carta la muestra agotada', carta(recepcion)[BEBIDA]['disponible'], False)
        estado, cuerpo = marcar(bebida['id'], recepcion, False)
        comprobar('marcarla otra vez igual: 200, sin cambios', (estado, cuerpo['producto']['disponible']), (200, False))

        _, cuerpo = pedir('/pedidos/%s' % pedido_id, recepcion)
        despues = cuerpo['pedido']
        iguales = ((despues['lineas'], despues['total'], despues['estado'])
                   == (antes['lineas'], antes['total'], antes['estado']))
        comprobar('CA-13.2: el pedido sigue con sus lineas, total y estado', iguales, True,
                  '%d lineas, Bs %s, %s' % (len(despues['lineas']), despues['total'], despues['estado']))

        estado, cuerpo = llamar('POST', '/pedidos', recepcion, venta(lineas, total))
        comprobar('CA-13.1: una venta nueva con la bebida agotada: 409',
                  (estado, codigo(cuerpo), (cuerpo.get('error', {}).get('producto') or {}).get('id')),
                  (409, 'PRODUCTO_NO_DISPONIBLE', bebida['id']))

        estado, cuerpo = marcar(bebida['id'], recepcion, True)
        comprobar('recepcion la repone', (estado, cuerpo['producto']['disponible']), (200, True))
        comprobar('  la carta la vuelve a ofrecer', carta(cocina)[BEBIDA]['disponible'], True)

        print('\n--- los errores ---')
        estado, cuerpo = llamar('PATCH', '/productos/%s/disponibilidad' % bebida['id'], None, {'disponible': False})
        comprobar('sin token: 401', (estado, codigo(cuerpo)), (401, 'TOKEN_AUSENTE'))
        estado, cuerpo = marcar(2147483647, cocina, False)
        comprobar('un producto que no existe: 404', (estado, codigo(cuerpo)), (404, 'PRODUCTO_NO_ENCONTRADO'))
        estado, cuerpo = llamar('PATCH', '/productos/abc/disponibilidad', cocina, {'disponible': False})
        comprobar('un numero de producto invalido: 400', (estado, codigo(cuerpo)), (400, 'ID_INVALIDO'))
        estado, cuerpo = llamar('PATCH', '/productos/%s/disponibilidad' % bebida['id'], cocina,
                                {'disponible': False, 'precio': 1})
        comprobar('un campo de mas (el precio): 400', (estado, codigo(cuerpo)), (400, 'DISPONIBILIDAD_INVALIDA'))
        comprobar('  y la bebida sigue disponible, con su precio',
                  (carta(cocina)[BEBIDA]['disponible'], carta(cocina)[BEBIDA]['precio']), (True, bebida['precio']))
    finally:
        # Lo que la prueba toco, como estaba: la bebida y el pedido de prueba.
        if pedido_id is not None:
            llamar('POST', '/pedidos/%s/cancelacion' % pedido_id, recepcion, {'motivo': 'prueba de la tarjeta 08'})
        marcar(bebida['id'], recepcion, original)
        final = carta(recepcion)[BEBIDA]['disponible']
        print('\nAl terminar: %s quedo %s, como estaba; el pedido de prueba %s, cancelado.' % (
            BEBIDA, 'disponible' if final else 'agotado', pedido_id))
        resultados.append(final == original)

    print('\n' + ('TODO CORRECTO' if all(resultados) else 'HAY FALLOS'))
    sys.exit(0 if all(resultados) else 1)
