#!/bin/sh
# ==========================================================
# La configuracion de seguridad de Keycloak (D-53, D-54), la parte que
# corre DENTRO de un contenedor con la imagen de Keycloak (usa kcadm).
#
# Es una sola fuente para los dos usos (D-64):
#   - scripts/endurecer-keycloak.sh se la pasa a "docker exec" en el
#     contenedor de Keycloak, en desarrollo y en produccion;
#   - el servicio keycloak-config de docker/docker-compose.yml (perfil
#     "completo") la corre en el arranque de la instalacion local.
#
# Recibe todo por variables de entorno, nunca por argumentos (asi
# ninguna contrasena aparece en la lista de procesos):
#   KA, KP  la cuenta de administracion y su contrasena
#   R       el realm del sistema (maxpizzapp)
#   D       el dominio publico (maxpizzapp.tech)
#   KC_SERVIDOR  donde escucha Keycloak. Por omision, http://localhost:8080
#                (dentro de su propio contenedor).
#
# Se puede correr las veces que haga falta: el resultado es siempre el
# mismo. Que hace cada paso, en scripts/endurecer-keycloak.sh.
# ==========================================================
set -eu
K=/opt/keycloak/bin/kcadm.sh
CONF=/tmp/kcadm-endurecer.config
trap 'rm -f "$CONF"' EXIT
C="--config $CONF"
SERVIDOR="${KC_SERVIDOR:-http://localhost:8080}"

if ! $K config credentials $C --server "$SERVIDOR" --realm master \
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

echo "5. La pagina de acceso con la identidad del local (D-77)"
# El tema esta en docker/keycloak/tema/ y se monta en el contenedor. El
# nombre del realm marca "Pizzapp" para que salga en rojo, como en la app.
# Volver al tema oficial: -s loginTheme=keycloak.v2
$K update "realms/$R" $C \
  -s loginTheme=maxpizzapp \
  -s 'displayNameHtml=Max <span class="mp-rojo">Pizzapp</span>'

# Solo en la instalacion local: las contrasenas de las cuentas de prueba,
# desde KEYCLOAK_DEMO_PASSWORD (DP). En produccion se asignan aparte
# (docker/keycloak/README.md), y este bloque no corre porque DP no llega.
if [ -n "${DP:-}" ]; then
  echo "6. Las contrasenas de las cuentas de prueba"
  for u in recepcion.demo cocina.demo; do
    $K set-password $C -r "$R" --username "$u" --new-password "$DP"
    echo "   $u: lista"
  done
fi

echo
echo "== Como quedo"
echo "-- frontend-web:"
$K get "clients/$CID" $C -r "$R" --fields redirectUris,webOrigins
# --fields no muestra los atributos (un mapa anidado): se leen del cliente entero.
$K get "clients/$CID" $C -r "$R" | grep -E '"(post\.logout\.redirect\.uris|pkce\.code\.challenge\.method)"'
echo "-- realm $R:"
$K get "realms/$R" $C --fields passwordPolicy,eventsEnabled,eventsExpiration,bruteForceProtected,failureFactor,loginTheme,displayNameHtml
echo "-- rol por defecto (vacio = []):"
$K get "roles/default-roles-$R/composites" $C -r "$R" --fields name
echo "-- realm master:"
$K get realms/master $C --fields bruteForceProtected,failureFactor,passwordPolicy
echo "-- cuentas de administracion (la que dice is_temporary_admin es la de arranque):"
$K get users $C -r master | grep -E '"username"|is_temporary_admin' || true
