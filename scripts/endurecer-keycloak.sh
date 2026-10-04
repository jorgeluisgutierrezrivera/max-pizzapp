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

# La parte de adentro es docker/keycloak/endurecer.sh (D-64): la misma que
# corre el servicio keycloak-config en la instalacion local. Se la pasa al
# contenedor por la entrada estandar; las variables viajan por el entorno de
# docker exec (-e NOMBRE, sin valor), no en sus argumentos.
KA="$KC_USUARIO" KP="$KC_CLAVE" R="$REALM" D="$DOMINIO" \
  docker exec -i -e KA -e KP -e R -e D "$CONTENEDOR" sh -s < docker/keycloak/endurecer.sh

echo "==> Listo."
