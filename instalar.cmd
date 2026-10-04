@echo off
rem ==========================================================
rem Max Pizzapp - instalacion local en un solo paso (tarjeta 13)
rem
rem Doble clic. O desde una consola, en esta carpeta:
rem   instalar.cmd              instala, o vuelve a levantar lo instalado
rem   instalar.cmd desde-cero   borra los datos de esta instalacion y la rehace
rem
rem Solo necesita Docker Desktop abierto. Todo lo hace
rem scripts\instalar.ps1. "-ExecutionPolicy Bypass" vale solo para esta
rem ejecucion: no cambia ninguna configuracion de la PC.
rem ==========================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\instalar.ps1" %*
set "RESULTADO=%ERRORLEVEL%"
echo.
pause
exit /b %RESULTADO%
