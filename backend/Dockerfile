# Imagen de la API. Node LTS fijado por version mayor, igual en desarrollo y en el servidor.
FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production

# Primero solo los manifiestos: si el codigo cambia pero las dependencias no, Docker
# reutiliza esta capa y el build tarda segundos. "npm ci" instala exactamente lo que dice
# package-lock.json, sin resolver versiones nuevas.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src

# El proceso no corre como root: si alguien lograra ejecutar codigo a traves de la API,
# no tendria privilegios de administrador dentro del contenedor.
USER node

EXPOSE 3000
CMD ["node", "src/index.js"]
