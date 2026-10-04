# ==========================================================
# Instalacion local de Max Pizzapp en un solo paso (tarjeta 13, D-63).
#
# Se abre con doble clic en instalar.cmd, en la raiz del repositorio.
# Desde una consola:
#   instalar.cmd              instala, o vuelve a levantar lo instalado
#   instalar.cmd desde-cero   borra los datos de ESTA instalacion y la rehace
#
# Solo necesita Docker Desktop. Hace, en orden:
#   1. Comprueba que Docker responde.
#   2. Crea el .env si no existe, con contrasenas al azar (nunca pisa uno
#      que ya existe), y detecta una instalacion anterior sin su .env.
#   3. Comprueba que los puertos esten libres.
#   4. Construye y levanta todo con el perfil "completo".
#   5. Espera a que la app y la API respondan.
#   6. Muestra la direccion y las cuentas de prueba, y abre el navegador.
#
# Compatible con Windows PowerShell 5.1, el de Windows 10. Los textos van
# sin tildes, como el resto de los scripts: PowerShell 5.1 lee los .ps1 sin
# marca de codificacion como si fueran ANSI.
#
# La version para Linux y macOS es scripts/instalar.sh.
# ==========================================================
param([string]$Modo = '')

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 2

$Raiz = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Raiz
$Compose = @('compose', '--env-file', '.env', '-f', 'docker/docker-compose.yml', '--profile', 'completo')
$Volumen = 'maxpizzapp_postgres_datos'
$Direccion = 'http://localhost:8090'

function Paso([int]$n, [string]$texto) {
    Write-Host ''
    Write-Host "[$n/6] $texto" -ForegroundColor Cyan
}

function Falla([string]$texto) {
    Write-Host ''
    Write-Host 'NO SE PUDO TERMINAR LA INSTALACION' -ForegroundColor Red
    Write-Host $texto
    Write-Host ''
    Write-Host 'Si no sabe como seguir, saque una foto de esta ventana y enviesela al autor.'
    exit 1
}

# Corre un comando de Docker sin mostrar su salida; devuelve si funciono.
# Con cmd /c, la salida de error no se convierte en un error de PowerShell.
function DockerCallado([string]$argumentos) {
    $null = cmd /c "docker $argumentos >nul 2>&1"
    return ($LASTEXITCODE -eq 0)
}

# Lee una variable de un archivo .env sin ejecutarlo.
function LeerVariable([string]$archivo, [string]$nombre) {
    if (-not (Test-Path -LiteralPath $archivo)) { return '' }
    $linea = Get-Content -LiteralPath $archivo | Where-Object { $_ -match "^$nombre=" } | Select-Object -Last 1
    if ($null -eq $linea) { return '' }
    return ($linea -replace "^$nombre=", '').Trim()
}

# 24 caracteres al azar, letras y numeros, del generador criptografico del
# sistema. Se descartan los bytes que sesgarian el reparto (rechazo).
function Azar([int]$largo) {
    $letras = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $limite = 256 - (256 % $letras.Length)
    $generador = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $byte = New-Object byte[] 1
    $texto = New-Object System.Text.StringBuilder
    while ($texto.Length -lt $largo) {
        $generador.GetBytes($byte)
        if ($byte[0] -lt $limite) { [void]$texto.Append($letras[$byte[0] % $letras.Length]) }
    }
    $generador.Dispose()
    return $texto.ToString()
}

Write-Host '=========================================================='
Write-Host ' Max Pizzapp - instalacion local'
Write-Host '=========================================================='
Write-Host "Carpeta: $Raiz"
Write-Host 'La primera vez tarda bastante: descarga y prepara todo lo necesario.'

# ----------------------------------------------------------
Paso 1 'Docker'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Falla ('No se encontro Docker en esta PC. Instale Docker Desktop (apartado B.2 del manual),' +
        "`nreinicie la PC si se lo pide y vuelva a abrir instalar.cmd.")
}
if (-not (DockerCallado 'info')) {
    Falla ('Docker Desktop no esta abierto, o todavia esta arrancando.' +
        "`nAbralo desde el menu Inicio, espere a que abajo a la izquierda diga" +
        "`n'Engine running' (el motor en marcha) y vuelva a abrir instalar.cmd.")
}
if (-not (DockerCallado 'compose version')) {
    Falla 'Docker responde, pero sin Compose. Actualice Docker Desktop y vuelva a intentar.'
}
Write-Host 'Docker responde.'

# ----------------------------------------------------------
Paso 2 'Archivo de configuracion (.env)'
$hayVolumen = DockerCallado "volume inspect $Volumen"

if ($Modo -eq 'desde-cero') {
    Write-Host 'Va a BORRAR los datos de esta instalacion (pedidos y cuentas) y empezar de nuevo.' -ForegroundColor Yellow
    $respuesta = Read-Host 'Escriba SI (en mayusculas) para continuar'
    if ($respuesta -cne 'SI') { Falla 'No se borro nada.' }
    & docker @Compose down -v --remove-orphans
    $hayVolumen = $false
    Write-Host 'Datos anteriores borrados.'
} elseif ($Modo -ne '') {
    Falla "No conozco la opcion '$Modo'. Las opciones son: ninguna, o desde-cero."
}

if (Test-Path -LiteralPath '.env') {
    Write-Host 'Ya hay un .env: se usa el que esta (no se cambia nada).'
} else {
    if ($hayVolumen) {
        Falla ('Hay datos de una instalacion anterior en esta PC, pero falta su archivo .env' +
            "`n(por ejemplo, porque se volvio a descomprimir el ZIP). Sus contrasenas ya no" +
            "`ncoinciden. Para empezar de nuevo, borrando esos datos, abra una consola en" +
            "`nesta carpeta y escriba:" +
            "`n    instalar.cmd desde-cero")
    }
    if (-not (Test-Path -LiteralPath '.env.example')) { Falla 'Falta el archivo .env.example: el ZIP no se descomprimio entero.' }
    $texto = [System.IO.File]::ReadAllText((Join-Path $Raiz '.env.example')) -replace "`r`n", "`n"
    # El usuario de la base no es un secreto; las contrasenas, al azar.
    $texto = $texto -replace '(?m)^POSTGRES_USER=cambia_.*$', 'POSTGRES_USER=maxpizzapp'
    foreach ($nombre in 'POSTGRES_PASSWORD', 'KEYCLOAK_ADMIN_PASSWORD', 'KEYCLOAK_DEMO_PASSWORD') {
        $texto = $texto -replace "(?m)^$nombre=cambia_.*$", "$nombre=$(Azar 24)"
    }
    if ($texto -match '(?m)^[A-Z_]+=cambia_') { Falla 'El .env.example tiene un valor cambia_ que el instalador no conoce.' }
    # Sin marca de codificacion y con saltos de linea de Linux: lo lee Docker.
    [System.IO.File]::WriteAllText((Join-Path $Raiz '.env'), $texto, (New-Object System.Text.UTF8Encoding $false))
    Write-Host 'Creado el .env, con contrasenas generadas al azar en esta PC.'
}
$puertoKeycloak = LeerVariable '.env' 'KEYCLOAK_PORT'
$puertoApi = LeerVariable '.env' 'API_PORT'
$claveDemo = LeerVariable '.env' 'KEYCLOAK_DEMO_PASSWORD'
if (-not $puertoKeycloak -or -not $puertoApi -or -not $claveDemo) {
    Falla 'Al .env le falta KEYCLOAK_PORT, API_PORT o KEYCLOAK_DEMO_PASSWORD.'
}

# ----------------------------------------------------------
Paso 3 'Puertos'
# Un puerto que ya ocupa Docker es de esta misma instalacion, levantada antes:
# no es un problema. Uno que ocupa otro programa, si.
#
# Excepcion en el 8090: la app se publica solo en 127.0.0.1, y en Windows esa
# direccion exacta tiene prioridad sobre un programa que escucha en 0.0.0.0
# (todas las direcciones IPv4). Pasa en la PC del autor (E-009). Lo que si
# estorba es otro programa en 127.0.0.1 o en IPv6, que el navegador prueba
# primero al abrir "localhost".
$deDocker = @('com.docker.backend', 'wslrelay', 'vpnkit', 'com.docker.proxy', 'docker-proxy')
foreach ($puerto in @(8090, [int]$puertoKeycloak, [int]$puertoApi)) {
    $escuchas = @(Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue)
    foreach ($escucha in $escuchas) {
        if ($puerto -eq 8090 -and $escucha.LocalAddress -eq '0.0.0.0') { continue }
        $proceso = Get-Process -Id $escucha.OwningProcess -ErrorAction SilentlyContinue
        $programa = if ($proceso) { $proceso.ProcessName } else { 'desconocido' }
        if ($deDocker -notcontains $programa) {
            Falla ("El puerto $puerto lo esta usando otro programa ($programa)." +
                "`nCierrelo (o reinicie la PC) y vuelva a abrir instalar.cmd.")
        }
    }
}
Write-Host "Libres: 8090 (la app), $puertoKeycloak (el acceso) y $puertoApi (la API)."

# ----------------------------------------------------------
Paso 4 'Construir y levantar el sistema'
Write-Host 'Esto muestra mucho texto y puede tardar. No cierres esta ventana.'
& docker @Compose up -d --build
if ($LASTEXITCODE -ne 0) {
    $estado = cmd /c "docker inspect -f {{.State.ExitCode}} maxpizzapp-auth-config 2>nul"
    if ($estado -and $estado -ne '0') {
        Write-Host ''
        Write-Host 'Lo ultimo que dijo la configuracion del acceso (Keycloak):'
        & docker logs --tail 15 maxpizzapp-auth-config
    }
    Falla ('Docker no pudo levantar el sistema (el detalle esta arriba).' +
        "`nSi dice que falta memoria o espacio en disco, revise los requisitos del manual (B.1).")
}

# ----------------------------------------------------------
Paso 5 'Esperar a que responda'
$listo = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $salud = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "$Direccion/api/v1/salud"
        $app = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "$Direccion/"
        if ($salud.StatusCode -eq 200 -and $app.StatusCode -eq 200) { $listo = $true; break }
    } catch { }
    Start-Sleep -Seconds 3
}
if (-not $listo) {
    & docker @Compose ps
    Falla "El sistema arranco pero no responde en $Direccion despues de 3 minutos."
}
Write-Host 'La API responde (salud 200) y la app carga.'

# ----------------------------------------------------------
Paso 6 'Listo'
Write-Host ''
Write-Host '==========================================================' -ForegroundColor Green
Write-Host ' Max Pizzapp esta funcionando en esta PC' -ForegroundColor Green
Write-Host '==========================================================' -ForegroundColor Green
Write-Host " Direccion:  $Direccion"
Write-Host ' Recepcion:  recepcion.demo'
Write-Host ' Cocina:     cocina.demo'
Write-Host ''
Write-Host ' Para ver las dos pantallas a la vez, abra cocina en otra ventana'
Write-Host ' del navegador en modo InPrivate o incognito.'
Write-Host ' Para detenerlo: Docker Desktop > Containers > maxpizzapp > Stop.'
Write-Host ' Para volver a abrirlo: instalar.cmd otra vez.'
Write-Host ''
Write-Host " Contrasena de las dos cuentas de prueba: $claveDemo"
Write-Host ''
Start-Process $Direccion
exit 0
