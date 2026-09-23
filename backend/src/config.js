// Toda la configuracion sale del entorno. Si falta una variable obligatoria, el proceso
// no arranca: es preferible no arrancar a arrancar apuntando a donde no debe.

function obligatoria(nombre) {
  const valor = process.env[nombre];
  if (valor === undefined || valor.trim() === '') {
    throw new Error(`Falta la variable de entorno obligatoria ${nombre}`);
  }
  return valor.trim();
}

function cargarConfig() {
  const realm = process.env.KEYCLOAK_REALM || 'maxpizzapp';
  const keycloakInterno = (process.env.KEYCLOAK_INTERNAL_URL || 'http://keycloak:8080').replace(/\/$/, '');

  return {
    puerto: Number(process.env.PORT || 3000),
    bd: {
      host: process.env.DB_HOST || 'postgres',
      port: Number(process.env.DB_PORT || 5432),
      database: obligatoria('POSTGRES_DB'),
      user: obligatoria('POSTGRES_USER'),
      password: obligatoria('POSTGRES_PASSWORD'),
    },
    identidad: {
      // El emisor tiene que coincidir al caracter con el "iss" de los tokens. En produccion
      // es la URL publica; si fuera la interna, se rechazarian todos (riesgo D-09).
      emisor: obligatoria('KEYCLOAK_ISSUER'),
      audiencia: process.env.KEYCLOAK_AUDIENCE || process.env.KEYCLOAK_CLIENT_ID || 'backend-api',
      // Las claves publicas se leen por la red interna: no hace falta salir a Internet.
      jwksUri: process.env.KEYCLOAK_JWKS_URL
        || `${keycloakInterno}/realms/${realm}/protocol/openid-connect/certs`,
    },
  };
}

module.exports = { cargarConfig };
