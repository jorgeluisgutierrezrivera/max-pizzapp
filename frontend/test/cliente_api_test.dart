import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maxpizzapp/api/cliente_api.dart';
import 'package:maxpizzapp/api/usuario.dart';

void main() {
  final base = Uri.parse('https://maxpizzapp.tech/api/v1');

  http.Response json(int estado, Object cuerpo) => http.Response(jsonEncode(cuerpo), estado,
      headers: {'content-type': 'application/json; charset=utf-8'});

  test('pide la ruta bajo /api/v1 y manda el token como Bearer', () async {
    late http.Request vista;
    final api = ClienteApi(
      base: base,
      token: () => 'token-1',
      renovar: () async => true,
      cliente: MockClient((p) async {
        vista = p;
        return json(200, {'ok': true});
      }),
    );
    expect(await api.obtener('/sesion'), {'ok': true});
    expect(vista.url.toString(), 'https://maxpizzapp.tech/api/v1/sesion');
    expect(vista.headers['Authorization'], 'Bearer token-1');
  });

  test('los parametros de consulta van en la direccion, codificados', () async {
    late http.Request vista;
    final api = ClienteApi(
      base: base,
      token: () => 't',
      renovar: () async => true,
      cliente: MockClient((p) async {
        vista = p;
        return json(200, {'pedidos': []});
      }),
    );
    await api.obtener('/pedidos', consulta: {'estado': 'pendiente,en_preparacion'});
    expect(vista.url.path, '/api/v1/pedidos');
    expect(vista.url.queryParameters, {'estado': 'pendiente,en_preparacion'});
  });

  test('enviar hace un POST con el cuerpo en JSON; cambiar, un PATCH', () async {
    final vistas = <http.Request>[];
    final api = ClienteApi(
      base: base,
      token: () => 'token-1',
      renovar: () async => true,
      cliente: MockClient((p) async {
        vistas.add(p);
        return json(p.method == 'POST' ? 201 : 200, {'pedido': {'id': 12}});
      }),
    );
    expect(await api.enviar('/pedidos', {'paraLlevar': true}), {'pedido': {'id': 12}});
    expect(await api.cambiar('/pedidos/12/estado', {'estado': 'listo'}), {'pedido': {'id': 12}});
    expect(vistas.map((v) => '${v.method} ${v.url.path}'), ['POST /api/v1/pedidos', 'PATCH /api/v1/pedidos/12/estado']);
    expect(jsonDecode(vistas[0].body), {'paraLlevar': true});
    expect(vistas[1].headers['Content-Type'], startsWith('application/json'));
    expect(vistas[1].headers['Authorization'], 'Bearer token-1');
  });

  test('un POST rechazado por token vencido se reintenta una vez, con el mismo cuerpo', () async {
    var token = 'vencido';
    final cuerpos = <String>[];
    final api = ClienteApi(
      base: base,
      token: () => token,
      renovar: () async {
        token = 'nuevo';
        return true;
      },
      cliente: MockClient((p) async {
        cuerpos.add(p.body);
        return p.headers['Authorization'] == 'Bearer nuevo'
            ? json(201, {'pedido': {'id': 1}})
            : json(401, {'error': {'codigo': 'TOKEN_EXPIRADO', 'mensaje': 'Tu sesion expiro.'}});
      }),
    );
    expect(await api.enviar('/pedidos', {'a': 1}), {'pedido': {'id': 1}});
    expect(cuerpos, ['{"a":1}', '{"a":1}']);
  });

  test('los datos extra de un error llegan en el ErrorApi: el total correcto, el producto agotado', () async {
    final api = ClienteApi(
      base: base,
      token: () => 't',
      renovar: () async => true,
      cliente: MockClient((_) async => json(409, {
            'error': {
              'codigo': 'PRODUCTO_NO_DISPONIBLE',
              'mensaje': 'Napolitana no esta disponible.',
              'producto': {'id': 7, 'nombre': 'Napolitana'},
            }
          })),
    );
    await expectLater(
      api.enviar('/pedidos', {}),
      throwsA(isA<ErrorApi>()
          .having((e) => e.codigo, 'codigo', 'PRODUCTO_NO_DISPONIBLE')
          .having((e) => e.datos, 'datos', {'producto': {'id': 7, 'nombre': 'Napolitana'}})),
    );
  });

  test('el formato unico de error se convierte en ErrorApi con el mensaje del servidor', () async {
    final api = ClienteApi(
      base: base,
      token: () => 't',
      renovar: () async => true,
      cliente: MockClient((_) async => json(403, {
            'error': {'codigo': 'ROL_SIN_PERMISO', 'mensaje': 'Tu rol no permite esta operacion.'}
          })),
    );
    await expectLater(
      api.obtener('/sesion'),
      throwsA(isA<ErrorApi>()
          .having((e) => e.estado, 'estado', 403)
          .having((e) => e.codigo, 'codigo', 'ROL_SIN_PERMISO')
          .having((e) => e.mensaje, 'mensaje', 'Tu rol no permite esta operacion.')),
    );
  });

  test('ante un 401 renueva el token una vez y reintenta con el nuevo', () async {
    var token = 'vencido';
    final vistos = <String?>[];
    final api = ClienteApi(
      base: base,
      token: () => token,
      renovar: () async {
        token = 'nuevo';
        return true;
      },
      cliente: MockClient((p) async {
        vistos.add(p.headers['Authorization']);
        return p.headers['Authorization'] == 'Bearer nuevo'
            ? json(200, {'ok': true})
            : json(401, {'error': {'codigo': 'TOKEN_EXPIRADO', 'mensaje': 'Tu sesion expiro.'}});
      }),
    );
    expect(await api.obtener('/sesion'), {'ok': true});
    expect(vistos, ['Bearer vencido', 'Bearer nuevo']);
  });

  test('si la renovacion falla no reintenta, y el 401 llega como error', () async {
    var llamadas = 0;
    final api = ClienteApi(
      base: base,
      token: () => 't',
      renovar: () async => false,
      cliente: MockClient((_) async {
        llamadas++;
        return json(401, {'error': {'codigo': 'TOKEN_EXPIRADO', 'mensaje': 'Tu sesion expiro.'}});
      }),
    );
    await expectLater(api.obtener('/sesion'),
        throwsA(isA<ErrorApi>().having((e) => e.estado, 'estado', 401)));
    expect(llamadas, 1);
  });

  test('sin red: un mensaje para la persona, no una excepcion tecnica', () async {
    final api = ClienteApi(
      base: base,
      token: () => 't',
      renovar: () async => true,
      cliente: MockClient((_) async => throw http.ClientException('fallo de red')),
    );
    await expectLater(api.obtener('/sesion'),
        throwsA(isA<ErrorApi>().having((e) => e.codigo, 'codigo', 'SIN_CONEXION')));
  });

  test('una respuesta que no es el JSON esperado no rompe la app', () async {
    final api = ClienteApi(
      base: base,
      token: () => 't',
      renovar: () async => true,
      cliente: MockClient((_) async => http.Response('<html>502 Bad Gateway</html>', 502)),
    );
    await expectLater(
        api.obtener('/sesion'),
        throwsA(isA<ErrorApi>()
            .having((e) => e.codigo, 'codigo', 'RESPUESTA_INESPERADA')
            .having((e) => e.estado, 'estado', 502)));
  });

  group('Usuario', () {
    test('se lee de la respuesta de /sesion', () {
      final u = Usuario.desdeJson({
        'sub': 'abc',
        'nombre': 'Recepcion de prueba',
        'usuario': 'recepcion.demo',
        'roles': ['recepcion'],
      });
      expect(u.rol, Rol.recepcion);
      expect(u.nombreVisible, 'Recepcion de prueba');
    });

    test('sin nombre completo se muestra el de la cuenta', () {
      final u = Usuario.desdeJson({'sub': 'x', 'nombre': '', 'usuario': 'cocina.demo', 'roles': ['cocina']});
      expect(u.nombreVisible, 'cocina.demo');
      expect(u.rol, Rol.cocina);
    });

    test('roles ajenos al sistema se ignoran', () {
      final u = Usuario.desdeJson({'sub': 'x', 'roles': ['admin', 'otro']});
      expect(u.roles, isEmpty);
      expect(u.rol, isNull);
    });
  });
}
