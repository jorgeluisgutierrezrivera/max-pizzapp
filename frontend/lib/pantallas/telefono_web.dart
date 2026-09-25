import 'package:web/web.dart' as web;

/// Abre el marcador del teléfono con el número del cliente (D-31): en el celular, lo marca;
/// en la computadora, el navegador ofrece la aplicación de llamadas si hay una. Solo se
/// importa desde main.dart: las pruebas corren fuera del navegador.
void llamarPorTelefono(String numero) {
  // Solo dígitos: el número ya viene validado por el servidor, y así no hay forma de que un
  // dato raro arme otra dirección.
  final digitos = numero.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.isEmpty) return;
  web.window.location.href = 'tel:$digitos';
}
