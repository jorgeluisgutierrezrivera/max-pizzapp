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
| 01 | Esquema de datos y PostgreSQL en contenedor | Persistencia lista y verificada | **Aprobado** |
| 02 | Identidad y roles con Keycloak | Realm, cliente y roles recepción y cocina | Por hacer |
| 03 | API base y validación de token | Express con endpoint de salud y middleware de token | Por hacer |
| 04 | App Flutter y acceso por rol | Login end-to-end y navegación según rol | Por hacer |
| 05 | Carta y pantalla de recepción | Productos y toma de pedido en pantalla | Por hacer |
| 06 | Pedidos y cola de cocina | Alta de pedidos, cola y cambios de estado por rol | Por hacer |
| 07 | Sincronización en tiempo real | Eventos de pedido propagados en vivo a las pantallas | Por hacer |
| 08 | Disponibilidad de productos y cancelación de pedidos | Marcar un producto agotado (RF-13) y cancelar antes de "listo" (RF-09) | Por hacer |
| 09 | Despliegue público con HTTPS | Sistema accesible por URL pública | Por hacer |
| 10 | Endurecimiento de seguridad | Cabeceras, límite de intentos y repaso de validaciones | Por hacer |
| 11 | Pruebas end-to-end y documentación técnica | Suite en verde y plan de pruebas documentado | Por hacer |

Las tarjetas 02 en adelante se detallan al jalarlas: el índice fija el orden, no el
contenido definitivo de cada plan.
