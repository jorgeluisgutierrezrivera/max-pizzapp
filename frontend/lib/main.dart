import 'package:flutter/material.dart';

import 'api/canal_en_vivo.dart';
import 'api/cliente_api.dart';
import 'api/usuario.dart';
import 'carta/producto.dart';
import 'pedidos/pedido.dart';
import 'autenticacion/navegador_web.dart';
import 'autenticacion/servicio_sesion.dart';
import 'configuracion.dart';
import 'pantallas/pantalla_acceso.dart';
import 'pantallas/pantalla_cargando.dart';
import 'pantallas/segun_rol.dart';
import 'pantallas/telefono_web.dart';
import 'pantallas/timbre_web.dart';
import 'tema.dart';

/// En desarrollo: flutter run --dart-define=KEYCLOAK_URL=http://localhost:8082
/// En produccion no se define: la direccion se deduce del dominio.
const _keycloakDefinido = String.fromEnvironment('KEYCLOAK_URL');

void main() {
  final navegador = NavegadorWeb();
  final Configuracion configuracion;
  try {
    configuracion = Configuracion.deducir(paginaActual: navegador.direccionActual, keycloakDefinido: _keycloakDefinido);
  } on ErrorDeConfiguracion catch (e) {
    runApp(_App(inicio: PantallaAcceso(mensaje: e.mensaje)));
    return;
  }

  final sesion = ServicioSesion(configuracion: configuracion, navegador: navegador);
  final api = ClienteApi(
    base: configuracion.origen.replace(path: Configuracion.rutaApi),
    token: () => sesion.tokenAcceso,
    renovar: sesion.renovar,
  );
  final timbre = TimbreWeb();
  CanalEnVivo crearCanal() => CanalSocketIo(origen: configuracion.origen, token: () => sesion.tokenAcceso);
  runApp(
    _App(
      inicio: _SegunSesion(sesion: sesion, api: api, crearCanal: crearCanal, timbre: timbre),
    ),
  );
  sesion.arrancar();
}

class _App extends StatelessWidget {
  const _App({required this.inicio});

  final Widget inicio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Max Pizzapp',
      debugShowCheckedModeBanner: false,
      // Tema claro fijo, con la identidad del local (D-29): no sigue el modo del dispositivo.
      theme: temaMaxPizzas(),
      home: inicio,
    );
  }
}

/// Muestra la pantalla que corresponde al estado de la sesion.
class _SegunSesion extends StatelessWidget {
  const _SegunSesion({required this.sesion, required this.api, required this.crearCanal, required this.timbre});

  final ServicioSesion sesion;
  final ClienteApi api;
  final CanalEnVivo Function() crearCanal;
  final TimbreWeb timbre;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sesion,
      builder: (context, _) => switch (sesion.estado) {
        EstadoSesion.iniciando => const PantallaCargando(),
        EstadoSesion.sinSesion => PantallaAcceso(alIniciarSesion: sesion.iniciarSesion, mensaje: sesion.mensaje),
        EstadoSesion.conSesion => PantallaSegunRol(
          cargarUsuario: () async => Usuario.desdeJson(await api.obtener('/sesion')),
          cargarCarta: () async => Carta([
            for (final p in (await api.obtener('/productos'))['productos'] as List<dynamic>)
              Producto.desdeJson(p as Map<String, dynamic>),
          ]),
          enviarPedido: (pedido) async => (await api.enviar('/pedidos', pedido))['pedido'] as Map<String, dynamic>,
          cargarCola: () async => [
            for (final p
                in (await api.obtener('/pedidos', consulta: {'estado': 'pendiente,en_preparacion'}))['pedidos']
                    as List<dynamic>)
              Pedido.desdeJson(p as Map<String, dynamic>),
          ],
          cargarPedidos: () async => [
            for (final p in (await api.obtener('/pedidos'))['pedidos'] as List<dynamic>)
              Pedido.desdeJson(p as Map<String, dynamic>),
          ],
          // Con la versión que se ve: si alguien le agregó algo después, el servidor lo
          // rechaza con 409 PEDIDO_CAMBIADO y la pantalla se pone al día (D-37).
          cambiarEstado: (pedido, hacia) async => Pedido.desdeJson(
            (await api.cambiar('/pedidos/${pedido.id}/estado', {
                  'estado': hacia.nombreApi,
                  if (pedido.version > 0) 'version': pedido.version,
                }))['pedido']
                as Map<String, dynamic>,
          ),
          cancelarPedido: (pedido, motivo) async => Pedido.desdeJson(
            (await api.enviar('/pedidos/${pedido.id}/cancelacion', {'motivo': motivo}))['pedido']
                as Map<String, dynamic>,
          ),
          agregarAlPedido: (pedido, cuerpo) async => Pedido.desdeJson(
            (await api.enviar('/pedidos/${pedido.id}/lineas', cuerpo))['pedido'] as Map<String, dynamic>,
          ),
          llamar: llamarPorTelefono,
          crearCanal: crearCanal,
          timbre: timbre,
          alCerrarSesion: sesion.cerrarSesion,
        ),
      },
    );
  }
}
