import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maxpizzapp/autenticacion/navegador.dart';
import 'package:maxpizzapp/autenticacion/pkce.dart';
import 'package:maxpizzapp/autenticacion/servicio_sesion.dart';
import 'package:maxpizzapp/configuracion.dart';

class NavegadorFalso implements Navegador {
  NavegadorFalso(String direccion) : direccionActual = Uri.parse(direccion);

  @override
  Uri direccionActual;
  final almacen = <String, String>{};
  final visitas = <Uri>[];

  @override
  void irA(Uri destino) => visitas.add(destino);
  @override
  void reemplazarDireccion(Uri destino) => direccionActual = destino;
  @override
  String? leer(String clave) => almacen[clave];
  @override
  void guardar(String clave, String valor) => almacen[clave] = valor;
  @override
  void borrar(String clave) => almacen.remove(clave);
}

final config = Configuracion.deducir(paginaActual: Uri.parse('https://maxpizzapp.tech/'));

Map<String, dynamic> respuestaDeTokens({String acceso = 'acceso-1'}) => {
      'access_token': acceso,
      'refresh_token': 'renovacion-1',
      'id_token': 'identidad-1',
      'expires_in': 3600,
      'refresh_expires_in': 3600,
    };

void main() {
  late NavegadorFalso navegador;
  late List<http.Request> peticiones;

  ServicioSesion crear({required String direccion, int estadoHttp = 200, Object? fallo}) {
    navegador = NavegadorFalso(direccion);
    peticiones = [];
    final cliente = MockClient((peticion) async {
      peticiones.add(peticion);
      if (fallo != null) throw fallo;
      return http.Response(jsonEncode(respuestaDeTokens()), estadoHttp);
    });
    final sesion = ServicioSesion(
      configuracion: config, navegador: navegador, cliente: cliente, azar: Random(1));
    addTearDown(sesion.dispose);
    return sesion;
  }

  /// Simula la ida a Keycloak y el regreso con un codigo.
  Future<ServicioSesion> sesionIniciada() async {
    final ida = crear(direccion: 'https://maxpizzapp.tech/');
    ida.iniciarSesion();
    final estado = navegador.almacen[ServicioSesion.claveEstado]!;
    final almacenIda = Map.of(navegador.almacen);

    final vuelta = crear(direccion: 'https://maxpizzapp.tech/?code=codigo-1&state=$estado');
    navegador.almacen.addAll(almacenIda);
    await vuelta.arrancar();
    return vuelta;
  }

  group('ida a Keycloak', () {
    test('al abrir la app sin codigo, pregunta en silencio (prompt=none)', () async {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/');
      await sesion.arrancar();

      final destino = navegador.visitas.single;
      expect(destino.replace(queryParameters: {}).toString().replaceAll('?', ''),
          config.urlAutorizacion.toString());
      expect(destino.queryParameters['prompt'], 'none');
      expect(sesion.estado, EstadoSesion.iniciando);
    });

    test('iniciar sesion manda todos los parametros de PKCE y no pide silencio', () {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/');
      sesion.iniciarSesion();

      final p = navegador.visitas.single.queryParameters;
      final verificador = navegador.almacen[ServicioSesion.claveVerificador]!;
      expect(p['client_id'], 'frontend-web');
      expect(p['response_type'], 'code');
      expect(p['scope'], 'openid');
      expect(p['redirect_uri'], 'https://maxpizzapp.tech/');
      expect(p['code_challenge_method'], 'S256');
      expect(p['code_challenge'], desafioS256(verificador));
      expect(p['state'], navegador.almacen[ServicioSesion.claveEstado]);
      expect(p.containsKey('prompt'), isFalse);
    });

    test('el verificador nunca viaja en la direccion: solo su huella', () {
      crear(direccion: 'https://maxpizzapp.tech/').iniciarSesion();
      final verificador = navegador.almacen[ServicioSesion.claveVerificador]!;
      expect(navegador.visitas.single.toString(), isNot(contains(verificador)));
    });
  });

  group('regreso desde Keycloak', () {
    test('con codigo y state correctos: canjea el codigo y entra', () async {
      final sesion = await sesionIniciada();

      expect(sesion.estado, EstadoSesion.conSesion);
      expect(sesion.tokenAcceso, 'acceso-1');
      final formulario = peticiones.single.bodyFields;
      expect(peticiones.single.url, config.urlToken);
      expect(formulario['grant_type'], 'authorization_code');
      expect(formulario['code'], 'codigo-1');
      expect(formulario['redirect_uri'], 'https://maxpizzapp.tech/');
      expect(formulario['code_verifier']!.length, 43);
    });

    test('despues de entrar no queda nada en sessionStorage ni el codigo en la barra', () async {
      await sesionIniciada();
      expect(navegador.almacen, isEmpty);
      expect(navegador.direccionActual.toString(), 'https://maxpizzapp.tech/');
    });

    test('con un state distinto: no canjea nada y avisa', () async {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/?code=robado&state=otro');
      navegador.almacen[ServicioSesion.claveEstado] = 'el-verdadero';
      navegador.almacen[ServicioSesion.claveVerificador] = generarVerificador();
      await sesion.arrancar();

      expect(peticiones, isEmpty);
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.mensaje, isNotNull);
      expect(navegador.almacen, isEmpty);
    });

    test('un codigo sin state guardado (otra pestana, otro navegador) se descarta', () async {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/?code=x&state=y');
      await sesion.arrancar();
      expect(peticiones, isEmpty);
      expect(sesion.estado, EstadoSesion.sinSesion);
    });

    test('login_required no es un error: solo significa que no habia sesion', () async {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/?error=login_required&state=s');
      await sesion.arrancar();
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.mensaje, isNull);
      expect(navegador.visitas, isEmpty, reason: 'no debe volver a Keycloak en bucle');
    });

    test('otro error de Keycloak se muestra', () async {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/?error=access_denied&state=s');
      await sesion.arrancar();
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.mensaje, contains('access_denied'));
    });

    test('si Keycloak rechaza el canje: sin sesion y con mensaje', () async {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/?code=c&state=s', estadoHttp: 400);
      navegador.almacen[ServicioSesion.claveEstado] = 's';
      navegador.almacen[ServicioSesion.claveVerificador] = generarVerificador();
      await sesion.arrancar();
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.tokenAcceso, isNull);
      expect(sesion.mensaje, isNotNull);
    });

    test('sin conexion: mensaje de red, no un error sin explicar', () async {
      final sesion = crear(
          direccion: 'https://maxpizzapp.tech/?code=c&state=s', fallo: http.ClientException('x'));
      navegador.almacen[ServicioSesion.claveEstado] = 's';
      navegador.almacen[ServicioSesion.claveVerificador] = generarVerificador();
      await sesion.arrancar();
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.mensaje, contains('conexión'));
    });
  });

  group('renovacion y cierre', () {
    test('renovar pide un token nuevo con el de renovacion', () async {
      final sesion = await sesionIniciada();
      peticiones.clear();
      expect(await sesion.renovar(), isTrue);
      expect(peticiones.single.bodyFields['grant_type'], 'refresh_token');
      expect(peticiones.single.bodyFields['refresh_token'], 'renovacion-1');
      expect(sesion.estado, EstadoSesion.conSesion);
    });

    test('si la renovacion falla, vuelve al acceso avisando que la sesion expiro', () async {
      final sesion = crear(direccion: 'https://maxpizzapp.tech/', estadoHttp: 400);
      expect(await sesion.renovar(), isFalse);
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.mensaje, contains('expiró'));
    });

    test('cerrar sesion cierra tambien la de Keycloak y olvida el token', () async {
      final sesion = await sesionIniciada();
      sesion.cerrarSesion();

      expect(sesion.tokenAcceso, isNull);
      final destino = navegador.visitas.last;
      expect(destino.path, config.urlCierre.path);
      expect(destino.queryParameters['id_token_hint'], 'identidad-1');
      expect(destino.queryParameters['post_logout_redirect_uri'], 'https://maxpizzapp.tech/');
      expect(destino.queryParameters['client_id'], 'frontend-web');
    });
  });
}
