const jwt = require('jsonwebtoken');
const jwksRsa = require('jwks-rsa');
const { ErrorApi } = require('./errores');

const ROLES_DEL_SISTEMA = ['recepcion', 'cocina'];

// El token se valida en este proceso contra las claves publicas del realm, que se
// descargan una vez y quedan en memoria. No se consulta a Keycloak en cada peticion:
// seria un salto de red mas por llamada y dejaria la API a merced del proveedor.
function crearAutenticador({ emisor, audiencia, jwksUri }) {
  const claves = jwksRsa({
    jwksUri,
    cache: true,
    cacheMaxAge: 10 * 60 * 1000,
    rateLimit: true,
    jwksRequestsPerMinute: 10,
  });

  function obtenerClave(cabecera, entregar) {
    claves.getSigningKey(cabecera.kid)
      .then((clave) => entregar(null, clave.getPublicKey()))
      .catch((err) => entregar(err));
  }

  function verificar(token) {
    return new Promise((resolver, rechazar) => {
      jwt.verify(token, obtenerClave, {
        algorithms: ['RS256'],
        issuer: emisor,
        audience: audiencia,
      }, (err, carga) => (err ? rechazar(err) : resolver(carga)));
    });
  }

  // Cuatro comprobaciones, no una: firma de este realm, emisor esperado, vigencia y
  // audiencia. La audiencia impide que un token de otra aplicacion del mismo Keycloak,
  // con firma perfectamente valida, sirva para entrar aqui.
  // Es la misma para la API y para el canal en vivo: un token vale en los dos o en ninguno.
  async function usuarioDelToken(token) {
    if (!token) {
      throw new ErrorApi(401, 'TOKEN_AUSENTE', 'Inicia sesion para continuar.');
    }

    let carga;
    try {
      carga = await verificar(token);
    } catch (err) {
      const expirado = err && err.name === 'TokenExpiredError';
      throw new ErrorApi(401,
        expirado ? 'TOKEN_EXPIRADO' : 'TOKEN_INVALIDO',
        expirado ? 'Tu sesion expiro. Inicia sesion de nuevo.' : 'No se pudo verificar tu sesion.');
    }

    const rolesDelToken = (carga.realm_access && carga.realm_access.roles) || [];
    return {
      sub: carga.sub,
      nombre: carga.name || carga.preferred_username || '',
      usuario: carga.preferred_username || '',
      roles: rolesDelToken.filter((r) => ROLES_DEL_SISTEMA.includes(r)),
    };
  }

  async function autenticar(req, res, next) {
    const cabecera = req.get('authorization') || '';
    const [esquema, token] = cabecera.split(' ');
    req.usuario = await usuarioDelToken(esquema === 'Bearer' ? token : null);
    next();
  }
  autenticar.usuarioDelToken = usuarioDelToken;
  return autenticar;
}

// Se declara en cada ruta que rol exige. Con token valido pero rol insuficiente: 403.
function exigirRol(...permitidos) {
  return function comprobarRol(req, res, next) {
    const roles = (req.usuario && req.usuario.roles) || [];
    if (!roles.some((r) => permitidos.includes(r))) {
      throw new ErrorApi(403, 'ROL_SIN_PERMISO', 'Tu rol no permite esta operacion.');
    }
    next();
  };
}

module.exports = { crearAutenticador, exigirRol, ROLES_DEL_SISTEMA };
