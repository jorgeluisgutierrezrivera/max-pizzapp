enum Rol { recepcion, cocina }

/// Quien usa la app, segun lo confirma el servidor en GET /api/v1/sesion.
class Usuario {
  const Usuario({required this.sub, required this.nombre, required this.usuario, required this.roles});

  factory Usuario.desdeJson(Map<String, dynamic> json) => Usuario(
        sub: json['sub'] as String,
        nombre: json['nombre'] as String? ?? '',
        usuario: json['usuario'] as String? ?? '',
        roles: {
          for (final r in (json['roles'] as List<dynamic>? ?? const []))
            if (r == 'recepcion') Rol.recepcion else if (r == 'cocina') Rol.cocina,
        },
      );

  final String sub;
  final String nombre;
  final String usuario;
  final Set<Rol> roles;

  /// El nombre para mostrar: el completo si Keycloak lo tiene, si no el de la cuenta.
  String get nombreVisible => nombre.trim().isNotEmpty ? nombre : usuario;

  /// La pantalla que corresponde. En este sistema cada cuenta tiene un solo rol.
  Rol? get rol => roles.contains(Rol.recepcion)
      ? Rol.recepcion
      : roles.contains(Rol.cocina)
          ? Rol.cocina
          : null;
}
