# -*- coding: utf-8 -*-
"""Comprueba la disponibilidad de los productos (RF-13) con tokens REALES y la base REAL.

Las pruebas del backend (npm test) simulan la base. Esta es la otra mitad: que la consulta
funcione contra el esquema de verdad, que cada rol marque y reponga lo suyo, y los dos
criterios de aceptacion:

  * CA-13.1: marcado agotado, deja de poder venderse (409 PRODUCTO_NO_DISPONIBLE);
  * CA-13.2: un pedido que ya lo llevaba sigue igual.

Cada rol, lo suyo (D-76): recepcion agota y repone la bebida, y cocina los extras. Con lo del
otro rol, cada uno recibe 403 ROL_SIN_PERMISO y nada cambia.

Uso, con el entorno levantado y las contrasenas de demostracion:

    python pruebas/api/probar_disponibilidad.py

Contra el despliegue publico (fuera del horario de atencion, de 18:00 a 23:30):

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        python3 pruebas/api/probar_disponibilidad.py

Usa UNA BEBIDA (por omision, "Soda 2 L"; otra con PRODUCTO="..."), que en produccion se
agota unos segundos, fuera del horario, y una pizza para el pedido de prueba, que nunca se marca. La categoria entera
(D-70) se prueba con los EXTRAS, que son ficticios; tambien el 403 de recepcion, para que un
servidor sin la D-76 no agote nada que no se reponga al final. Al terminar deja la bebida y cada
extra como estaban y cancela el pedido que creo ("Prueba Disponibilidad", 70000009). La
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

BEBIDA = os.environ.get('PRODUCTO', 'Soda 2 L')
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


def marcar_categoria(categoria, token, disponible):
    return llamar('PATCH', '/productos/disponibilidad', token, {'categoria': categoria, 'disponible': disponible})


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
    extras_originales = {p['id']: p['disponible'] for p in productos.values() if p['categoria'] == 'extra'}
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

        print('\n--- la bebida la marca y la repone recepcion (D-76) ---')
        estado, cuerpo = marcar(bebida['id'], cocina, False)
        comprobar('cocina no puede agotarla: 403, de otro rol',
                  (estado, codigo(cuerpo), cuerpo.get('error', {}).get('categoria')),
                  (403, 'ROL_SIN_PERMISO', 'bebida'))
        comprobar('  y la bebida sigue disponible', carta(recepcion)[BEBIDA]['disponible'], True)
        estado, cuerpo = marcar(bebida['id'], recepcion, False)
        comprobar('recepcion la marca agotada', (estado, cuerpo.get('producto', {}).get('disponible')), (200, False))
        comprobar('  la carta la muestra agotada', carta(cocina)[BEBIDA]['disponible'], False)
        estado, cuerpo = marcar(bebida['id'], recepcion, False)
        comprobar('marcarla otra vez igual: 200, sin cambios', (estado, cuerpo['producto']['disponible']), (200, False))
        estado, cuerpo = marcar(bebida['id'], cocina, True)
        comprobar('cocina tampoco puede reponerla: 403', (estado, codigo(cuerpo)), (403, 'ROL_SIN_PERMISO'))

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

        print('\n--- una categoria entera: los extras, que maneja cocina (D-70, D-76) ---')
        estado, cuerpo = marcar_categoria('extra', recepcion, False)
        comprobar('recepcion no puede agotarlos: 403, de otro rol',
                  (estado, codigo(cuerpo), cuerpo.get('error', {}).get('categoria')),
                  (403, 'ROL_SIN_PERMISO', 'extra'))
        comprobar('  y ningun extra cambio',
                  {p['id']: p['disponible'] for p in carta(cocina).values() if p['categoria'] == 'extra'},
                  extras_originales)
        estado, cuerpo = marcar_categoria('extra', cocina, False)
        disponibles_antes = sorted(i for i, d in extras_originales.items() if d)
        comprobar('cocina agota todos los extras: los que estaban disponibles',
                  (estado, cuerpo.get('cambiados')), (200, disponibles_antes))
        extras = {p['id']: p for p in carta(recepcion).values() if p['categoria'] == 'extra'}
        comprobar('  la carta los muestra todos agotados', all(not p['disponible'] for p in extras.values()), True)
        comprobar('  las pizzas y las bebidas no se tocaron',
                  (carta(recepcion)[PIZZA]['disponible'], carta(recepcion)[BEBIDA]['disponible']), (True, True))
        un_extra = sorted(extras)[0]
        con_extra = [{'productoId': pizza['id'], 'cantidad': 1, 'extras': [un_extra]}]
        estado, cuerpo = llamar('POST', '/pedidos', recepcion,
                                venta(con_extra, round(pizza['precio'] + extras[un_extra]['precio'], 2)))
        comprobar('una venta con un extra agotado: 409', (estado, codigo(cuerpo)), (409, 'PRODUCTO_NO_DISPONIBLE'))
        estado, cuerpo = marcar_categoria('extra', cocina, False)
        comprobar('agotarlos otra vez: 200, nada que cambiar', (estado, cuerpo.get('cambiados')), (200, []))
        estado, cuerpo = marcar(un_extra, recepcion, True)
        comprobar('recepcion no puede reponer un extra: 403', (estado, codigo(cuerpo)), (403, 'ROL_SIN_PERMISO'))
        comprobar('  y sigue agotado', carta(cocina)[extras[un_extra]['nombre']]['disponible'], False)
        estado, cuerpo = marcar_categoria('extra', cocina, True)
        comprobar('cocina los repone todos', (estado, len(cuerpo.get('cambiados', []))), (200, len(extras)))
        estado, cuerpo = marcar_categoria('pasta', cocina, False)
        comprobar('una categoria que no existe: 400', (estado, codigo(cuerpo)), (400, 'DISPONIBILIDAD_INVALIDA'))
        estado, cuerpo = llamar('PATCH', '/productos/disponibilidad', None, {'categoria': 'extra', 'disponible': False})
        comprobar('sin token: 401', (estado, codigo(cuerpo)), (401, 'TOKEN_AUSENTE'))

        print('\n--- los errores ---')
        estado, cuerpo = llamar('PATCH', '/productos/%s/disponibilidad' % bebida['id'], None, {'disponible': False})
        comprobar('sin token: 401', (estado, codigo(cuerpo)), (401, 'TOKEN_AUSENTE'))
        estado, cuerpo = marcar(2147483647, cocina, False)
        comprobar('un producto que no existe: 404', (estado, codigo(cuerpo)), (404, 'PRODUCTO_NO_ENCONTRADO'))
        estado, cuerpo = llamar('PATCH', '/productos/abc/disponibilidad', cocina, {'disponible': False})
        comprobar('un numero de producto invalido: 400', (estado, codigo(cuerpo)), (400, 'ID_INVALIDO'))
        estado, cuerpo = llamar('PATCH', '/productos/%s/disponibilidad' % bebida['id'], recepcion,
                                {'disponible': False, 'precio': 1})
        comprobar('un campo de mas (el precio): 400', (estado, codigo(cuerpo)), (400, 'DISPONIBILIDAD_INVALIDA'))
        comprobar('  y la bebida sigue disponible, con su precio',
                  (carta(cocina)[BEBIDA]['disponible'], carta(cocina)[BEBIDA]['precio']), (True, bebida['precio']))
    finally:
        # Lo que la prueba toco, como estaba, cada cosa con el rol que la maneja: la bebida,
        # los extras y el pedido de prueba.
        if pedido_id is not None:
            llamar('POST', '/pedidos/%s/cancelacion' % pedido_id, recepcion, {'motivo': 'prueba de la tarjeta 08'})
        marcar(bebida['id'], recepcion, original)
        for extra_id, disponible in extras_originales.items():
            marcar(extra_id, cocina, disponible)
        finales = {p['id']: p['disponible'] for p in carta(recepcion).values() if p['categoria'] == 'extra'}
        print('Los extras, como estaban: %s.' % ('si' if finales == extras_originales else 'NO'))
        resultados.append(finales == extras_originales)
        final = carta(recepcion)[BEBIDA]['disponible']
        print('\nAl terminar: %s quedo %s, como estaba; el pedido de prueba %s, cancelado.' % (
            BEBIDA, 'disponible' if final else 'agotado', pedido_id))
        resultados.append(final == original)

    print('\n' + ('TODO CORRECTO' if all(resultados) else 'HAY FALLOS'))
    sys.exit(0 if all(resultados) else 1)
