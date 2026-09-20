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
| **Recepción** | Crea pedidos, ve estados en vivo, cancela antes de "listo", entrega, marca productos agotados |
| **Cocina** | Ve pedidos entrantes en vivo, avanza el estado, marca "listo", marca productos agotados |

El sistema tiene **dos roles**. La administración de la carta y el historial quedan fuera
de alcance y se recogen como trabajo futuro.

## Stack

- **Backend:** Node.js + Express (API REST) + **Socket.IO** (tiempo real)
- **Base de datos:** PostgreSQL
- **Identidad y roles:** Keycloak (OIDC)
- **Frontend:** Flutter (web)
- **Infraestructura:** Docker Compose · Caddy (HTTPS)

### Versiones fijadas

Versiones tomadas del entorno de desarrollo real. Las imágenes se fijan por versión
(nunca `latest`) para que el entorno sea reproducible en desarrollo y en el servidor.

| Componente | Versión | Cómo se fija |
|---|---|---|
| Node.js | 24.15.0 (LTS) | imagen `node:24-alpine` |
| npm | 11.12.1 | incluido en la imagen de Node |
| Flutter | 3.44.8 (stable) | SDK local; se declara en `frontend/pubspec.yaml` |
| Dart | 3.12.2 | incluido en el SDK de Flutter |
| PostgreSQL | 17 | imagen `postgres:17-alpine` |
| Keycloak | 26.7 | imagen `quay.io/keycloak/keycloak:26.7` |
| Caddy | 2 | imagen `caddy:2-alpine` |
| Docker Engine | 29.7.2 | entorno de desarrollo |
| Docker Compose | v5.3.1 | entorno de desarrollo |

Las versiones de las librerías (Express, Socket.IO, `pg`, `jwks-rsa`, paquetes de Flutter)
quedan fijadas en `backend/package.json` y `frontend/pubspec.yaml` al crearse cada
componente.

## Metodología

Desarrollo con **Kanban**: flujo continuo de trabajo (tablero, límite de trabajo en
curso y entregas incrementales). No se usan sprints.

## Estructura del repositorio

```
codigo/
├── backend/      API Node/Express + Socket.IO
├── frontend/     App Flutter
├── docker/       Compose, Postgres (init SQL), Keycloak (realm), Caddy
└── docs/         Documentación técnica: BRIEF de desarrollo y planes de trabajo
```

## Puesta en marcha (local)

> En construcción — se completa en el Incremento 1 (cimientos: Docker + login).
> Las instrucciones del despliegue público (VM + HTTPS) se documentarán aquí en el
> Incremento 2.

## Variables de entorno

Copiar `.env.example` como `.env` y completar los valores. El `.env` **no** se versiona.
