# Planes de trabajo

Cada tarjeta de trabajo tiene aquí su **plan escrito y aprobado antes de codificar**. El
plan no es un resumen posterior: se redacta primero, se revisa, y solo entonces empieza la
implementación. Al cerrar la tarjeta, el mismo archivo guarda la **evidencia de las
pruebas** y los commits que la cerraron.

## El ciclo de una tarjeta

```
1. PLAN        → se redacta PLAN.md con objetivo, alcance, decisiones y criterios
2. APROBACIÓN  → se revisa y se aprueba (o se corrige y se vuelve a revisar)
3. CÓDIGO      → se implementa solo lo aprobado
4. PRUEBAS     → verificación end-to-end; la evidencia se anota en el PLAN.md
5. APROBACIÓN  → se revisa el resultado y las pruebas
6. SUBIDA      → commit y push del código de la tarjeta
```

Se trabaja **una tarjeta a la vez** (límite de trabajo en curso = 1): no se abre la
siguiente hasta cerrar la actual.

## Convenciones

- Una carpeta por tarjeta: `NN-nombre-de-la-funcionalidad/PLAN.md`, numerada por orden de
  entrada al tablero y nombrada por la funcionalidad que entrega.
- Estados del plan: **Propuesto → Aprobado → En curso → En pruebas → Hecho**.
- Si un plan se declina, la corrección se anota en el propio archivo (sección
  *Revisiones*): queda registro de que la revisión ocurrió.
- El plan es de la **tarjeta**, no del proyecto: cabe en una lectura y agrupa los dos o
  tres commits que la cierran.

## Índice

| # | Tarjeta | Entrega | Estado |
|---|---|---|---|
| 01 | Esquema de datos y PostgreSQL en contenedor | Persistencia lista y verificada | **Hecho** — 22-sep |
| 02 | URL pública con HTTPS, proxy e identidad | Dirección pública con certificado válido y Keycloak con sus dos roles | **Hecho** — 23-sep |
| 03 | API base: estado del servicio y validación de token | Express con la ruta de salud y el middleware que valida firma, emisor, vigencia, audiencia y rol | **Hecho** — 23-sep |
| 04 | App Flutter y acceso por rol | Login end-to-end y navegación según rol | **Hecho** — 23-sep |
| 05 | La carta y la venta en recepción | La carta real y la venta como recorrido guiado, con la identidad del local | **Hecho** — 24-sep |
| 06 | Pedidos y cola de cocina | El CRUD del pedido (alta con precio del servidor, estados por rol y cancelación con motivo), la cola de cocina y el aviso en vivo mínimo | **Cerrada** el 25-sep, en producción — revisada con la tutoría (D-36 a D-38) y con el autor al probarla (D-39, D-41) |
| 07 | El canal en vivo y la sesión | El aviso cuando se cae el canal, con *Recargar* (CA-03.2, RNF-05); el latido que lo detecta en menos de 10 s; la reconexión después de un corte o un rechazo; la sesión rechazada que vuelve al acceso; y ninguna conexión que dure más que su token. La carta al día en todas las pantallas pasa a la 08, con RF-13 | **Hecho** — 30-sep, en producción. La vuelta rápida del canal en Chrome (E-014) pasa al E4 |
| 08 | Disponibilidad de productos | Marcar un producto agotado o disponible, o una categoría entera, con el aviso en vivo a las dos pantallas (RF-13). Cada rol lo suyo (D-76): cocina, las pizzas y los extras (web y APK); recepción, las bebidas. La cancelación (RF-09) se adelantó a la 06 (D-33) | **Hecho** — 7-oct, en producción y probada por el autor en la PC y en el APK 0.4.0 |
| 09 | Endurecimiento de seguridad | Cabeceras y límite de peticiones en la API, Keycloak endurecido con un script versionado (direcciones exactas, Argon2 a la vista, cuentas nuevas sin rol, consola protegida), la CSP medida de la app y la evidencia del 2.7 | **Hecho** — 2-oct, en producción y probada por el autor |
| 10 | Pruebas con evidencia | Los reportes versionados de las suites y de las sondas, la integración continua, RNF-01 (30 propagaciones y k6), RNF-03, RNF-04 y RNF-05 medidos, y la tabla de casos de la que sale el 2.8 | **Hecho** — 2-oct: las 28 filas de la tabla con su evidencia y la integración continua en verde. La numeración de las secciones de la venta pasa al E4 |
| 11 | Identidad visual del acceso | Tema de Keycloak con la estética de la app y del local (colores, tipografía, marca), solo con estilos | Por hacer — después del E2 |
| 12 | App Android para cocina | El mismo código de Flutter compilado como APK para el rol cocina (D-43): inicio de sesión en Android, sonido **desde el arranque, sin esperar un toque** (lo que la web no puede, visto en la prueba de la 07), pantalla encendida, firma y descarga. Recepción sigue en la web | **Hecho** — 1-oct: publicado en el Release `apk-cocina-0.1.0` y probado por el autor en su teléfono contra producción |
| 13 | Instalación local en un solo paso | El sistema completo en una PC que solo tiene Docker Desktop, con un paso (`instalar.cmd`): la app compilada en Docker, Keycloak configurado en el arranque, el `.env` generado y la instalación probada en la integración continua. La prueba: otra persona sigue el manual de instalación (enunciado del E4) | **En curso** — aprobado el 4-oct; fases A a C probadas y en GitHub; ⛔ espera la prueba de la encargada (7-oct) |
| 14 | Las bebidas reales | Las bebidas que vende el local, con sus precios y genéricas: agua, jugo y soda, y la soda por tamaño (personal, 1 L, 1,5 L y 2 L). La marca y el sabor se preguntan al entregar y no se registran. Las tres ficticias toman su nombre real, y las bebidas van en el orden en que se piden | **Hecho** — 7-oct, en producción y probada por el autor en la PC y en el APK |

> **Orden modificado el 22-sep.** La tarjeta 02 era *Identidad y roles con Keycloak* y el
> despliegue público estaba al final, en la 09. Se fundieron y se adelantaron: la dirección
> pública y la identidad se levantan **antes** que el backend y las pantallas. El motivo es
> que la entrega de la semana 2 exige el sistema accesible en una dirección pública, y que
> los problemas de puertos, certificados y proxy no aparecen en local: aparecen la primera
> vez que se despliega. Las tarjetas siguientes conservan su contenido y corren un número.

Las tarjetas 03 en adelante se detallan al jalarlas: el índice fija el orden, no el
contenido definitivo de cada plan.
