# ==========================================================
# Imagen de la app web para la instalacion local (tarjeta 13, D-62).
#
# La usa el servicio "web" de docker/docker-compose.yml, en el perfil
# "completo" (instalar.cmd / scripts/instalar.sh). NO es la de
# produccion: alli la app se compila en la maquina del autor y Caddy
# la sirve desde una carpeta del servidor (scripts/publicar-web.sh).
#
# DOS ETAPAS
#   1. compilar: Debian slim con el SDK de Flutter, la misma version
#      que el README y la integracion continua. Solo el SDK: la web no
#      necesita el de Android.
#   2. servir: la misma imagen de Caddy que produccion. El Caddyfile
#      (docker/caddy/Caddyfile.local) lo monta el compose.
#
# Asi, en la PC donde se instala solo hace falta Docker: ni Flutter,
# ni Node, ni Git.
# ==========================================================

FROM debian:bookworm-slim AS compilar

# git: el SDK de Flutter es un repositorio y su herramienta lo consulta.
# curl y unzip: con ellos la herramienta baja el SDK de Dart y los artefactos
# de la web.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip \
 && rm -rf /var/lib/apt/lists/*

# El SDK de Flutter, solo la version fijada: el codigo de su etiqueta, sin
# historia, y verificado por el commit exacto que publica Flutter para 3.44.8
# (releases_linux.json). Si no es ese commit, la imagen no se construye.
# Se descarto el paquete completo (1,5 GB, con artefactos de todas las
# plataformas): asi se bajan solo el SDK de Dart y lo de la web, en una
# conexion lenta es la diferencia entre minutos y media hora.
ARG FLUTTER_VERSION=3.44.8
ARG FLUTTER_COMMIT=058e0af2c2b57e369d905a03ac9748b0ebf543c6
RUN git clone --quiet --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter \
 && test "$(git -C /opt/flutter rev-parse HEAD)" = "${FLUTTER_COMMIT}" \
 && git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}"

# Sin estadisticas de uso, y los artefactos de la web en su propia capa: si
# solo cambia el codigo de la app, Docker reutiliza todo lo de arriba.
RUN flutter config --no-analytics --no-cli-animations \
 && dart --disable-analytics \
 && flutter precache --web --no-android --no-ios --no-linux --no-windows --no-macos --no-fuchsia

WORKDIR /app

# Primero solo las dependencias, con las versiones exactas del pubspec.lock.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile

COPY . .

# La direccion de Keycloak que usa el NAVEGADOR de esa PC, igual que el
# "flutter run --dart-define=KEYCLOAK_URL=..." del desarrollo. En localhost la
# app no la puede deducir del dominio, asi que sin ella no arranca.
ARG KEYCLOAK_URL
RUN test -n "${KEYCLOAK_URL}" || { echo "Falta el argumento KEYCLOAK_URL" >&2; exit 1; }

# Igual que en produccion: CanvasKit sale del propio origen (D-55).
RUN flutter build web --release --no-web-resources-cdn --dart-define=KEYCLOAK_URL="${KEYCLOAK_URL}"


FROM caddy:2-alpine

COPY --from=compilar /app/build/web /srv

EXPOSE 8090
