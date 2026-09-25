# -*- coding: utf-8 -*-
"""Comprueba los pedidos de punta a punta: token REAL, base REAL, carta REAL.

Las pruebas del backend (npm test) simulan la base para ver QUE le llega y en que orden.
Esta es la otra mitad: que las consultas funcionen contra el esquema de verdad, que los
precios guardados sean los de la tabla del plan 05, seccion 6, que el ciclo de estados se
cumpla con los dos roles, y TRES CARRERAS que solo se pueden probar en la base real, porque
las decide su bloqueo:
  - dos cambios simultaneos sobre el mismo pedido: pasa uno;
  - muchas ventas a la vez: los numeros del dia salen seguidos, sin repetir ni saltar (D-35);
  - "Listo" y "Agregar una pizza" a la vez: gana el primero y el otro recibe 409 (D-37).

Uso, con el entorno levantado, las migraciones 06 y 07 aplicadas y las contrasenas de
demostracion:

    python pruebas/api/probar_pedidos.py

Contra el despliegue publico:

    API_URL=https://maxpizzapp.tech/api/v1 KEYCLOAK_URL=https://auth.maxpizzapp.tech \\
        python3 pruebas/api/probar_pedidos.py

Crea pedidos de prueba con datos ficticios ("Ana Prueba", 70000001) y AL FINAL LOS CIERRA:
cancela los pendientes, y los que cocina ya empezo, que no se cancelan (D-41), los termina y
los entrega, igual que los listos. No deja nada en la cola. Solo toca los pedidos que ella
misma creo. La contrasena se lee del .env y nunca se imprime; los
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
    for nombre in ('Salame', 'Peperoni', 'Carnívora', 'Cuatro quesos', 'Criolla española', 'Hawaiana', 'Choclo',
                   'Dos estaciones', 'Tres estaciones', 'Gaseosa 2 L', 'Extra queso', 'Extra choclo'):
        if nombre not in id_de:
            print('Falta en la carta:', nombre)
            sys.exit(1)

    print('\n--- las pizzas que se venden solo enteras (D-39) ---')
    solo_enteras = sorted(p['nombre'] for p in cuerpo['productos'] if p.get('soloEntera'))
    comprobar('la carta marca las tres especialidades armadas por sectores', solo_enteras,
              ['Criolla española', 'Dos estaciones', 'Tres estaciones'])

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
        # La tabla del plan 05 usaba Carnívora con Criolla española (62,50), que ya no vale: la
        # Criolla se vende solo entera (D-39). La mitad y mitad que termina en 50 centavos, con otra.
        ('1 mitad Carnívora, mitad Cuatro quesos',
         [{'productoId': id_de['Carnívora'], 'mitadId': id_de['Cuatro quesos'], 'cantidad': 1}], 57.5, 'pendiente'),
        ('2 mitad Salame, mitad Peperoni',
         [{'productoId': id_de['Salame'], 'mitadId': id_de['Peperoni'], 'cantidad': 2}], 95, 'pendiente'),
        ('1 Hawaiana con extra queso',
         [{'productoId': id_de['Hawaiana'], 'cantidad': 1, 'extras': [id_de['Extra queso']]}], 58, 'pendiente'),
        ('3 Choclo, cada una con extra choclo',
         [{'productoId': id_de['Choclo'], 'cantidad': 3, 'extras': [id_de['Extra choclo']]}], 150, 'pendiente'),
    ]
    creados = []
    numeros = []
    for nombre, lineas, total, estado_inicial in tabla:
        estado, cuerpo = enviar('/pedidos', recepcion, venta(lineas, total))
        pedido = cuerpo.get('pedido', {})
        creados.append(pedido.get('id'))
        numeros.append(pedido.get('numero'))
        comprobar(nombre, (estado, pedido.get('total'), pedido.get('estado')),
                  (201, total, estado_inicial), 'Pedido %s (#%s)' % (pedido.get('numero'), pedido.get('id')))

    print('\n--- el numero del dia (D-35) ---')
    comprobar('cada pedido lleva su numero del dia', all(isinstance(n, int) and n > 0 for n in numeros), True,
              ' '.join(str(n) for n in numeros))
    comprobar('  seguidos, en el orden en que se vendieron',
              numeros == list(range(numeros[0], numeros[0] + len(numeros))), True)

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
    comprobar('  la version: 4 lineas guardadas (3 y el extra), ninguna agregada despues',
              (pedido.get('version'), [l.get('agregadoEn') for l in lineas]), (4, [None, None, None]))

    print('\n--- sin celular y para comer aqui ---')
    estado, cuerpo = enviar('/pedidos', recepcion, venta(
        [{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50,
        paraLlevar=False, cliente={'nombre': 'Usuario Demo'}))
    pedido = cuerpo.get('pedido', {})
    creados.append(pedido.get('id'))
    comprobar('cliente sin celular', (estado, pedido.get('cliente'), pedido.get('paraLlevar')),
              (201, {'nombre': 'Usuario Demo', 'celular': None}, False))

    print('\n--- la venta directa de bebidas (D-38) ---')
    directa = {'ventaDirecta': True, 'lineas': [{'productoId': id_de['Gaseosa 2 L'], 'cantidad': 2}],
               'totalEsperado': 36}
    estado, cuerpo = enviar('/pedidos', recepcion, directa)
    vendida = cuerpo.get('pedido', {})
    comprobar('2 gaseosas, sin nombre: nace entregada',
              (estado, vendida.get('estado'), vendida.get('total')), (201, 'entregado', 36), '#%s' % vendida.get('id'))
    comprobar('  sin cliente, sin para llevar y sin numero del dia',
              (vendida.get('cliente'), vendida.get('paraLlevar'), vendida.get('numero')), (None, None, None))
    estado, cuerpo = llamar('GET', '/pedidos/%s' % vendida.get('id'), recepcion)
    comprobar('  queda quien la vendio, en el historial',
              [(h['estado'], 'ocina' in h['usuario']) for h in cuerpo.get('pedido', {}).get('historial', [])],
              [('entregado', False)])
    _, cuerpo = llamar('GET', '/pedidos', recepcion)
    comprobar('  y no aparece entre los activos',
              vendida.get('id') in [p['id'] for p in cuerpo.get('pedidos', [])], False)
    estado, cuerpo = enviar('/pedidos', recepcion, venta([{'productoId': id_de['Gaseosa 2 L'], 'cantidad': 2}], 36))
    comprobar('solo bebidas a nombre de un cliente: se rechaza', (estado, codigo(cuerpo)), (400, 'VENTA_INVALIDA'),
              cuerpo.get('error', {}).get('mensaje'))
    estado, cuerpo = enviar('/pedidos', recepcion,
                            dict(directa, lineas=[{'productoId': id_de['Peperoni'], 'cantidad': 1}], totalEsperado=50))
    comprobar('venta directa con una pizza: se rechaza', (estado, codigo(cuerpo)), (400, 'VENTA_INVALIDA'))
    estado, cuerpo = enviar('/pedidos', recepcion, dict(directa, cliente={'nombre': 'Ana Prueba'}))
    comprobar('venta directa con nombre: se rechaza', (estado, codigo(cuerpo)), (400, 'VENTA_INVALIDA'))
    estado, cuerpo = enviar('/pedidos', cocina, directa)
    comprobar('cocina no vende', (estado, codigo(cuerpo)), (403, 'ROL_SIN_PERMISO'))

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
        ('Dos estaciones como mitad: se vende solo entera (D-39)',
         venta([{'productoId': id_de['Salame'], 'mitadId': id_de['Dos estaciones'], 'cantidad': 1}], 47.5)),
        ('Carnívora con Criolla española: la Criolla se vende solo entera (D-39)',
         venta([{'productoId': id_de['Carnívora'], 'mitadId': id_de['Criolla española'], 'cantidad': 1}], 62.5)),
        ('Tres estaciones como primera mitad (D-39)',
         venta([{'productoId': id_de['Tres estaciones'], 'mitadId': id_de['Peperoni'], 'cantidad': 1}], 50)),
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

    def cambiar(pedido_id, token, estado, version=None):
        cuerpo = {'estado': estado}
        if version is not None:
            cuerpo['version'] = version
        return llamar('PATCH', '/pedidos/%s/estado' % pedido_id, token, cuerpo)

    def agregar(pedido_id, token, lineas, total):
        return llamar('POST', '/pedidos/%s/lineas' % pedido_id, token, {'lineas': lineas, 'totalEsperado': total})

    SODA = [{'productoId': id_de['Gaseosa 2 L'], 'cantidad': 1}]
    PIZZA = [{'productoId': id_de['Salame'], 'mitadId': id_de['Peperoni'], 'cantidad': 1,
              'extras': [id_de['Extra queso']]}]

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
    pid = nuevo_pedido()
    cambiar(pid, cocina, 'en_preparacion')
    estado, cuerpo = llamar('POST', '/pedidos/%s/cancelacion' % pid, recepcion, {'motivo': 'El cliente se fue'})
    comprobar('uno que cocina ya empezo no se cancela (D-41)',
              (estado, codigo(cuerpo), cuerpo.get('error', {}).get('estadoActual')),
              (409, 'TRANSICION_NO_PERMITIDA', 'en_preparacion'))

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

    print('\n--- agregar a un pedido ya enviado (D-37) ---')
    pid = nuevo_pedido()
    estado, cuerpo = agregar(pid, recepcion, SODA, 18)
    pedido = cuerpo.get('pedido', {})
    comprobar('una soda a un pedido pendiente', (estado, pedido.get('total'), pedido.get('version')),
              (200, 68, 2), '#%s' % pid)
    comprobar('  la soda queda marcada como agregada; la pizza del principio, no',
              [l['agregadoEn'] is not None for l in pedido.get('lineas', [])], [False, True])
    _, cuerpo = llamar('GET', '/pedidos/%s' % pid, cocina)
    comprobar('  cocina ve lo agregado, sin el celular',
              (len(cuerpo.get('pedido', {}).get('lineas', [])), 'celular' in cuerpo.get('pedido', {}).get('cliente', {})),
              (2, False))
    estado, cuerpo = agregar(pid, cocina, SODA, 18)
    comprobar('cocina no agrega', (estado, codigo(cuerpo)), (403, 'ROL_SIN_PERMISO'))
    estado, cuerpo = agregar(pid, recepcion, SODA, 15)
    comprobar('lo agregado con otro total', (estado, codigo(cuerpo)), (409, 'PRECIO_CAMBIADO'))

    cambiar(pid, cocina, 'en_preparacion')
    estado, cuerpo = agregar(pid, recepcion, PIZZA, 55.5)
    pedido = cuerpo.get('pedido', {})
    comprobar('una pizza mitad y mitad con extra, mientras cocina la prepara',
              (estado, pedido.get('total'), pedido.get('version')), (200, 123.5, 4))
    comprobar('  el extra, dentro de la pizza agregada',
              [e['producto']['nombre'] for e in pedido.get('lineas', [{}])[-1].get('extras', [])], ['Extra queso'])
    estado, cuerpo = cambiar(pid, cocina, 'listo', version=2)
    comprobar('marcar listo sin haber visto lo ultimo',
              (estado, codigo(cuerpo), cuerpo.get('error', {}).get('version')), (409, 'PEDIDO_CAMBIADO', 4))
    estado, cuerpo = cambiar(pid, cocina, 'listo', version=4)
    comprobar('  con la version que se ve, pasa', (estado, cuerpo.get('pedido', {}).get('estado')), (200, 'listo'))
    estado, cuerpo = agregar(pid, recepcion, PIZZA, 55.5)
    comprobar('una pizza a un pedido listo: va en otro pedido', (estado, codigo(cuerpo)),
              (409, 'AGREGADO_NO_PERMITIDO'))
    estado, cuerpo = agregar(pid, recepcion, SODA, 18)
    comprobar('una soda a un pedido listo: si', (estado, cuerpo.get('pedido', {}).get('total')), (200, 141.5))
    cambiar(pid, recepcion, 'entregado')
    estado, cuerpo = agregar(pid, recepcion, SODA, 18)
    comprobar('nada a un pedido entregado', (estado, codigo(cuerpo)), (409, 'AGREGADO_NO_PERMITIDO'))

    print('\n--- la carrera: muchas ventas a la vez y el numero del dia (D-35) ---')
    simultaneas = []
    candado = threading.Lock()

    def vender():
        estado, cuerpo = enviar('/pedidos', recepcion, venta([{'productoId': id_de['Peperoni'], 'cantidad': 1}], 50))
        with candado:
            simultaneas.append((estado, cuerpo.get('pedido', {})))
    hilos = [threading.Thread(target=vender) for _ in range(12)]
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()
    creados.extend(p.get('id') for _, p in simultaneas)
    comprobar('12 ventas lanzadas a la vez: todas se guardan', [e for e, _ in simultaneas].count(201), 12)
    nums = sorted(p.get('numero') or 0 for _, p in simultaneas)
    comprobar('  sin repetir ni saltar un numero', nums == list(range(nums[0], nums[0] + 12)), True,
              '%s a %s' % (nums[0], nums[-1]))
    por_hora = [p.get('numero') for p in sorted((p for _, p in simultaneas), key=lambda p: (p.get('creadoEn'), p.get('id')))]
    comprobar('  y el orden de los numeros es el orden de llegada', por_hora == sorted(por_hora), True)

    print('\n--- la carrera: "Listo" y "Agregar una pizza" a la vez (D-37) ---')
    ganadores = {'agregar': 0, 'listo': 0}
    consistente = True
    for _ in range(8):
        pid = nuevo_pedido()
        _, cuerpo = cambiar(pid, cocina, 'en_preparacion')
        version = cuerpo.get('pedido', {}).get('version')
        salida = {}
        h1 = threading.Thread(target=lambda: salida.__setitem__('listo', cambiar(pid, cocina, 'listo', version=version)))
        h2 = threading.Thread(target=lambda: salida.__setitem__('agregar', agregar(pid, recepcion, PIZZA, 55.5)))
        h1.start()
        h2.start()
        h1.join()
        h2.join()
        (e_listo, c_listo), (e_agregar, c_agregar) = salida['listo'], salida['agregar']
        _, final = llamar('GET', '/pedidos/%s' % pid, recepcion)
        final = final.get('pedido', {})
        if e_agregar == 200:
            ganadores['agregar'] += 1
            consistente &= (e_listo, codigo(c_listo), final.get('estado'), final.get('version')) == \
                (409, 'PEDIDO_CAMBIADO', 'en_preparacion', version + 2)
        else:
            ganadores['listo'] += 1
            consistente &= (e_listo, e_agregar, codigo(c_agregar), final.get('estado'), final.get('version')) == \
                (200, 409, 'AGREGADO_NO_PERMITIDO', 'listo', version)
    comprobar('8 rondas: siempre pasa uno solo y el otro recibe 409', consistente, True,
              'gano agregar %d veces, gano listo %d' % (ganadores['agregar'], ganadores['listo']))

    print('\n--- la cola ---')
    estado, cuerpo = llamar('GET', '/pedidos?estado=pendiente,en_preparacion', cocina)
    cola = cuerpo.get('pedidos', [])
    comprobar('cocina lee su cola', estado, 200, '%d pedidos' % len(cola))
    comprobar('  sin el celular de nadie (D-31)', any('celular' in p['cliente'] for p in cola), False)
    comprobar('  en orden de llegada', [p['creadoEn'] for p in cola] == sorted(p['creadoEn'] for p in cola), True)
    comprobar('  solo los pendientes y los que estan en preparacion',
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
        if estado_actual == 'pendiente':
            llamar('POST', '/pedidos/%s/cancelacion' % pid, recepcion, {'motivo': 'Pedido de prueba'})
            cerrados += 1
        elif estado_actual in ('en_preparacion', 'listo'):
            # El que cocina ya empezo no se cancela (D-41): se termina y se entrega.
            if estado_actual == 'en_preparacion':
                cambiar(pid, cocina, 'listo')
            cambiar(pid, recepcion, 'entregado')
            cerrados += 1
    _, cuerpo = llamar('GET', '/pedidos', recepcion)
    quedan = [p['id'] for p in cuerpo.get('pedidos', []) if p['id'] in creados]
    comprobar('ningun pedido de la prueba queda activo', quedan, [], '%d cerrados' % cerrados)

    print('\n' + ('TODO CORRECTO' if all(resultados) else 'HAY FALLOS'))
    sys.exit(0 if all(resultados) else 1)
