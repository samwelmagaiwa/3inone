# ---------------------------------------------------------------------------
# Stage 1: build the Angular app into plain static files
# ---------------------------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app

# Dependencies first, so a code change does not reinstall them
COPY package.json package-lock.json .npmrc ./
RUN npm ci --no-audit --no-fund

COPY . .
# Where the app lives in the address: "/" on its own port, "/app/" when it shares a domain with the API.
ARG BASE_HREF=/
RUN npx ng build --base-href "${BASE_HREF}"

# ---------------------------------------------------------------------------
# Stage 2: nginx serves the files and sends /api to the backend
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine

# Where /api goes. Overridden at run time (docker run -e / docker compose), never baked into the build.
ENV API_UPSTREAM=http://host.docker.internal:8000
# The Host header sent with /api. The default means "the one the browser used"; for another site use its name.
ENV API_HOST=\$http_host

# The official image fills ${API_UPSTREAM} in this template and writes /etc/nginx/conf.d/default.conf at start-up.
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist/accountant-web/browser /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1/healthz || exit 1
