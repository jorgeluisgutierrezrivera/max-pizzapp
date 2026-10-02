#!/usr/bin/env bash
# ==========================================================
# Corre las dos suites automaticas y deja sus reportes en el
# repositorio (tarjeta 10, D-57):
#   docs/pruebas/reportes/api.txt y api-junit.xml   la API
#   docs/pruebas/reportes/app.txt                   la app Flutter
#
# Uso, desde la raiz del repositorio (Git Bash en Windows):
#   bash scripts/correr-pruebas.sh
#
# Ninguna de las dos necesita la base, Keycloak ni un .env. La de
# la API necesita Node (y antes, una vez, `cd backend && npm ci`);
# la de la app, Flutter. Las pruebas contra produccion son otra
# cosa: pruebas/correr_sondas.py.
# ==========================================================
set -euo pipefail

cd "$(dirname "$0")/.."
REPORTES="docs/pruebas/reportes"
mkdir -p "$REPORTES"
FALLAS=0

echo "==> La API"
(cd backend && npm run test:reporte) || FALLAS=1

echo "==> La app"
INICIO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# El reporte de Flutter se escribe primero dentro de build/ (fuera del repositorio) y despues
# se le pone la cabecera. La ruta es relativa: flutter es un programa de Windows y no
# entiende las rutas /tmp de Git Bash.
set +e
(cd frontend && flutter test --file-reporter "expanded:build/reporte-de-la-app.txt")
ESTADO_APP=$?
set -e
[ "$ESTADO_APP" -eq 0 ] || FALLAS=1
{
  echo "Max Pizzapp - reporte de la suite de la app"
  echo "Fecha:   $INICIO"
  echo "Version: $(cd frontend && flutter --version 2>/dev/null | head -n 1)"
  echo "Comando: cd frontend && flutter test   (este reporte: bash scripts/correr-pruebas.sh)"
  echo "Sin servidor: la API, Keycloak y el canal en vivo son simulados."
  if [ "$ESTADO_APP" -eq 0 ]; then echo "Resultado: TODO EN VERDE"; else echo "Resultado: CON FALLAS"; fi
  printf '%78s\n' '' | tr ' ' '-'
  echo
  # Las rutas, relativas: la absoluta depende de la maquina en que se corrio.
  sed -E 's#([A-Za-z]:)?/[^:]*/frontend/test/#test/#g' frontend/build/reporte-de-la-app.txt
} > "$REPORTES/app.txt"
rm -f frontend/build/reporte-de-la-app.txt

echo
echo "==> Reportes en $REPORTES:"
ls -1 "$REPORTES"
exit "$FALLAS"
