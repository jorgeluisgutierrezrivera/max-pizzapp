# Max Pizzapp

> Trabajo Final · Diplomado en Desarrollo Web y Aplicaciones Móviles · UAJMS 2026\
> Módulo 4 — Integración y Despliegue de Soluciones\
> Autor: Jorge Luis Gutierrez Rivera · Tutor: M.Sc. Ing. Isaac Lange Aguilar

## Descripción

Sistema web de **gestión de pedidos con sincronización en tiempo real** del estado de
preparación, para el personal de **recepción y cocina** de la pizzería **Max's Pizzas**, en
su local central de la zona Villa Fátima de Tarija. La recepción toma el pedido y lo envía
a cocina; cocina lo ve llegar en vivo y avanza su estado, y cuando lo marca "listo",
recepción recibe el aviso y lo entrega.

**Sistema desplegado:** https://maxpizzapp.tech

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

### Credenciales de prueba

| Rol | Usuario | Contraseña |
|---|---|---|
| Recepción | `recepcion.demo` | Se entrega a la coordinación por canal privado |
| Cocina | `cocina.demo` | Se entrega a la coordinación por canal privado |

Las contraseñas **no están en este repositorio**: se asignan en cada entorno desde su `.env`
(`KEYCLOAK_DEMO_PASSWORD`), como explica `docker/keycloak/README.md`.

## Stack tecnológico

Versiones tomadas del entorno de desarrollo real. Las imágenes se fijan por versión
(nunca `latest`) para que el entorno sea reproducible en desarrollo y en el servidor.

| Componente | Versión | Función | Cómo se fija |
|---|---|---|---|
| Node.js | 24.15.0 (LTS) | Ejecuta la API REST (Express) y el canal en vivo (Socket.IO) | imagen `node:24-alpine` |
| npm | 11.12.1 | Instala las librerías de la API | incluido en la imagen de Node |
| Flutter | 3.44.8 (stable) | La app web de recepción y cocina | SDK local; se declara en `frontend/pubspec.yaml` |
| Dart | 3.12.2 | El lenguaje de la app | incluido en el SDK de Flutter |
| PostgreSQL | 17.11 | La base de datos, única fuente de verdad | imagen `postgres:17-alpine` |
| Keycloak | 26.7.4 | Identidad y roles (OIDC, con PKCE) | imagen `quay.io/keycloak/keycloak:26.7` |
| Caddy | 2.11.4 | HTTPS y proxy inverso en producción | imagen `caddy:2-alpine` |
| Docker Engine | 29.7.2 (desarrollo) · 29.8.1 (servidor) | Los contenedores | instalación del sistema |
| Docker Compose | v5.3.1 (desarrollo) · v5.5.1 (servidor) | Levanta el sistema completo desde un archivo | instalación del sistema |
| Sistema del servidor | Ubuntu 24.04.5 LTS | El servidor de producción | imagen del proveedor |

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
| socket.io | 4.8.3 | El canal en vivo: avisos de pedido nuevo, de lo agregado y de cambio de estado |
| socket.io-client | 4.8.3 | Solo desarrollo: las pruebas del canal y la medición del aviso |

Paquetes de la app Flutter, fijados sin rangos en `frontend/pubspec.yaml` y con
`pubspec.lock`:

| Paquete | Versión | Para qué |
|---|---|---|
| http | 1.6.0 | Peticiones a la API y canje del token |
| crypto | 3.0.7 | SHA-256 del desafío PKCE |
| web | 1.1.1 | Acceso al navegador: redirección, dirección actual y `sessionStorage` |
| socket_io_client | 3.1.6 | El canal en vivo en la app: pedidos nuevos, lo agregado y los cambios de estado |
| flutter_lints | 6.0.0 | Reglas de análisis estático (solo desarrollo) |


## Pruebas

Las del backend y la app corren sin el entorno levantado; las de `pruebas/`, contra
Keycloak y la API reales. Antes de la primera vez: `cd backend && npm ci` y
`cd frontend && flutter pub get`.

```bash
cd backend && npm test            # 267 pruebas: acceso, carta, precio, pedidos, lo agregado y canal en vivo, sin base ni Keycloak reales
cd frontend && flutter test       # 193 pruebas de la app: la venta, los pedidos, la cocina, el acceso y el contraste de colores
python pruebas/identidad/probar_acceso_pkce.py   # inicio de sesión real con PKCE
python pruebas/api/probar_salud_y_token.py       # la API con tokens reales del realm
python pruebas/api/probar_carta.py               # la carta con token real y la base real
python pruebas/api/probar_pedidos.py             # pedidos: precios, número del día, venta directa, agregar, tres carreras y limpieza, en la base real
python pruebas/tiempo-real/medir_aviso.py       # cuánto tarda el aviso en vivo: la venta y lo agregado en cocina, el cambio de estado en recepción
```

Las pruebas de `pruebas/` aceptan `KEYCLOAK_URL` y `API_URL` para ejecutarse contra el
despliegue público. La tabla completa de casos de prueba está en el apartado 2.8 del
documento monográfico.

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
├── scripts/      Publicar la app, preparar las fotos de la carta y dibujar las bebidas
└── docs/         Documentación técnica: BRIEF de desarrollo y planes de trabajo
```

## Dirección pública

| Qué | Dirección |
|---|---|
| Aplicación | **https://maxpizzapp.tech** |
| Identidad (Keycloak) | https://auth.maxpizzapp.tech |

Para entrar, las cuentas de prueba del apartado *Credenciales de prueba*.

## La carta

La carta vive en `docker/postgres/init/05_carta.sql` y se cambia sin tocar el esquema:

- **Las 15 pizzas son las del local**, con sus ingredientes, tomadas de su catálogo. Sus
  **precios están por confirmar** con la dueña.
- **Las bebidas y los extras son ficticios** hasta tener los reales.

El local vende **solo pizzas enteras**, de un sabor o de dos mitades. Una pizza de dos
mitades cuesta (precio A + precio B) / 2, al centavo. Dos estaciones, Tres estaciones y
Criolla española ya combinan varios sabores y se venden **solo enteras**: no pueden ser
mitad de otra (columna `producto.solo_entera`).

Las imágenes viven en `frontend/web/carta/`, y la base guarda solo el nombre del archivo,
nunca la imagen ni una dirección:

- **Las pizzas usan las fotos del local.** `scripts/preparar-fotos.py` las prepara a partir
  de una carpeta de originales: asigna cada archivo a su pizza por el nombre y la deja en
  WebP de 640 × 640 (unos 80 KB cada una). Los originales no se versionan.

  ```bash
  python scripts/preparar-fotos.py "ruta/a/la/carpeta/de/fotos"
  ```

- **Las bebidas, ficticias, tienen un dibujo** hecho por `scripts/dibujar-carta.py` con
  formas simples, sin imágenes de terceros.

## Identidad visual

La app lleva la identidad de **Max's Pizzas**, con su autorización: el logo «MP» en la
barra, en la pantalla de acceso y como ícono de la app, y su paleta.

- **Tema claro fijo:** fondo crema `#FBF6EE` con tarjetas blancas, para que luzcan las fotos
  de las pizzas. La app no sigue el modo claro u oscuro del dispositivo.
- **Rojo ladrillo `#C0392B`** en la barra superior, los botones y los íconos, y un
  **amarillo suave `#FFE58A`** en los precios y en lo que está elegido. Son los colores de
  la marca bajados de tono.
- **El negro, el amarillo `#FAF126` y el rojo `#F90304` puros quedan solo en el logo.**

Las pruebas miden el contraste de cada combinación de colores con la fórmula de WCAG, así
que un cambio de color que deje un texto ilegible no pasa. El logo vive en
`frontend/assets/marca/`, y los íconos de `frontend/web/` se generaron a partir de él.

El **software** se llama Max Pizzapp; el **local**, Max's Pizzas.

## Variables de entorno

Todas se documentan en `.env.example`: se copia como `.env` y se completan los valores. El
`.env` **nunca** se versiona, y el de producción no es una copia del de desarrollo: sus
contraseñas se generan en el servidor y no salen de ahí.

| Variable | Obligatoria | Descripción |
|---|---|---|
| `POSTGRES_DB` | Sí | Nombre de la base de datos |
| `POSTGRES_USER` | Sí | Usuario de la base |
| `POSTGRES_PASSWORD` | Sí | Contraseña de la base |
| `POSTGRES_PORT` | No | Puerto del host si se publica la base en desarrollo (5433). Por omisión no se publica |
| `NODE_ENV` | No | `development` o `production`. La imagen de la API ya trae `production` |
| `API_PORT` | Solo en desarrollo | Puerto del host para la API (3001) |
| `KEYCLOAK_PORT` | Solo en desarrollo | Puerto del host para Keycloak (8082) |
| `KEYCLOAK_REALM` | Sí | El realm del sistema: `maxpizzapp` |
| `KEYCLOAK_CLIENT_ID` | No | La audiencia que la API exige en los tokens. Por omisión, `backend-api` |
| `KEYCLOAK_ADMIN` | Sí | Usuario administrador de la consola de Keycloak |
| `KEYCLOAK_ADMIN_PASSWORD` | Sí | Su contraseña |
| `KEYCLOAK_DEMO_PASSWORD` | Sí | Contraseña de las cuentas de prueba; la usan también las pruebas de `pruebas/` |
| `KEYCLOAK_INTERNAL_URL` | No | Keycloak por la red interna de Docker. Por omisión, `http://keycloak:8080` |
| `DOMINIO` | Sí, en producción | Dominio raíz, sin protocolo ni barra final: de él salen la dirección de la app, la de Keycloak y el emisor de los tokens |
| `CADDY_EMAIL` | Sí, en producción | Correo al que Let's Encrypt avisa si un certificado está por vencer |
| `WEB_DIR` | No | Carpeta del servidor con la app publicada. Por omisión, `/opt/maxpizzapp-web` |

No van en el `.env` las variables que Compose le pasa a la API, como el emisor de los
tokens (`KEYCLOAK_ISSUER`), porque se derivan de las anteriores. Tampoco hay secretos para
firmar tokens ni orígenes CORS: los tokens los firma Keycloak, y la app y la API comparten
origen.

## Requisitos previos

- Git.
- Docker con el plugin de Compose (en Windows, Docker Desktop).
- Flutter 3.44.8 (stable), para compilar y probar la app.
- Node.js 24 LTS, para las pruebas del backend y la medición del aviso en vivo.
- Python 3, solo con su biblioteca estándar, para las pruebas de `pruebas/`. Los
  `scripts/` que preparan las imágenes de la carta usan además Pillow.

## Puesta en marcha en local

Todo se ejecuta desde la raíz del repositorio.

1. Clonar el repositorio y crear el `.env` a partir de `.env.example`, completando las
   contraseñas:

   ```bash
   git clone https://github.com/jorgeluisgutierrezrivera/max-pizzapp.git
   cd max-pizzapp
   cp .env.example .env
   ```

2. Levantar la base de datos, Keycloak y la API:

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
entorno y un servidor con Docker, se levanta igual en cualquier proveedor. El detalle
completo está en el apartado 2.9 del documento y en el Anexo B, *Manual de instalación y
despliegue*.

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
docker compose --env-file .env -f docker/docker-compose.prod.yml up -d --build
```

`--build` hace falta porque la imagen de la API se construye con el código del repositorio:
sin él, Compose reutiliza la imagen anterior y el código nuevo no llega al contenedor.

**Si el cambio trae una migración nueva** en `docker/postgres/init/`: los scripts de esa
carpeta solo corren al **crear** la base, así que en una base que ya existe hay que aplicar
cada archivo nuevo una vez, a mano, **en orden de número**. Antes, un respaldo de la base,
fuera de la carpeta del repositorio:

```bash
mkdir -p /opt/respaldos
docker exec maxpizzapp-bd sh -c 'pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  > /opt/respaldos/maxpizzapp-$(date +%F-%H%M).dump
ls -lh /opt/respaldos
```

Y después, las migraciones:

```bash
for f in 02_porciones_y_carta 04_solo_enteras_y_extras 05_carta 06_pedido_cliente_y_cancelacion 07_numero_agregados_y_venta_directa 08_pizzas_solo_enteras; do
  docker exec -i maxpizzapp-bd sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    < docker/postgres/init/$f.sql || break
done
```

El orden importa: la `04` ajusta lo que agregó la `02`, la carta (`05`) usa lo que agrega
la `04`, la `06` suma lo que necesitan los pedidos, la `07` el número del día, lo que se
agrega a un pedido y la venta directa de bebidas, y la `08` marca las pizzas que se venden
solo enteras. Y van **antes** del `up -d --build`:
la API nueva ya consulta las columnas que ellas agregan. No hay `03`: era una carta
ficticia que la real reemplazó. Volver a cargar la carta actualiza los productos por su
nombre sin duplicarlos, y no revive uno que cocina marcó agotado.

La `06` exige que todo pedido tenga cliente. Si encontrara uno sin cliente, se detiene
**sin cambiar nada**: corre en una sola transacción. La `07` numera los pedidos que ya
existían, día por día y en orden de llegada, y a partir de ahí solo la venta directa puede
quedar sin cliente.

Las migraciones están escritas para que aplicarlas dos veces no cambie nada ni falle. No se
edita nunca una migración que ya se aplicó: el cambio siguiente va en un archivo nuevo.

Compose solo recrea los servicios cuya configuración cambió. Hay una excepción:
`--import-realm` **no sobrescribe** un realm que ya existe, así que un cambio en el archivo
del realm también hay que aplicarlo desde la consola de Keycloak.

Los contenedores se reinician con `restart: unless-stopped`: tras un reinicio completo del
servidor, el sistema vuelve solo.

## Licencia

Uso académico. Todos los derechos reservados por el autor. El nombre, el logo y las fotos
de Max's Pizzas se usan con autorización del local y no forman parte de esta licencia.
