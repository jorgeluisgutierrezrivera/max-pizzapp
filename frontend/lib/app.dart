import 'package:flutter/material.dart';

import 'api/canal_en_vivo.dart';
import 'api/cliente_api.dart';
import 'api/usuario.dart';
import 'autenticacion/servicio_sesion.dart';
import 'carta/producto.dart';
import 'pantallas/pantalla_acceso.dart';
import 'pantallas/pantalla_cargando.dart';
import 'pantallas/pantalla_encendida.dart';
import 'pantallas/red.dart';
import 'pantallas/segun_rol.dart';
import 'pantallas/timbre.dart';
import 'pedidos/pedido.dart';
import 'tema.dart';

/// Lo común a las dos entradas de la app (D-48): main.dart, la web, y main_cocina.dart, el
/// APK de cocina. Cada una arma las piezas de su plataforma —cómo se inicia sesión, cómo
/// suena el timbre, cómo se sabe si hay red— y se las pasa a estas pantallas, que son las
/// mismas.
class AppMaxPizzapp extends StatelessWidget {
  const AppMaxPizzapp({super.key, required this.inicio, this.titulo = 'Max Pizzapp'});

  final Widget inicio;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: titulo,
      debugShowCheckedModeBanner: false,
      // Tema claro fijo, con la identidad del local (D-29): no sigue el modo del dispositivo.
      theme: temaMaxPizzas(),
      home: inicio,
    );
  }
}

void _sinTelefono(String numero) {}

/// Muestra la pantalla que corresponde al estado de la sesion.
class SegunSesion extends StatelessWidget {
  const SegunSesion({
    super.key,
    required this.sesion,
    required this.api,
    required this.crearCanal,
    required this.timbre,
    required this.red,
    this.pantallaEncendida = const PantallaSegunElSistema(),
    this.llamar = _sinTelefono,
    this.webDeRecepcion,
  });

  final ServicioSesion sesion;
  final ClienteApi api;
  final CanalEnVivo Function() crearCanal;
  final Timbre timbre;
  final Red red;
  final PantallaEncendida pantallaEncendida;
  final void Function(String numero) llamar;

  /// Solo en el APK de cocina: la web a la que tiene que ir una cuenta de recepción.
  final Uri? webDeRecepcion;

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
          llamar: llamar,
          crearCanal: crearCanal,
          timbre: timbre,
          red: red,
          pantallaEncendida: pantallaEncendida,
          alCerrarSesion: sesion.cerrarSesion,
          webDeRecepcion: webDeRecepcion,
        ),
      },
    );
  }
}
