# Max Pizzapp

Sistema de **gestión de pedidos para un restaurante pequeño**. La recepción toma el
pedido, lo envía a cocina, y el estado de preparación se sincroniza **en tiempo real**
entre ambas pantallas; cuando cocina marca "listo", recepción lo entrega.

Trabajo Final del **Módulo 4 — Integración y Despliegue de Soluciones** (Diplomado en
Desarrollo Web y Aplicaciones Móviles, UAJMS, gestión 2026).

## Alcance

Un flujo acotado y **desplegable**, priorizando profundidad sobre cantidad de módulos:

- **Recepción** crea el pedido a partir de la carta y lo envía a cocina.
- **Cocina** (tablet/PC) ve los pedidos entrantes en vivo y cambia su estado.
- Cuando el pedido está **listo**, recepción recibe el aviso y lo entrega.

## Roles

| Rol | Qué hace |
|---|---|
| **Recepción** | Crea pedidos, ve estados en vivo, entrega |
| **Cocina** | Ve pedidos entrantes en vivo, marca "listo" |
| **Administrador** | Gestiona la carta y los usuarios |

## Stack

- **Backend:** Node.js + Express (API REST) + **Socket.IO** (tiempo real)
- **Base de datos:** PostgreSQL
- **Identidad y roles:** Keycloak (OIDC)
- **Frontend:** Flutter (web)
- **Infraestructura:** Docker Compose · Caddy (HTTPS)

## Metodología

Desarrollo con **Kanban**: flujo continuo de trabajo (tablero, límite de trabajo en
curso y entregas incrementales). No se usan sprints.

## Estructura del repositorio

```
codigo/
├── backend/      API Node/Express + Socket.IO
├── frontend/     App Flutter
├── docker/       Compose, Postgres (init SQL), Keycloak (realm), Caddy
└── docs/         Documentación técnica (BRIEF de desarrollo)
```

## Puesta en marcha (local)

> En construcción — se completa en el Incremento 1 (cimientos: Docker + login).
> Las instrucciones del despliegue público (VM + HTTPS) se documentarán aquí en el
> Incremento 2.

## Variables de entorno

Copiar `.env.example` como `.env` y completar los valores. El `.env` **no** se versiona.
