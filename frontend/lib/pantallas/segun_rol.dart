import 'package:flutter/material.dart';

import '../api/canal_en_vivo.dart';
import '../api/cliente_api.dart';
import '../api/usuario.dart';
import '../carta/producto.dart';
import '../pedidos/pedido.dart';
import 'pantalla_cargando.dart';
import 'pantalla_cocina.dart';
import 'pantalla_error.dart';
import 'pantalla_recepcion.dart';
import 'timbre.dart';

Future<List<Pedido>> _colaVacia() async => const [];
Future<Pedido> _sinApi(Pedido pedido, [Object? _]) =>
    Future.error(const ErrorApi(0, 'SIN_API', 'Esta pantalla no tiene cómo cambiar pedidos.'));
CanalEnVivo _sinCanal() => const CanalApagado();
void _sinTelefono(String numero) {}

/// Pregunta al servidor quien es la persona y muestra la pantalla de su rol.
///
/// La app no decide el rol leyendo el token por su cuenta: lo decide el servidor, que acaba
/// de validar el token. La app puede ocultar lo que un rol no debe ver; impedirlo es tarea
/// del servidor.
class PantallaSegunRol extends StatefulWidget {
  const PantallaSegunRol({
    super.key,
    required this.cargarUsuario,
    required this.cargarCarta,
    required this.alCerrarSesion,
    this.enviarPedido,
    this.cargarCola = _colaVacia,
    this.cargarPedidos = _colaVacia,
    this.cambiarEstado = _sinApi,
    this.cancelarPedido = _sinApi,
    this.agregarAlPedido = _sinApi,
    this.crearCanal = _sinCanal,
    this.timbre,
    this.llamar = _sinTelefono,
  });

  final Future<Usuario> Function() cargarUsuario;
  final Future<Carta> Function() cargarCarta;
  final VoidCallback alCerrarSesion;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> pedido)? enviarPedido;

  /// La cola de cocina: pendientes y en preparación.
  final Future<List<Pedido>> Function() cargarCola;

  /// Los pedidos de recepción: los activos, listos incluidos.
  final Future<List<Pedido>> Function() cargarPedidos;
  final Future<Pedido> Function(Pedido pedido, EstadoPedido hacia) cambiarEstado;
  final Future<Pedido> Function(Pedido pedido, String motivo) cancelarPedido;
  final Future<Pedido> Function(Pedido pedido, Map<String, dynamic> cuerpo) agregarAlPedido;
  final CanalEnVivo Function() crearCanal;
  final Timbre? timbre;
  final void Function(String numero) llamar;

  @override
  State<PantallaSegunRol> createState() => _PantallaSegunRolState();
}

class _PantallaSegunRolState extends State<PantallaSegunRol> {
  late Future<Usuario> _usuario;

  @override
  void initState() {
    super.initState();
    _usuario = widget.cargarUsuario();
  }

  // Cuerpo con llaves a proposito: con "=>", el callback devolveria el Future de la
  // asignacion y setState lo rechaza.
  void _reintentar() => setState(() {
    _usuario = widget.cargarUsuario();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Usuario>(
      future: _usuario,
      builder: (context, estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const PantallaCargando(texto: 'Verificando tu cuenta…');
        }
        if (estado.hasError) {
          final error = estado.error;
          return PantallaError(
            mensaje: error is ErrorApi ? error.mensaje : 'No se pudo verificar tu cuenta.',
            alReintentar: _reintentar,
            alCerrarSesion: widget.alCerrarSesion,
          );
        }
        final usuario = estado.requireData;
        return switch (usuario.rol) {
          Rol.recepcion => PantallaRecepcion(
            usuario: usuario,
            alCerrarSesion: widget.alCerrarSesion,
            cargarCarta: widget.cargarCarta,
            enviarPedido: widget.enviarPedido,
            cargarPedidos: widget.cargarPedidos,
            cambiarEstado: widget.cambiarEstado,
            cancelarPedido: widget.cancelarPedido,
            agregarAlPedido: widget.agregarAlPedido,
            crearCanal: widget.crearCanal,
            timbre: widget.timbre,
            llamar: widget.llamar,
          ),
          Rol.cocina => PantallaCocina(
            usuario: usuario,
            alCerrarSesion: widget.alCerrarSesion,
            cargarCola: widget.cargarCola,
            cambiarEstado: widget.cambiarEstado,
            crearCanal: widget.crearCanal,
            timbre: widget.timbre ?? TimbreMudo(),
          ),
          null => PantallaError(
            mensaje:
                'Tu cuenta no tiene un rol de este sistema. Pide que te asignen '
                'recepción o cocina.',
            alReintentar: _reintentar,
            alCerrarSesion: widget.alCerrarSesion,
          ),
        };
      },
    );
  }
}
