// Una sola forma de error en toda la API:
//   { "error": { "codigo": "...", "mensaje": "..." } }
// "codigo" es estable y lo interpreta la aplicacion; "mensaje" se muestra a la persona.

class ErrorApi extends Error {
  constructor(estado, codigo, mensaje) {
    super(mensaje);
    this.estado = estado;
    this.codigo = codigo;
  }
}

function responderError(res, estado, codigo, mensaje) {
  res.status(estado).json({ error: { codigo, mensaje } });
}

function rutaNoEncontrada(req, res) {
  responderError(res, 404, 'RUTA_NO_ENCONTRADA', 'La ruta solicitada no existe.');
}

// Express 5 entrega aqui tambien los errores de los manejadores asincronos.
// eslint-disable-next-line no-unused-vars
function manejadorErrores(err, req, res, next) {
  if (err instanceof ErrorApi) {
    responderError(res, err.estado, err.codigo, err.message);
    return;
  }
  // Cuerpo JSON mal formado: lo detecta express.json() antes de llegar a la ruta.
  if (err.type === 'entity.parse.failed') {
    responderError(res, 400, 'JSON_INVALIDO', 'El cuerpo de la peticion no es JSON valido.');
    return;
  }
  // Cualquier otra cosa es un fallo nuestro. La traza queda en el registro del servidor;
  // al cliente no se le entrega: seria regalarle el mapa de la aplicacion.
  console.error('[error]', req.method, req.originalUrl, err);
  responderError(res, 500, 'ERROR_INTERNO', 'Ocurrio un error inesperado. Intenta de nuevo.');
}

module.exports = { ErrorApi, rutaNoEncontrada, manejadorErrores };
