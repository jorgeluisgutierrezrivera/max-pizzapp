#!/usr/bin/env bash
# ==========================================================
# Aplica la configuracion de seguridad de Keycloak (D-53, D-54).
#
# Uso, desde la raiz del repositorio (en el servidor, /opt/maxpizzapp),
# con Keycloak en marcha:
#   bash scripts/endurecer-keycloak.sh
#
# POR QUE UN SCRIPT
#   --import-realm solo importa el realm la PRIMERA vez: lo que cambia
#   despues en realm-maxpizzapp.json no llega solo a una base que ya
#   existe. Antes, cada ajuste de produccion se hacia a mano en la
#   consola. Este script lo hace con kcadm, igual en desarrollo y en
#   produccion, y se puede correr las veces que haga falta: el
#   resultado es siempre el mismo.
#
#   En una instalacion nueva tambien hace falta: al crear el realm,
#   Keycloak llena el rol por defecto con cuatro roles de fabrica,
#   aunque el archivo diga otra cosa. Se corre una vez despues del
#   primer arranque.
#
# QUE HACE
#   1. El cliente frontend-web acepta solo cuatro direcciones de
#      retorno, exactas: la web, el APK, la web en desarrollo y la de
#      las sondas de pruebas/ (D-53). Los origenes web, explicitos.
#   2. El realm del sistema: contrasenas de 12 caracteres o mas, que
#      no sean el usuario, guardadas con Argon2; y los eventos de
#      acceso, guardados 7 dias (D-54).
#   3. El rol por defecto, vacio: una cuenta nueva nace sin ningun
#      rol, y la API le responde 403 en todo (D-54).
#   4. El realm master, el de la consola de administracion: la misma
#      proteccion de fuerza bruta y la misma politica de contrasenas.
#   Al final muestra como quedo cada cosa.
#
# LA CUENTA DE ADMINISTRACION
#   Por omision, la del .env (KEYCLOAK_ADMIN y KEYCLOAK_ADMIN_PASSWORD):
#   la temporal con la que arranca Keycloak. Despues de reemplazarla
#   por una permanente (docker/keycloak/README.md), se indica cual usar
#   y el script pide la contrasena sin mostrarla:
#     KC_USUARIO=nombre.de.tu.cuenta bash scripts/endurecer-keycloak.sh
#   La contrasena nunca se escribe en la linea de comandos ni en la
#   salida: llega al contenedor por una variable de entorno.
# ==========================================================
set -euo pipefail

cd "$(dirname "$0")/.."
CONTENEDOR="${CONTENEDOR_KEYCLOAK:-maxpizzapp-auth}"

# Lee una variable del .env sin ejecutarlo ni mostrarlo.
leer() {
  [ -f .env ] || return 0
  # Una variable que no esta no es un error: queda el valor por omision.
  { grep -E "^$1=" .env || true; } | tail -n 1 | cut -d= -f2- | tr -d '\r'
}

REALM="$(leer KEYCLOAK_REALM)"
REALM="${REALM:-maxpizzapp}"
DOMINIO="$(leer DOMINIO)"
DOMINIO="${DOMINIO:-maxpizzapp.tech}"

if [ -n "${KC_USUARIO:-}" ]; then
  # Una cuenta indicada a mano: la contrasena se pide, nunca se lee del .env.
  if [ -z "${KC_CLAVE:-}" ]; then
    read -r -s -p "Contrasena de $KC_USUARIO (no se muestra): " KC_CLAVE
    echo
  fi
else
  KC_USUARIO="$(leer KEYCLOAK_ADMIN)"
  KC_CLAVE="$(leer KEYCLOAK_ADMIN_PASSWORD)"
fi
if [ -z "$KC_USUARIO" ] || [ -z "${KC_CLAVE:-}" ]; then
  echo "Falta la cuenta de administracion: KEYCLOAK_ADMIN en el .env, o KC_USUARIO=..." >&2
  exit 1
fi

echo "==> Keycloak: contenedor $CONTENEDOR, realm $REALM, dominio $DOMINIO"

# El script de adentro corre en el contenedor; las variables viajan por
# el entorno de docker exec (-e NOMBRE, sin valor), no en sus argumentos.
KA="$KC_USUARIO" KP="$KC_CLAVE" R="$REALM" D="$DOMINIO" \
  docker exec -i -e KA -e KP -e R -e D "$CONTENEDOR" sh -s <<'ADENTRO'
set -eu
K=/opt/keycloak/bin/kcadm.sh
CONF=/tmp/kcadm-endurecer.config
trap 'rm -f "$CONF"' EXIT
C="--config $CONF"

if ! $K config credentials $C --server http://localhost:8080 --realm master \
    --user "$KA" --password "$KP" >/dev/null 2>&1; then
  echo "ERROR: Keycloak no acepto la cuenta de administracion $KA." >&2
  echo "Si ya la reemplazaste por una permanente: KC_USUARIO=tu.cuenta bash scripts/endurecer-keycloak.sh" >&2
  exit 3
fi

echo "1. Las direcciones de retorno del cliente frontend-web, exactas (D-53)"
CID=$($K get clients $C -r "$R" -q clientId=frontend-web --fields id --format csv --noquotes)
if [ -z "$CID" ]; then
  echo "ERROR: el realm $R no tiene el cliente frontend-web." >&2
  exit 4
fi
$K update "clients/$CID" $C -r "$R" \
  -s "redirectUris=[\"https://$D/\",\"tech.maxpizzapp.cocina:/callback\",\"http://localhost:8090/\",\"http://localhost:9999/callback\"]" \
  -s "webOrigins=[\"https://$D\",\"http://localhost:8090\"]" \
  -s "attributes.\"post.logout.redirect.uris\"=https://$D/##tech.maxpizzapp.cocina:/callback##http://localhost:8090/"

echo "2. Contrasenas con Argon2 y eventos de acceso (D-54)"
POLITICA='length(12) and notUsername and hashAlgorithm(argon2)'
$K update "realms/$R" $C \
  -s "passwordPolicy=$POLITICA" \
  -s eventsEnabled=true -s eventsExpiration=604800 \
  -s 'enabledEventTypes=["LOGIN","LOGIN_ERROR","LOGOUT","LOGOUT_ERROR","CODE_TO_TOKEN","CODE_TO_TOKEN_ERROR","REFRESH_TOKEN_ERROR"]'

echo "3. El rol por defecto, vacio (D-54)"
# Los de fabrica: dos del realm y los dos de la consola de cuenta. Quitar
# uno que ya no esta no falla, asi que se puede repetir.
$K remove-roles $C -r "$R" --rname "default-roles-$R" \
  --rolename offline_access --rolename uma_authorization
$K remove-roles $C -r "$R" --rname "default-roles-$R" \
  --cclientid account --rolename view-profile --rolename manage-account

echo "4. La consola de administracion: fuerza bruta y contrasenas en master"
$K update realms/master $C \
  -s bruteForceProtected=true -s permanentLockout=false -s failureFactor=5 \
  -s waitIncrementSeconds=60 -s maxFailureWaitSeconds=900 \
  -s minimumQuickLoginWaitSeconds=60 -s quickLoginCheckMilliSeconds=1000 \
  -s "passwordPolicy=$POLITICA"

echo
echo "== Como quedo"
echo "-- frontend-web:"
$K get "clients/$CID" $C -r "$R" --fields redirectUris,webOrigins
# --fields no muestra los atributos (un mapa anidado): se leen del cliente entero.
$K get "clients/$CID" $C -r "$R" | grep -E '"(post\.logout\.redirect\.uris|pkce\.code\.challenge\.method)"'
echo "-- realm $R:"
$K get "realms/$R" $C --fields passwordPolicy,eventsEnabled,eventsExpiration,bruteForceProtected,failureFactor
echo "-- rol por defecto (vacio = []):"
$K get "roles/default-roles-$R/composites" $C -r "$R" --fields name
echo "-- realm master:"
$K get realms/master $C --fields bruteForceProtected,failureFactor,passwordPolicy
echo "-- cuentas de administracion (la que dice is_temporary_admin es la de arranque):"
$K get users $C -r master | grep -E '"username"|is_temporary_admin' || true
ADENTRO

echo "==> Listo."
