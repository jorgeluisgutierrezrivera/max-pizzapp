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
| 05 | La carta y la venta en recepción | La carta real y la venta como recorrido guiado, con la identidad del local | **Revisión 2 propuesta** — 23-sep (la v1 se aprobó; su pantalla no) |
| 06 | Pedidos y cola de cocina | Alta de pedidos, cola y cambios de estado por rol | Por hacer |
| 07 | Sincronización en tiempo real | Eventos de pedido propagados en vivo a las pantallas | Por hacer |
| 08 | Disponibilidad de productos y cancelación de pedidos | Marcar un producto agotado (RF-13) y cancelar antes de "listo" (RF-09) | Por hacer |
| 09 | Endurecimiento de seguridad | Cabeceras, límite de intentos y repaso de validaciones | Por hacer |
| 10 | Pruebas end-to-end y documentación técnica | Suite en verde y plan de pruebas documentado | Por hacer |
| 11 | Identidad visual del acceso | Tema de Keycloak con la estética de la app y del local (colores, tipografía, marca), solo con estilos | Por hacer — después del E2 |

> **Orden modificado el 22-sep.** La tarjeta 02 era *Identidad y roles con Keycloak* y el
> despliegue público estaba al final, en la 09. Se fundieron y se adelantaron: la dirección
> pública y la identidad se levantan **antes** que el backend y las pantallas. El motivo es
> que la entrega de la semana 2 exige el sistema accesible en una dirección pública, y que
> los problemas de puertos, certificados y proxy no aparecen en local: aparecen la primera
> vez que se despliega. Las tarjetas siguientes conservan su contenido y corren un número.

Las tarjetas 03 en adelante se detallan al jalarlas: el índice fija el orden, no el
contenido definitivo de cada plan.
