const express = require('express');
const { exigirRol, ROLES_DEL_SISTEMA } = require('./autenticacion');
const { rutaNoEncontrada, manejadorErrores } = require('./errores');
const { rutasProductos } = require('./rutas/productos');
const { rutasPedidos } = require('./rutas/pedidos');
const { SIN_AVISOS } = require('./tiempo-real');

// La aplicacion se construye a partir de sus dependencias (base y autenticador) para que
// las pruebas puedan crearla sin una base real ni un Keycloak real.
// "montarExtra" existe solo para las pruebas: permite colgar rutas antes del 404.
// "avisos" es el canal en vivo (tiempo-real.js); sin el, la API funciona igual y no avisa.
function crearApp({ pool, autenticar, avisos = SIN_AVISOS, montarExtra }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 'loopback, uniquelocal');
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
