const express = require('express');
const helmet = require('helmet');
const { rateLimit } = require('express-rate-limit');
const { exigirRol, ROLES_DEL_SISTEMA } = require('./autenticacion');
const { ErrorApi, rutaNoEncontrada, manejadorErrores } = require('./errores');
const { rutasProductos } = require('./rutas/productos');
const { rutasPedidos } = require('./rutas/pedidos');
const { SIN_AVISOS } = require('./tiempo-real');

// La aplicacion se construye a partir de sus dependencias (base y autenticador) para que
// las pruebas puedan crearla sin una base real ni un Keycloak real.
// "montarExtra" existe solo para las pruebas: permite colgar rutas antes del 404.
// "avisos" es el canal en vivo (tiempo-real.js); sin el, la API funciona igual y no avisa.
// "limitePorMinuto" es cuantas peticiones acepta de una misma IP (D-52).
function crearApp({ pool, autenticar, avisos = SIN_AVISOS, montarExtra, limitePorMinuto = 600 }) {
  const app = express();
  app.disable('x-powered-by');
  // Solo se cree en la IP que manda el proxy de la red interna (Caddy). Asi req.ip es la del
  // cliente, y el limite de peticiones cuenta por cliente y no por Caddy.
  app.set('trust proxy', 'loopback, uniquelocal');

  // Las cabeceras de seguridad (D-52). La API solo devuelve JSON: no carga nada ni se
  // muestra dentro de un marco. HSTS no va aqui: lo pone Caddy, que es quien termina TLS.
  app.use(helmet({
    contentSecurityPolicy: { useDefaults: false, directives: { defaultSrc: ["'none'"], frameAncestors: ["'none'"] } },
    strictTransportSecurity: false,
  }));

  // El limite de peticiones por IP (D-52), antes de leer el cuerpo y de validar el token:
  // una avalancha sin token tambien se corta. Generoso, porque todo el local sale a Internet
  // por la misma IP. Pasado el limite, 429 en el formato unico, con Retry-After.
  app.use(rateLimit({
    windowMs: 60 * 1000,
    limit: limitePorMinuto,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    handler: (req, res, next) => next(new ErrorApi(429, 'DEMASIADAS_PETICIONES',
      'Demasiadas peticiones seguidas. Espera un momento e intenta de nuevo.')),
  }));

  app.use(express.json({ limit: '100kb' }));

  const api = express.Router();

  // Unica ruta publica. Consulta la base de verdad: una ruta de salud que responde "ok"
  // sin tocar nada miente justo cuando la base se cae. No revela topologia ni versiones.
  api.get('/salud', async (req, res) => {
    try {
      await pool.query('SELECT 1');
      res.json({ estado: 'ok', baseDeDatos: 'ok' });
    } catch (err) {
      console.error('[salud] la base no responde:', err.message);
      res.status(503).json({ estado: 'degradado', baseDeDatos: 'sin respuesta' });
    }
  });

  api.get('/sesion', autenticar, exigirRol(...ROLES_DEL_SISTEMA), (req, res) => {
    const { sub, nombre, usuario, roles } = req.usuario;
    res.json({ sub, nombre, usuario, roles });
  });

  api.use(rutasProductos({ pool, autenticar }));
  api.use(rutasPedidos({ pool, autenticar, avisos }));

  if (montarExtra) montarExtra(api, { autenticar, exigirRol });

  app.use('/api/v1', api);
  app.use(rutaNoEncontrada);
  app.use(manejadorErrores);
  return app;
}

module.exports = { crearApp };
