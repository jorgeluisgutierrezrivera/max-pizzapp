#!/usr/bin/env bash
# ==========================================================
# Instalacion local de Max Pizzapp en un solo paso (tarjeta 13, D-63),
# para Linux y macOS. En Windows: instalar.cmd (scripts/instalar.ps1).
#
# Uso, desde la raiz del repositorio:
#   bash scripts/instalar.sh              instala, o vuelve a levantar lo instalado
#   bash scripts/instalar.sh desde-cero   borra los datos de ESTA instalacion y la rehace
#
# Solo necesita Docker con Compose. Hace lo mismo que la version de
# Windows: comprueba Docker, crea el .env con contrasenas al azar (nunca
# pisa uno existente), detecta una instalacion anterior sin su .env,
# comprueba los puertos, levanta con el perfil "completo", espera a que
# la app y la API respondan y muestra la direccion y las cuentas.
#
# Es el que corre la integracion continua (.github/workflows/instalacion.yml).
# Ahi no hay quien escriba SI: con CI=true, desde-cero no pregunta.
# ==========================================================
set -euo pipefail

cd "$(dirname "$0")/.."
RAIZ="$(pwd)"
MODO="${1:-}"
COMPOSE=(docker compose --env-file .env -f docker/docker-compose.yml --profile completo)
VOLUMEN=maxpizzapp_postgres_datos
DIRECCION=http://localhost:8090

paso() { printf '\n[%s/6] %s\n' "$1" "$2"; }
falla() { printf '\nNO SE PUDO TERMINAR LA INSTALACION\n%b\n' "$1" >&2; exit 1; }
leer() { { grep -E "^$1=" .env || true; } | tail -n 1 | cut -d= -f2- | tr -d '\r'; }
# 24 caracteres al azar, letras y numeros, del generador del sistema.
azar() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true; }

echo "=========================================================="
echo " Max Pizzapp - instalacion local"
echo "=========================================================="
echo "Carpeta: $RAIZ"
echo "La primera vez tarda bastante: descarga y prepara todo lo necesario."

# ----------------------------------------------------------
paso 1 "Docker"
command -v docker >/dev/null 2>&1 || falla "No se encontro Docker. Instale Docker (con Compose) y vuelva a intentar."
docker info >/dev/null 2>&1 || falla "Docker no responde: arranquelo y vuelva a intentar."
docker compose version >/dev/null 2>&1 || falla "Docker responde, pero sin el plugin de Compose."
echo "Docker responde."

# ----------------------------------------------------------
paso 2 "Archivo de configuracion (.env)"
HAY_VOLUMEN=no
docker volume inspect "$VOLUMEN" >/dev/null 2>&1 && HAY_VOLUMEN=si

case "$MODO" in
  "") ;;
  desde-cero)
    echo "Va a BORRAR los datos de esta instalacion (pedidos y cuentas) y empezar de nuevo."
    if [ "${CI:-}" != "true" ]; then
      read -r -p "Escriba SI (en mayusculas) para continuar: " RESPUESTA
      [ "$RESPUESTA" = "SI" ] || falla "No se borro nada."
    fi
    "${COMPOSE[@]}" down -v --remove-orphans
    HAY_VOLUMEN=no
    echo "Datos anteriores borrados." ;;
  *) falla "No conozco la opcion '$MODO'. Las opciones son: ninguna, o desde-cero." ;;
esac

if [ -f .env ]; then
  echo "Ya hay un .env: se usa el que esta (no se cambia nada)."
else
  [ "$HAY_VOLUMEN" = "no" ] || falla "Hay datos de una instalacion anterior, pero falta su .env: sus contrasenas
ya no coinciden. Para empezar de nuevo, borrando esos datos:
    bash scripts/instalar.sh desde-cero"
  [ -f .env.example ] || falla "Falta el archivo .env.example."
  # El usuario de la base no es un secreto; las contrasenas, al azar.
  sed -e 's/^POSTGRES_USER=cambia_.*$/POSTGRES_USER=maxpizzapp/' \
      -e "s/^POSTGRES_PASSWORD=cambia_.*\$/POSTGRES_PASSWORD=$(azar)/" \
      -e "s/^KEYCLOAK_ADMIN_PASSWORD=cambia_.*\$/KEYCLOAK_ADMIN_PASSWORD=$(azar)/" \
      -e "s/^KEYCLOAK_DEMO_PASSWORD=cambia_.*\$/KEYCLOAK_DEMO_PASSWORD=$(azar)/" \
      .env.example | tr -d '\r' > .env.nuevo
  if grep -qE '^[A-Z_]+=cambia_' .env.nuevo; then
    rm -f .env.nuevo
    falla "El .env.example tiene un valor cambia_ que el instalador no conoce."
  fi
  chmod 600 .env.nuevo
  mv .env.nuevo .env
  echo "Creado el .env, con contrasenas generadas al azar en esta maquina."
fi
PUERTO_KEYCLOAK="$(leer KEYCLOAK_PORT)"
PUERTO_API="$(leer API_PORT)"
CLAVE_DEMO="$(leer KEYCLOAK_DEMO_PASSWORD)"
[ -n "$PUERTO_KEYCLOAK" ] && [ -n "$PUERTO_API" ] && [ -n "$CLAVE_DEMO" ] \
  || falla "Al .env le falta KEYCLOAK_PORT, API_PORT o KEYCLOAK_DEMO_PASSWORD."

# ----------------------------------------------------------
paso 3 "Puertos"
# Un puerto ocupado por un contenedor de esta instalacion no es un problema.
for PUERTO in 8090 "$PUERTO_KEYCLOAK" "$PUERTO_API"; do
  if (exec 3<>"/dev/tcp/127.0.0.1/$PUERTO") 2>/dev/null; then
    docker ps --format '{{.Ports}}' | grep -q ":$PUERTO->" \
      || falla "El puerto $PUERTO lo esta usando otro programa. Cierrelo y vuelva a intentar."
  fi
done
echo "Libres: 8090 (la app), $PUERTO_KEYCLOAK (el acceso) y $PUERTO_API (la API)."

# ----------------------------------------------------------
paso 4 "Construir y levantar el sistema"
if ! "${COMPOSE[@]}" up -d --build; then
  ESTADO="$(docker inspect -f '{{.State.ExitCode}}' maxpizzapp-auth-config 2>/dev/null || true)"
  if [ -n "$ESTADO" ] && [ "$ESTADO" != "0" ]; then
    echo "Lo ultimo que dijo la configuracion del acceso (Keycloak):"
    docker logs --tail 15 maxpizzapp-auth-config || true
  fi
  falla "Docker no pudo levantar el sistema (el detalle esta arriba)."
fi

# ----------------------------------------------------------
paso 5 "Esperar a que responda"
LISTO=no
for _ in $(seq 1 60); do
  if curl -fs -o /dev/null "$DIRECCION/api/v1/salud" 2>/dev/null && curl -fs -o /dev/null "$DIRECCION/" 2>/dev/null; then
    LISTO=si; break
  fi
  sleep 3
done
if [ "$LISTO" = "no" ]; then
  "${COMPOSE[@]}" ps
  falla "El sistema arranco pero no responde en $DIRECCION despues de 3 minutos."
fi
echo "La API responde (salud 200) y la app carga."

# ----------------------------------------------------------
paso 6 "Listo"
echo
echo "=========================================================="
echo " Max Pizzapp esta funcionando en esta maquina"
echo "=========================================================="
echo " Direccion:  $DIRECCION"
echo " Recepcion:  recepcion.demo"
echo " Cocina:     cocina.demo"
echo " Para detenerlo:  ${COMPOSE[*]} stop"
echo " Para volver a abrirlo: bash scripts/instalar.sh"
echo
# En la integracion continua la contrasena no se imprime: quedaria en el registro publico.
if [ "${CI:-}" = "true" ]; then
  echo " La contrasena de las cuentas de prueba esta en el .env (KEYCLOAK_DEMO_PASSWORD)."
else
  echo " Contrasena de las dos cuentas de prueba: $CLAVE_DEMO"
fi
