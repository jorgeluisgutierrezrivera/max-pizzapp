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
| Direcciones de retorno | Cuatro, **exactas**: `https://maxpizzapp.tech/` (la web), `tech.maxpizzapp.cocina:/callback` (el APK), `http://localhost:8090/` (la web en desarrollo) y `http://localhost:9999/callback` (las sondas de `pruebas/`) | Cualquier otra, aunque se parezca, se rechaza. Las mismas en desarrollo y en producción (D-53) |
| Cliente de la API | `backend-api`, **confidencial**, sin flujos habilitados | La API no inicia sesiones: solo valida tokens. Existe para ser **audiencia** de los que emite la app |
| Mapeador de audiencia | Añade `backend-api` al `aud` del token | Permite que el servidor rechace un token emitido para otra aplicación, aunque la firma sea válida |
| Vida del token | 3600 s (60 min) | Es lo que declara el RNF-02 del documento |
| Contraseñas | `length(12) and notUsername and hashAlgorithm(argon2)` | 12 caracteres o más, distinta del usuario, guardada con **Argon2id** (D-54) |
| Protección de fuerza bruta | 5 intentos, espera creciente hasta 15 min; dos fallos en menos de 1 s bloquean 60 s | Lo exige el RNF-02 y lo resuelve el proveedor, no código propio |
| Eventos de acceso | Entradas, fallos y salidas, guardados 7 días | Para ver un intento de fuerza bruta (D-54) |
| Registro de usuarios | Deshabilitado | No es un sistema con autoservicio: las cuentas las crea el negocio |
| Rol por defecto | **Vacío**, lo deja así el script (abajo) | Una cuenta nueva nace sin ningún rol: la API le responde 403 en todo (D-54) |

## El script de seguridad: `scripts/endurecer-keycloak.sh`

`--import-realm` solo importa este archivo **la primera vez**, y hay una cosa que el archivo
no puede hacer: al crear el realm, Keycloak llena el rol por defecto con cuatro roles de
fábrica (`offline_access`, `uma_authorization` y los dos de la consola de cuenta), diga lo que
diga el archivo. Por eso la configuración de seguridad se aplica con un script, que se puede
correr las veces que haga falta, en desarrollo o en el servidor:

```bash
bash scripts/endurecer-keycloak.sh
```

Se corre **una vez después del primer arranque** de una instalación nueva, y otra vez si
cambia algo de lo que aplica. Deja las direcciones de retorno exactas, la política de
contraseñas, los eventos y el rol por defecto vacío en el realm del sistema, y la protección
de fuerza bruta y la política de contraseñas también en `master`, el realm de la consola. Al
final muestra cómo quedó cada cosa. Usa la cuenta de administración del `.env`; si ya se
reemplazó por una permanente (abajo), se indica cuál y pide la contraseña sin mostrarla:

```bash
KC_USUARIO=nombre.de.tu.cuenta bash scripts/endurecer-keycloak.sh
```

### Una sola fuente: `endurecer.sh`

Lo que el script hace dentro del contenedor de Keycloak está en `docker/keycloak/endurecer.sh`
(D-64), y lo usan dos caminos:

- **`scripts/endurecer-keycloak.sh`**, en desarrollo y en producción: se lo pasa a
  `docker exec` en el contenedor `maxpizzapp-auth`.
- **El servicio `keycloak-config`** de `docker/docker-compose.yml`, en la instalación local de
  un paso (perfil `completo`): corre una vez en cada arranque, contra Keycloak por la red
  interna, y termina. Además asigna a `recepcion.demo` y `cocina.demo` la contraseña de
  `KEYCLOAK_DEMO_PASSWORD`, así quien instala no tiene que hacerlo a mano. Si falla, la app no
  arranca y el instalador muestra sus últimas líneas.

Así la configuración de seguridad de la instalación local y la de producción no pueden
desfasarse: son el mismo archivo.

## Reemplazar la cuenta temporal de administración

Keycloak arranca con una cuenta de administración **temporal**, la del `.env`
(`KEYCLOAK_ADMIN`), y la consola avisa que hay que reemplazarla. Después de correr el script:

1. En `https://auth.maxpizzapp.tech/admin`, con la cuenta temporal: realm **master** →
   *Users* → *Add user*. Un nombre propio (no `admin`) → *Create*.
2. Pestaña *Credentials* → *Set password*: una contraseña de 12 caracteres o más, guardada en
   tu gestor de contraseñas, con *Temporary* en **Off**.
3. Pestaña *Role mapping* → *Assign role* → filtrar por roles del realm → **admin** →
   *Assign*.
4. Cerrar sesión y entrar con la cuenta nueva. Recién entonces: *Users* → la cuenta `admin`
   temporal → *Delete*.

La contraseña de la cuenta permanente no se escribe en el `.env` ni en ningún archivo.
`KEYCLOAK_ADMIN` y `KEYCLOAK_ADMIN_PASSWORD` quedan en el `.env` solo para el primer arranque
de una instalación nueva: Keycloak crea la cuenta temporal únicamente cuando crea `master`.

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
las cuentas demo se asignan leyendo el `.env` del servidor, sin escribirlas en la terminal.
La cuenta de administración se pide al correr el comando (la permanente, si ya se reemplazó
la temporal), y la contraseña no se muestra:

```bash
cd /opt/maxpizzapp && DP="$(grep '^KEYCLOAK_DEMO_PASSWORD=' .env | cut -d= -f2-)" && read -r -p "Cuenta de administracion: " KA && read -r -s -p "Su contrasena: " KP && echo
KA="$KA" KP="$KP" DP="$DP" docker exec -e KA -e KP -e DP maxpizzapp-auth sh -c '
    K=/opt/keycloak/bin/kcadm.sh; C="--config /tmp/kcadm-demo.config"
    $K config credentials $C --server http://localhost:8080 --realm master --user "$KA" --password "$KP"
    for u in recepcion.demo cocina.demo; do $K set-password $C -r maxpizzapp --username $u --new-password "$DP"; done
    rm -f /tmp/kcadm-demo.config'
```

Las variables viajan con `-e NOMBRE`, sin el valor: así ninguna contraseña aparece en la lista
de procesos del servidor.

## El dominio público

Las direcciones de retorno llevan `https://maxpizzapp.tech/`, exacta. Si el dominio cambia,
hay que cambiarlo aquí **antes** de importar; el script toma el dominio de `DOMINIO`, en el
`.env`. Si se olvida, el inicio de sesión falla con *"Invalid parameter: redirect_uri"*: es
un fallo ruidoso e inmediato, no silencioso.

**Ojo:** `--import-realm` **no sobrescribe** un realm que ya existe en la base. Un cambio en
este archivo después del primer despliegue no se aplica solo al reiniciar: lo de seguridad lo
aplica el script de arriba; lo demás, la consola (o `kcadm`), o recrear la base de Keycloak.

Las dos direcciones de `localhost` se dejan a propósito, con su puerto exacto: la de la web en
desarrollo y la de las sondas de `pruebas/`, que entran con PKCE contra producción y dan la
evidencia de los 401 y 403. Es el retorno de *loopback* con puerto fijo que el RFC 8252 prevé
para un cliente que no es un navegador. Un archivo para cada entorno se desincronizaría sin
avisar.

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
