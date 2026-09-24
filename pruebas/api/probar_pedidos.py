# -*- coding: utf-8 -*-
"""Comprueba los pedidos de punta a punta: token REAL, base REAL, carta REAL.

Las pruebas del backend (npm test) simulan la base para ver QUE le llega y en que orden.
Esta es la otra mitad: que las consultas funcionen contra el esquema de verdad, que los
precios guardados sean los de la tabla del plan 05, seccion 6, que el ciclo de estados se
cumpla con los dos roles, y que dos cambios simultaneos sobre el mismo pedido no pasen los
dos: eso lo decide el bloqueo de la base, que solo existe en la base real.

Uso, con el entorno levantado, la migracion 06 aplicada y las contrasenas de demostracion:

    python pruebas/api/probar_pedidos.py

Contra el despliegue publico:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        python3 pruebas/api/probar_pedidos.py

Crea pedidos de prueba con datos ficticios ("Ana Prueba", 70000001) y AL FINAL LOS CIERRA:
cancela los que siguen en cocina y entrega los listos, para no dejar nada en la cola. Solo
toca los pedidos que ella misma creo. La contrasena se lee del .env y nunca se imprime; los
tokens tampoco.
"""
import importlib.util
import json
import os
import sys
import threading
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


def llamar(metodo, ruta, token, cuerpo=None):
    datos = None if cuerpo is None else json.dumps(cuerpo).encode('utf-8')
    peticion = urllib.request.Request(API + ruta, method=metodo, data=datos)
    peticion.add_header('Content-Type', 'application/json')
    if token:
        peticion.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(peticion, timeout=15) as r:
            return r.status, json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode('utf-8'))


def enviar(ruta, token, cuerpo):
    return llamar('POST', ruta, token, cuerpo)


def venta(lineas, total, **cambios):
    cuerpo = {
        'paraLlevar': True,
        'cliente': {'nombre': 'Ana Prueba', 'celular': '70000001'},
        'observacion': 'pedido de prueba',
        'lineas': lineas,
        'totalEsperado': total,
    }
    cuerpo.update(cambios)
    return cuerpo


def codigo(cuerpo):
    return cuerpo.get('error', {}).get('codigo')


if __name__ == '__main__':
    print('API:', API)
    print('Keycloak:', identidad.KC)

    recepcion = identidad.obtener_token('recepcion.demo', informar=lambda *_: None)['access_token']
    cocina = identidad.obtener_token('cocina.demo', informar=lambda *_: None)['access_token']

    # Los ids salen de la carta real: la prueba no supone numeros.
    _, cuerpo = pedir('/productos', recepcion)
    id_de = {p['nombre']: p['id'] for p in cuerpo['productos']}
    for nombre in ('Salame', 'Peperoni', 'Carnívora', 'Criolla española', 'Hawaiana', 'Choclo',
                   'Gaseosa 2 L', 'Extra queso', 'Extra choclo'):
        if nombre not in id_de:
            print('Falta en la carta:', nombre)
            sys.exit(1)

    print('\n--- quien puede crear ---')
    una = venta([{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50)
    estado, cuerpo = enviar('/pedidos', None, una)
    comprobar('POST /pedidos sin token', estado, 401, codigo(cuerpo))
    estado, cuerpo = enviar('/pedidos', cocina, una)
    comprobar('POST /pedidos con el token de cocina', estado, 403, codigo(cuerpo))

    print('\n--- la tabla del plan 05, seccion 6, guardada en la base real ---')
    tabla = [
        ('1 Peperoni', [{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50, 'pendiente'),
        ('1 mitad Salame, mitad Peperoni',
         [{'productoId': id_de['Salame'], 'mitadId': id_de['Peperoni'], 'cantidad': 1}], 47.5, 'pendiente'),
        ('1 mitad Carnívora, mitad Criolla española',
         [{'productoId': id_de['Carnívora'], 'mitadId': id_de['Criolla española'], 'cantidad': 1}], 62.5, 'pendiente'),
        ('2 mitad Salame, mitad Peperoni',
         [{'productoId': id_de['Salame'], 'mitadId': id_de['Peperoni'], 'cantidad': 2}], 95, 'pendiente'),
        ('1 Hawaiana con extra queso',
         [{'productoId': id_de['Hawaiana'], 'cantidad': 1, 'extras': [id_de['Extra queso']]}], 58, 'pendiente'),
        ('3 Choclo, cada una con extra choclo',
         [{'productoId': id_de['Choclo'], 'cantidad': 3, 'extras': [id_de['Extra choclo']]}], 150, 'pendiente'),
        ('solo 2 gaseosas: nace lista (D-32)',
         [{'productoId': id_de['Gaseosa 2 L'], 'cantidad': 2}], 36, 'listo'),
    ]
    creados = []
    for nombre, lineas, total, estado_inicial in tabla:
        estado, cuerpo = enviar('/pedidos', recepcion, venta(lineas, total))
        pedido = cuerpo.get('pedido', {})
        creados.append(pedido.get('id'))
        comprobar(nombre, (estado, pedido.get('total'), pedido.get('estado')),
                  (201, total, estado_inicial), '#%s' % pedido.get('id'))

    print('\n--- lo que devuelve un pedido recien creado ---')
    estado, cuerpo = enviar('/pedidos', recepcion, venta([
        {'productoId': id_de['Salame'], 'mitadId': id_de['Peperoni'], 'cantidad': 2},
        {'productoId': id_de['Hawaiana'], 'cantidad': 1, 'extras': [id_de['Extra queso']]},
        {'productoId': id_de['Gaseosa 2 L'], 'cantidad': 2},
    ], 189, observacion='sin cebolla'))
    pedido = cuerpo.get('pedido', {})
    creados.append(pedido.get('id'))
    comprobar('venta mixta de Bs 189', (estado, pedido.get('total')), (201, 189), '#%s' % pedido.get('id'))
    comprobar('  el cliente, con su celular (recepcion lo ve)', pedido.get('cliente'),
              {'nombre': 'Ana Prueba', 'celular': '70000001'})
    comprobar('  para llevar y la observacion', (pedido.get('paraLlevar'), pedido.get('observacion')),
              (True, 'sin cebolla'))
    lineas = pedido.get('lineas', [])
    comprobar('  tres lineas; el extra no es una de ellas', len(lineas), 3)
    comprobar('  la mitad y mitad guarda sus dos sabores y la mitad exacta',
              (lineas[0]['producto']['nombre'], lineas[0]['mitad']['nombre'], lineas[0]['precioUnitario']),
              ('Salame', 'Peperoni', 47.5))
    comprobar('  el extra viaja dentro de su pizza, con su cantidad',
              [(e['producto']['nombre'], e['cantidad'], e['subtotal']) for e in lineas[1]['extras']],
              [('Extra queso', 1, 8)])

    print('\n--- sin celular y para comer aqui ---')
    estado, cuerpo = enviar('/pedidos', recepcion, venta(
        [{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50,
        paraLlevar=False, cliente={'nombre': 'Usuario Demo'}))
    pedido = cuerpo.get('pedido', {})
    creados.append(pedido.get('id'))
    comprobar('cliente sin celular', (estado, pedido.get('cliente'), pedido.get('paraLlevar')),
              (201, {'nombre': 'Usuario Demo', 'celular': None}, False))

    print('\n--- lo que el servidor rechaza ---')
    estado, cuerpo = enviar('/pedidos', recepcion, venta([{'productoId': id_de['Peperoni'], 'cantidad': 1}], 45))
    comprobar('el total no coincide', (estado, codigo(cuerpo)), (409, 'PRECIO_CAMBIADO'),
              'total correcto: %s' % cuerpo.get('error', {}).get('totalCorrecto'))
    rechazos = [
        ('celular que no es boliviano', venta([{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50,
                                               cliente={'nombre': 'Ana Prueba', 'celular': '12345678'})),
        ('sin decir si es para llevar', venta([{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50, paraLlevar=None)),
        ('la otra mitad es una bebida', venta([{'productoId': id_de['Salame'], 'mitadId': id_de['Gaseosa 2 L'],
                                                'cantidad': 1}], 31.5)),
        ('un extra vendido solo', venta([{'productoId': id_de['Extra queso'], 'cantidad': 1}], 8)),
        ('un producto que no existe', venta([{'productoId': 999999, 'cantidad': 1}], 10)),
        ('una venta vacia', venta([], 0)),
    ]
    for nombre, cuerpo_venta in rechazos:
        estado, cuerpo = enviar('/pedidos', recepcion, cuerpo_venta)
        comprobar(nombre, (estado, codigo(cuerpo)), (400, 'VENTA_INVALIDA'))

    def nuevo_pedido():
        estado, cuerpo = enviar('/pedidos', recepcion, venta([{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50))
        pedido_id = cuerpo.get('pedido', {}).get('id')
        creados.append(pedido_id)
        return pedido_id

    def cambiar(pedido_id, token, estado):
        return llamar('PATCH', '/pedidos/%s/estado' % pedido_id, token, {'estado': estado})

    print('\n--- el ciclo completo, con los dos roles ---')
    pid = nuevo_pedido()
    estado, cuerpo = cambiar(pid, cocina, 'en_preparacion')
    comprobar('cocina lo empieza', (estado, cuerpo.get('pedido', {}).get('estado')), (200, 'en_preparacion'), '#%s' % pid)
    estado, cuerpo = cambiar(pid, cocina, 'listo')
    comprobar('cocina lo marca listo', (estado, cuerpo.get('pedido', {}).get('estado')), (200, 'listo'))
    estado, cuerpo = cambiar(pid, recepcion, 'entregado')
    comprobar('recepcion lo entrega', (estado, cuerpo.get('pedido', {}).get('estado')), (200, 'entregado'))
    estado, cuerpo = llamar('GET', '/pedidos/%s' % pid, recepcion)
    historial = cuerpo.get('pedido', {}).get('historial', [])
    roles = [(h['estado'], 'cocina' if 'ocina' in h['usuario'] else 'recepcion') for h in historial]
    comprobar('  el historial cuenta los cuatro pasos, con quien hizo cada uno', roles,
              [('pendiente', 'recepcion'), ('en_preparacion', 'cocina'), ('listo', 'cocina'),
               ('entregado', 'recepcion')])

    print('\n--- lo que cada rol no puede hacer ---')
    pid = nuevo_pedido()
    estado, cuerpo = cambiar(pid, recepcion, 'en_preparacion')
    comprobar('recepcion no empieza un pedido', (estado, codigo(cuerpo)), (403, 'ROL_SIN_PERMISO'))
    estado, cuerpo = cambiar(pid, cocina, 'listo')
    comprobar('no se salta de pendiente a listo', (estado, codigo(cuerpo)), (409, 'TRANSICION_NO_PERMITIDA'))
    estado, cuerpo = cambiar(pid, recepcion, 'entregado')
    comprobar('no se entrega lo que no esta listo (D-08)', (estado, codigo(cuerpo)), (409, 'TRANSICION_NO_PERMITIDA'))
    estado, cuerpo = llamar('POST', '/pedidos/%s/cancelacion' % pid, cocina, {'motivo': 'no hay queso'})
    comprobar('cocina no cancela', (estado, codigo(cuerpo)), (403, 'ROL_SIN_PERMISO'))
    estado, cuerpo = llamar('POST', '/pedidos/%s/cancelacion' % pid, recepcion, {'motivo': '   '})
    comprobar('cancelar sin motivo', (estado, codigo(cuerpo)), (400, 'MOTIVO_INVALIDO'))

    print('\n--- la baja: cancelar con motivo (D-33) ---')
    estado, cuerpo = llamar('POST', '/pedidos/%s/cancelacion' % pid, recepcion, {'motivo': 'El cliente se fue'})
    comprobar('recepcion lo cancela', (estado, cuerpo.get('pedido', {}).get('estado')), (200, 'cancelado'), '#%s' % pid)
    estado, cuerpo = llamar('GET', '/pedidos/%s' % pid, recepcion)
    ultimo = (cuerpo.get('pedido', {}).get('historial') or [{}])[-1]
    comprobar('  el pedido no se borra: se sigue pudiendo leer', estado, 200)
    comprobar('  y el motivo queda en el historial', (ultimo.get('estado'), ultimo.get('motivo')),
              ('cancelado', 'El cliente se fue'))
    estado, cuerpo = llamar('POST', '/pedidos/%s/cancelacion' % pid, recepcion, {'motivo': 'otra vez'})
    comprobar('cancelarlo de nuevo', (estado, codigo(cuerpo)), (409, 'TRANSICION_NO_PERMITIDA'))

    print('\n--- la carrera: dos cambios a la vez sobre el mismo pedido ---')
    pid = nuevo_pedido()
    cambiar(pid, cocina, 'en_preparacion')
    respuestas = []
    hilos = [threading.Thread(target=lambda: respuestas.append(cambiar(pid, cocina, 'listo')[0]))
             for _ in range(2)]
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()
    comprobar('uno pasa y el otro recibe 409', sorted(respuestas), [200, 409], '#%s' % pid)
    estado, cuerpo = llamar('GET', '/pedidos/%s' % pid, recepcion)
    comprobar('  y el historial registra un solo "listo"',
              [h['estado'] for h in cuerpo.get('pedido', {}).get('historial', [])].count('listo'), 1)

    print('\n--- la cola ---')
    estado, cuerpo = llamar('GET', '/pedidos?estado=pendiente,en_preparacion', cocina)
    cola = cuerpo.get('pedidos', [])
    comprobar('cocina lee su cola', estado, 200, '%d pedidos' % len(cola))
    comprobar('  sin el celular de nadie (D-31)', any('celular' in p['cliente'] for p in cola), False)
    comprobar('  en orden de llegada', [p['creadoEn'] for p in cola] == sorted(p['creadoEn'] for p in cola), True)
    comprobar('  sin los listos: el pedido de solo bebidas no le llega (D-32)',
              all(p['estado'] in ('pendiente', 'en_preparacion') for p in cola), True)
    estado, cuerpo = llamar('GET', '/pedidos?estado=pagado', cocina)
    comprobar('un estado que no existe', (estado, codigo(cuerpo)), (400, 'FILTRO_INVALIDO'))
    estado, cuerpo = llamar('GET', '/pedidos/999999999', recepcion)
    comprobar('un pedido que no existe', (estado, codigo(cuerpo)), (404, 'PEDIDO_NO_ENCONTRADO'))

    print('\n--- limpieza: se cierran los pedidos que creo esta prueba ---')
    cerrados = 0
    for pid in [p for p in creados if p]:
        _, cuerpo = llamar('GET', '/pedidos/%s' % pid, recepcion)
        estado_actual = cuerpo.get('pedido', {}).get('estado')
        if estado_actual in ('pendiente', 'en_preparacion'):
            llamar('POST', '/pedidos/%s/cancelacion' % pid, recepcion, {'motivo': 'Pedido de prueba'})
            cerrados += 1
        elif estado_actual == 'listo':
            cambiar(pid, recepcion, 'entregado')
            cerrados += 1
    _, cuerpo = llamar('GET', '/pedidos', recepcion)
    quedan = [p['id'] for p in cuerpo.get('pedidos', []) if p['id'] in creados]
    comprobar('ningun pedido de la prueba queda activo', quedan, [], '%d cerrados' % cerrados)

    print('\n' + ('TODO CORRECTO' if all(resultados) else 'HAY FALLOS'))
    sys.exit(0 if all(resultados) else 1)
