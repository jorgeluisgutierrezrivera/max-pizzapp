# Max Pizzapp

Sistema de **gestión de pedidos para un restaurante pequeño**. La recepción toma el
pedido, lo envía a cocina, y el estado de preparación se sincroniza **en tiempo real**
entre ambas pantallas; cuando cocina marca "listo", recepción lo entrega.

Trabajo Final del **Módulo 4 — Integración y Despliegue de Soluciones** (Diplomado en
Desarrollo Web y Aplicaciones Móviles, UAJMS, gestión 2026).

## Alcance

Un flujo acotado y **desplegable**, priorizando profundidad sobre cantidad de módulos:

- **Recepción** crea el pedido a partir de la carta y lo envía a cocina.
- **Cocina** (tablet/PC) ve los pedidos entrantes en vivo y cambia su estado.
- Cuando el pedido está **listo**, recepción recibe el aviso y lo entrega.

## Roles

| Rol | Qué hace |
|---|---|
| **Recepción** | Crea pedidos, ve estados en vivo, cancela antes de "listo", entrega, marca productos agotados |
| **Cocina** | Ve pedidos entrantes en vivo, avanza el estado, marca "listo", marca productos agotados |

El sistema tiene **dos roles**. La administración de la carta y el historial quedan fuera
de alcance y se recogen como trabajo futuro.

## Stack

- **Backend:** Node.js + Express (API REST) + **Socket.IO** (tiempo real)
- **Base de datos:** PostgreSQL
- **Identidad y roles:** Keycloak (OIDC)
- **Frontend:** Flutter (web)
- **Infraestructura:** Docker Compose · Caddy (HTTPS)

### Versiones fijadas

Versiones tomadas del entorno de desarrollo real. Las imágenes se fijan por versión
(nunca `latest`) para que el entorno sea reproducible en desarrollo y en el servidor.

| Componente | Versión | Cómo se fija |
|---|---|---|
| Node.js | 24.15.0 (LTS) | imagen `node:24-alpine` |
| npm | 11.12.1 | incluido en la imagen de Node |
| Flutter | 3.44.8 (stable) | SDK local; se declara en `frontend/pubspec.yaml` |
| Dart | 3.12.2 | incluido en el SDK de Flutter |
| PostgreSQL | 17.11 | imagen `postgres:17-alpine` |
| Keycloak | 26.7.4 | imagen `quay.io/keycloak/keycloak:26.7` |
| Caddy | 2.11.4 | imagen `caddy:2-alpine` |
| Docker Engine | 29.7.2 (desarrollo) · 29.8.1 (servidor) | instalación del sistema |
| Docker Compose | v5.3.1 (desarrollo) · v5.5.1 (servidor) | instalación del sistema |
| Sistema del servidor | Ubuntu 24.04.5 LTS | imagen del proveedor |

Las versiones exactas de PostgreSQL, Keycloak y Caddy se leyeron de los contenedores en
ejecución en el servidor.

Librerías del backend, fijadas sin rangos en `backend/package.json` y con
`package-lock.json`, que es lo que `npm ci` instala en el servidor:

| Librería | Versión | Para qué |
|---|---|---|
| Express | 5.2.1 | Servidor HTTP y rutas |
| pg | 8.23.0 | Acceso a PostgreSQL con consultas parametrizadas |
| jsonwebtoken | 9.0.3 | Verificación de la firma y de los datos del token |
| jwks-rsa | 4.1.0 | Lectura y caché de las claves públicas de Keycloak |

Paquetes de la app Flutter, fijados sin rangos en `frontend/pubspec.yaml` y con
`pubspec.lock`:

| Paquete | Versión | Para qué |
|---|---|---|
| http | 1.6.0 | Peticiones a la API y canje del token |
| crypto | 3.0.7 | SHA-256 del desafío PKCE |
| web | 1.1.1 | Acceso al navegador: redirección, dirección actual y `sessionStorage` |
| flutter_lints | 6.0.0 | Reglas de análisis estático (solo desarrollo) |

Socket.IO se fija del mismo modo cuando entre su tarjeta.

## Pruebas

```bash
cd backend && npm test            # 16 pruebas del acceso, sin base ni Keycloak reales
cd frontend && flutter test       # pruebas de la app Flutter
python pruebas/identidad/probar_acceso_pkce.py   # inicio de sesión real con PKCE
python pruebas/api/probar_salud_y_token.py       # la API con tokens reales del realm
```

Las dos pruebas de `pruebas/` aceptan `KEYCLOAK_URL` y `API_URL` para ejecutarse contra el
despliegue público.

## Metodología

Desarrollo con **Kanban**: flujo continuo de trabajo (tablero, límite de trabajo en
curso y entregas incrementales). No se usan sprints.

## Estructura del repositorio

```
codigo/
├── backend/      API Node/Express + Socket.IO
├── frontend/     App Flutter
├── docker/       Compose, Postgres (init SQL), Keycloak (realm), Caddy
├── pruebas/      Pruebas de extremo a extremo contra Keycloak y la API reales
├── scripts/      Publicar la app y dibujar las ilustraciones de la carta
└── docs/         Documentación técnica: BRIEF de desarrollo y planes de trabajo
```

## Dirección pública

| Qué | Dirección |
|---|---|
| Aplicación | **https://maxpizzapp.tech** |
| Identidad (Keycloak) | https://auth.maxpizzapp.tech |

Hay una cuenta de demostración por rol: `recepcion.demo` y `cocina.demo`. Sus contraseñas
**no están en este repositorio**: se asignan en el servidor desde el `.env`.

## La carta de demostración

La carta que trae el sistema es **ficticia**: nueve pizzas (cinco tradicionales y cuatro
premium) y tres bebidas, con nombres genéricos y precios inventados. Vive en
`docker/postgres/init/03_carta_ficticia.sql` y se reemplaza por la real sin tocar el esquema.

Cada producto tiene una ilustración en `frontend/web/carta/`. Las dibuja
`scripts/dibujar-carta.py` con formas simples, sin imágenes de terceros, y el resultado es
siempre el mismo. La base guarda solo el nombre del archivo, nunca la imagen ni una dirección.

## Variables de entorno

Copiar `.env.example` como `.env` y completar los valores. El `.env` **no** se versiona, y
el de producción no es una copia del de desarrollo: sus contraseñas se generan en el
servidor y no salen de ahí.

## Puesta en marcha en local

Requisitos: Docker con el plugin de Compose. Todo se ejecuta desde la carpeta `codigo/`.

1. Crear el `.env` a partir de `.env.example` y completar las contraseñas.
2. Levantar la base de datos y Keycloak:

   ```bash
   docker compose --env-file .env -f docker/docker-compose.yml up -d
   docker compose --env-file .env -f docker/docker-compose.yml ps
   ```

   Keycloak tarda uno o dos minutos en quedar `healthy`. Su consola queda en
   `http://localhost:8082`.
3. Asignar las contraseñas de las cuentas de demostración, como explica
   `docker/keycloak/README.md`.
4. Comprobar el inicio de sesión de punta a punta:

   ```bash
   python pruebas/identidad/probar_acceso_pkce.py
   ```

En desarrollo los puertos del host son 5433 (base), 3001 (API) y 8082 (identidad), para
no chocar con otros servicios de la máquina.

### La app Flutter en desarrollo

Con el entorno anterior levantado:

```bash
cd frontend
flutter run -d chrome --dart-define=KEYCLOAK_URL=http://localhost:8082
```

La app queda en `http://localhost:8090`. Su servidor de desarrollo reenvía `/api/` al
backend local (`frontend/web_dev_config.yaml`), así que para el navegador la app y la API
comparten origen, igual que en producción. El puerto 8090 es fijo: Keycloak lo tiene
declarado como origen permitido del cliente `frontend-web`.

## Despliegue en el servidor

El despliegue es **un `docker compose` versionado**: con este repositorio, un archivo de
entorno y un servidor con Docker, se levanta igual en cualquier proveedor.

```
Internet ──HTTPS 443──▶ Caddy ─┬─ /              ▶ archivos estáticos
                               ├─ /api/*         ▶ API (backend:3000)
                               ├─ /socket.io/*   ▶ tiempo real (backend:3000)
                               └─ auth.<dominio> ▶ Keycloak (keycloak:8080) ──SQL──▶ PostgreSQL
```

Solo Caddy publica puertos (80 y 443). La base de datos y Keycloak se alcanzan únicamente
por la red interna de Docker.

### 1. Requisitos del servidor

- Linux con Docker y el plugin de Compose. El servidor actual usa Ubuntu 24.04 LTS, con
  Docker instalado mediante el script oficial: `curl -fsSL https://get.docker.com | sh`.
- **Puertos 80 y 443 libres.** Si otro servidor web los ocupa, Caddy no arranca. Se
  comprueba con `ss -tlnp | grep -E ':80 |:443 '`.
- **Cortafuegos del proveedor** abierto solo en TCP 22, TCP 80, TCP 443 y UDP 443. No se usa
  `ufw`, porque los puertos que publica Docker se saltan sus reglas.
- Al menos 2 GB de RAM. Keycloak es la pieza que más memoria usa.

### 2. DNS

Dos registros apuntando a la IP del servidor, **antes** del primer arranque. Si el dominio
no resuelve, Let's Encrypt rechaza la validación y se consumen intentos.

| Tipo | Nombre | Valor |
|---|---|---|
| A (y AAAA si hay IPv6) | `@` | IP del servidor |
| A (y AAAA si hay IPv6) | `auth` | IP del servidor |

No debe existir un registro CAA que excluya a Let's Encrypt.

### 3. Código y entorno

```bash
git clone https://github.com/jorgeluisgutierrezrivera/max-pizzapp.git /opt/maxpizzapp
cd /opt/maxpizzapp
```

El `.env` de producción se crea **en el servidor** y con permisos `600`. Las contraseñas se
generan ahí mismo:

```bash
umask 077
cat > .env <<EOF
POSTGRES_DB=maxpizzapp
POSTGRES_USER=maxpizzapp
POSTGRES_PASSWORD=$(openssl rand -hex 24)
NODE_ENV=production
KEYCLOAK_REALM=maxpizzapp
KEYCLOAK_CLIENT_ID=backend-api
KEYCLOAK_CLIENT_SECRET=
KEYCLOAK_ADMIN=maxpizzapp-admin
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -hex 24)
KEYCLOAK_DEMO_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | cut -c1-14)
KEYCLOAK_INTERNAL_URL=http://keycloak:8080
DOMINIO=maxpizzapp.tech
CADDY_EMAIL=correo-de-contacto@ejemplo.com
EOF
```

`DOMINIO` va sin protocolo ni barra final. De esa variable salen la dirección de la
aplicación, la de Keycloak y el emisor de los tokens. **Si cambia el dominio**, también hay
que cambiarlo en las URI de redirección de `docker/keycloak/realm-maxpizzapp.json`.

### 4. Validar y levantar

```bash
docker compose --env-file .env -f docker/docker-compose.prod.yml config --quiet
docker run --rm --env-file .env -v "$PWD/docker/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose --env-file .env -f docker/docker-compose.prod.yml up -d
docker compose --env-file .env -f docker/docker-compose.prod.yml ps
```

Los tres servicios tienen que quedar `Up`, y la base y Keycloak además `healthy`. Caddy
obtiene los certificados solo durante el primer arranque. Los certificados quedan en el
volumen `caddy_datos`, que **no se debe borrar**: Let's Encrypt limita cuántas veces se
puede pedir el mismo certificado por semana.

Después se asignan las contraseñas de las cuentas de demostración, como explica
`docker/keycloak/README.md` en el apartado *En producción*.

### 5. Verificar desde fuera del servidor

Una prueba hecha dentro del servidor no demuestra que el sistema sea público. Desde otra
red:

```bash
curl -I https://maxpizzapp.tech/        # 200, certificado válido
curl -I http://maxpizzapp.tech/         # 308 hacia https://
curl -s https://auth.maxpizzapp.tech/realms/maxpizzapp/.well-known/openid-configuration
```

El campo `issuer` tiene que ser `https://auth.maxpizzapp.tech/realms/maxpizzapp`. Si
aparece una dirección interna, la API rechazará todos los tokens.

Ya en el servidor, se comprueba que solo haya puertos públicos 22, 80 y 443:

```bash
ss -tlnp | grep -E ':(80|443|5432|8080|9000|2019) '
```

Si aparece 5432 u 8080, algún servicio publicó un puerto que no debía.

El inicio de sesión de punta a punta se prueba ejecutando en el servidor
`KEYCLOAK_URL=https://auth.maxpizzapp.tech python3 pruebas/identidad/probar_acceso_pkce.py`.

### 6. Publicar la app

La app Flutter **no se compila en el servidor**, que tiene 1 vCPU y la compilación pide más
que todo el sistema en marcha. Se compila en la máquina de desarrollo y se publica con un
comando, desde la raíz del repositorio (Git Bash en Windows):

```bash
bash scripts/publicar-web.sh root@IP-DEL-SERVIDOR
```

El script compila en modo *release*, copia el build a una carpeta nueva del servidor,
`/opt/maxpizzapp-web/versiones/<fecha-hora>`, y recién cuando la copia terminó mueve el
enlace `actual` hacia ella. Caddy sirve siempre lo que apunta `actual`, así que el cambio es
instantáneo y nadie ve una versión a medias. Se conservan las tres últimas versiones.

Para **volver a la versión anterior**, en el servidor:

```bash
cd /opt/maxpizzapp-web && ls versiones
ln -sfn versiones/<version-anterior> actual.nuevo && mv -T actual.nuevo actual
```

El build **no se versiona**: se genera desde el código. Mientras no haya ninguna versión
publicada, Caddy sirve la página de cortesía del repositorio. Los archivos de la app se
envían con `Cache-Control: no-cache`, así que después de publicar el navegador revalida y
recibe la versión nueva sin que haga falta borrar la caché.

### 7. Actualizar

```bash
cd /opt/maxpizzapp
git pull
docker compose --env-file .env -f docker/docker-compose.prod.yml up -d
```

**Si el cambio trae una migración nueva** en `docker/postgres/init/` (`02_…sql`, `03_…sql`):
los scripts de esa carpeta solo corren al **crear** la base, así que en una base que ya
existe hay que aplicarla una vez, a mano:

```bash
docker exec -i maxpizzapp-bd sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < docker/postgres/init/02_porciones_y_carta.sql
```

La carta ficticia (`03_carta_ficticia.sql`) se carga igual. Volver a cargarla actualiza los
productos por su nombre sin duplicarlos, y no revive uno que cocina marcó agotado.

Las migraciones están escritas para que aplicarlas dos veces no cambie nada ni falle. No se
edita nunca una migración que ya se aplicó: el cambio siguiente va en un archivo nuevo.

Compose solo recrea los servicios cuya configuración cambió. Hay una excepción:
`--import-realm` **no sobrescribe** un realm que ya existe, así que un cambio en el archivo
del realm también hay que aplicarlo desde la consola de Keycloak.

Los contenedores se reinician con `restart: unless-stopped`: tras un reinicio completo del
servidor, el sistema vuelve solo.
