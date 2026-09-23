# Identidad — configuración de Keycloak

`realm-maxpizzapp.json` es la **configuración de identidad del sistema versionada como
archivo**: el *realm*, los dos roles, los dos clientes y las dos cuentas de demostración.
Keycloak lo importa al arrancar (`--import-realm`), tanto en desarrollo como en el
servidor.

Está en el repositorio a propósito. La parte cara de Keycloak —clientes, URI de
redirección, orígenes permitidos, mapeadores— es la que falla la primera vez que se
despliega, y resolverla aquí significa que en el servidor sea una importación en vez de una
sesión de clics imposible de repetir igual.

## Qué define

| Pieza | Valor | Por qué |
|---|---|---|
| *Realm* | `maxpizzapp` | El espacio propio del sistema; no se usa el `master`, que es solo para administrar Keycloak |
| Roles | `recepcion` · `cocina` | Los **dos** roles del sistema. El rol administrador quedó fuera de alcance |
| Cliente de la app | `frontend-web`, **público**, *Authorization Code* + **PKCE (S256)** | Vive en el navegador y no puede guardar un secreto. Sin PKCE, un código interceptado sirve para pedir el token |
| Cliente de la API | `backend-api`, **confidencial**, sin flujos habilitados | La API no inicia sesiones: solo valida tokens. Existe para ser **audiencia** de los que emite la app |
| Mapeador de audiencia | Añade `backend-api` al `aud` del token | Permite que el servidor rechace un token emitido para otra aplicación, aunque la firma sea válida |
| Vida del token | 3600 s (60 min) | Es lo que declara el RNF-02 del documento |
| Protección de fuerza bruta | 5 intentos, espera creciente hasta 15 min | Lo exige el RNF-02 y lo resuelve el proveedor, no código propio |
| Registro de usuarios | Deshabilitado | No es un sistema con autoservicio: las cuentas las crea el negocio |

## Lo que este archivo NO contiene, y no debe contener

**Ninguna contraseña.** Las dos cuentas de demostración se importan *sin credenciales*: el
archivo crea la cuenta y su rol, pero la contraseña se establece aparte. Un secreto en el
repositorio es un secreto público, y el requisito mínimo 7 del módulo lo prohíbe
explícitamente.

El secreto del cliente `backend-api` tampoco está: lo genera Keycloak al importar.

### Establecer las contraseñas después de importar

Desde la consola de administración (`http://localhost:8082` en desarrollo) →
*realm* `maxpizzapp` → *Users* → la cuenta → pestaña *Credentials* → *Set password*, con
*Temporary* en **Off**.

O por línea de comandos, sin que la contraseña quede escrita en ningún archivo:

```bash
docker exec -it maxpizzapp-auth /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin
docker exec -it maxpizzapp-auth /opt/keycloak/bin/kcadm.sh set-password \
  -r maxpizzapp --username recepcion.demo
```

### En producción

La consola está en `https://auth.maxpizzapp.tech/admin`, solo por HTTPS. Las contraseñas de
las cuentas demo se asignan leyendo el `.env` del servidor, sin escribirlas en la terminal:

```bash
cd /opt/maxpizzapp && set -a && . ./.env && set +a
docker exec -e KA="$KEYCLOAK_ADMIN" -e KP="$KEYCLOAK_ADMIN_PASSWORD" -e DP="$KEYCLOAK_DEMO_PASSWORD" \
  maxpizzapp-auth sh -c '
    K=/opt/keycloak/bin/kcadm.sh
    $K config credentials --server http://localhost:8080 --realm master --user "$KA" --password "$KP"
    for u in recepcion.demo cocina.demo; do $K set-password -r maxpizzapp --username $u --new-password "$DP"; done
    rm -f /opt/keycloak/.keycloak/kcadm.config'
```

## El dominio público

Las URI de redirección incluyen `https://maxpizzapp.tech/*`, que reemplazó al marcador
original antes de la primera importación en el servidor. Si el dominio cambia, hay que
cambiarlo aquí **antes** de importar. Si se olvida, el inicio de sesión falla con
*"Invalid parameter: redirect_uri"*: es un fallo ruidoso e inmediato, no silencioso.

**Ojo:** `--import-realm` **no sobrescribe** un realm que ya existe en la base. Un cambio en
este archivo después del primer despliegue no se aplica solo al reiniciar: hay que hacerlo
también desde la consola (o `kcadm`) o recrear la base de Keycloak.

Las URI de `localhost` se dejan a propósito: permiten seguir desarrollando contra el mismo
realm sin mantener dos archivos que se desincronizan.

## Si se cambia algo desde la consola

La consola escribe en la base de datos, **no en este archivo**. Un cambio hecho a mano se
pierde en el siguiente despliegue limpio. Para conservarlo hay que exportarlo y actualizar
el archivo:

```bash
docker exec maxpizzapp-auth /opt/keycloak/bin/kc.sh export \
  --dir /tmp/export --realm maxpizzapp --users skip
docker cp maxpizzapp-auth:/tmp/export/maxpizzapp-realm.json ./realm-exportado.json
```

`--users skip` evita arrastrar los datos de las cuentas al repositorio. Después hay que
comparar con el archivo versionado y llevar a mano lo que corresponda: un export en bruto
trae mucho ruido de configuración por defecto.
