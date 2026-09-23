#!/usr/bin/env bash
# ==========================================================
# Publica la app Flutter en el servidor.
#
# Uso, desde la raiz del repositorio (Git Bash en Windows):
#   bash scripts/publicar-web.sh root@IP-DEL-SERVIDOR
#
# QUE HACE
#   1. Compila la app en ESTA maquina, en modo release. Nunca en
#      el servidor: la compilacion usa mas memoria y procesador que
#      todo el sistema en marcha, y el servidor tiene 1 vCPU.
#   2. La copia al servidor en una carpeta nueva, con la fecha y
#      hora como nombre: /opt/maxpizzapp-web/versiones/<version>.
#   3. Recien cuando la copia termino, mueve el enlace "actual" a
#      esa carpeta. Mover un enlace es instantaneo: nadie ve una
#      version a medias. Caddy sirve siempre lo que apunta "actual".
#   4. Conserva las 3 ultimas versiones, para poder volver atras.
#
# Sin --dart-define: en produccion la app deduce Keycloak del
# dominio. Ninguna direccion queda escrita en el build.
#
# VOLVER A LA VERSION ANTERIOR (en el servidor):
#   cd /opt/maxpizzapp-web && ls versiones
#   ln -sfn versiones/<version-anterior> actual.nuevo && mv -T actual.nuevo actual
# ==========================================================
set -euo pipefail

DESTINO="${1:?Uso: bash scripts/publicar-web.sh root@IP-DEL-SERVIDOR}"
RAIZ_REMOTA="/opt/maxpizzapp-web"
VERSION="$(date +%Y%m%d-%H%M%S)"
CONSERVAR=3

cd "$(dirname "$0")/../frontend"

echo "==> Compilando la app (release)"
flutter build web --release

echo "==> Copiando la version $VERSION a $DESTINO"
tar -C build/web -czf - . | ssh "$DESTINO" "
  set -e
  mkdir -p '$RAIZ_REMOTA/versiones/$VERSION'
  tar -xzf - -C '$RAIZ_REMOTA/versiones/$VERSION'
  test -f '$RAIZ_REMOTA/versiones/$VERSION/index.html'
  cd '$RAIZ_REMOTA'
  ln -sfn 'versiones/$VERSION' actual.nuevo
  mv -T actual.nuevo actual
  ls -1d versiones/* | sort -r | tail -n +$((CONSERVAR + 1)) | xargs -r rm -rf
  echo \"    publicada: \$(readlink actual)\"
  echo \"    versiones: \$(ls versiones | tr '\n' ' ')\"
"

echo "==> Listo. Caddy ya sirve la version $VERSION."
