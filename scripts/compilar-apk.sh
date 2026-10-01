#!/usr/bin/env bash
# ==========================================================
# Compila el APK de cocina para publicarlo (tarjeta 12, D-51).
#
# Uso, desde la raiz del repositorio (Git Bash en Windows):
#   bash scripts/compilar-apk.sh
#   bash scripts/compilar-apk.sh https://otro-servidor   (otra direccion)
#
# QUE HACE
#   1. Revisa que este la llave de firma, FUERA del repositorio, en
#      ../llaves-android/ (key.properties y el .jks). Sin ella no
#      compila: un telefono no acepta instalar una version firmada
#      con otra llave encima de la publicada.
#   2. Compila el APK universal (cualquier telefono Android) en modo
#      release, con la direccion del servidor: por omision, produccion.
#   3. Verifica la firma con apksigner, y que NO sea la de depuracion.
#   4. Lo deja en frontend/build/max-pizzapp-cocina.apk y muestra su
#      SHA-256, para adjuntarlo al Release de GitHub con su huella.
#
# El APK no lleva secretos: el cliente de Keycloak es publico y la
# direccion del servidor no es secreta. Para publicar una version
# nueva, primero se sube el numero despues del "+" en la linea
# "version:" de frontend/pubspec.yaml: Android no instala encima una
# version con el mismo numero o menor.
# ==========================================================
set -euo pipefail

ORIGEN="${1:-https://maxpizzapp.tech}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
LLAVES="$RAIZ/../llaves-android"
SALIDA="$RAIZ/frontend/build/max-pizzapp-cocina.apk"

if [ ! -f "$LLAVES/key.properties" ]; then
  echo "ERROR: no esta la llave de firma en $LLAVES (key.properties y el .jks)." >&2
  echo "       Sin ella, el APK no se puede publicar. Ver el README: 'El APK de cocina'." >&2
  exit 1
fi

# apksigner viene con el SDK de Android: se usa el de las build-tools mas nuevas.
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${LOCALAPPDATA:-}/Android/Sdk}}"
SDK="$(cygpath -u "$SDK" 2>/dev/null || echo "$SDK")"
HERRAMIENTAS="$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
APKSIGNER="${HERRAMIENTAS}apksigner"
[ -f "$APKSIGNER" ] || APKSIGNER="$APKSIGNER.bat"
if [ ! -f "$APKSIGNER" ]; then
  echo "ERROR: no se encontro apksigner en $SDK/build-tools. Definir ANDROID_HOME." >&2
  exit 1
fi

cd "$RAIZ/frontend"

echo "==> Compilando el APK de cocina contra $ORIGEN"
flutter build apk --release -t lib/main_cocina.dart --dart-define=ORIGEN="$ORIGEN"
cp build/app/outputs/flutter-apk/app-release.apk "$SALIDA"

echo "==> Verificando la firma"
CERTIFICADO="$("$APKSIGNER" verify --print-certs "$SALIDA")"
if ! echo "$CERTIFICADO" | grep -E "certificate (DN|SHA-256 digest):"; then
  echo "ERROR: apksigner no muestra el certificado: el APK no quedo firmado." >&2
  exit 1
fi
if echo "$CERTIFICADO" | grep -q "CN=Android Debug"; then
  echo "ERROR: el APK quedo firmado con la llave de depuracion: no se publica." >&2
  exit 1
fi

echo "==> Listo: $SALIDA"
echo "    version: $(grep '^version:' pubspec.yaml | cut -d' ' -f2)"
echo "    tamano:  $(du -h "$SALIDA" | cut -f1)"
echo "    SHA-256: $(sha256sum "$SALIDA" | cut -d' ' -f1)"
