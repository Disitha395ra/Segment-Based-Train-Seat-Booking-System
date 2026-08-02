# =============================================================================
# Dockerfile — React Frontend
# Stage 1: Build (Node.js)
# Stage 2: Serve (nginx)
# =============================================================================

FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --silent

COPY . .

ARG VITE_API_URL=http://backend:9090
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build

# ── Runtime: nginx ────────────────────────────────────────────────────────────
FROM nginx:1.27-alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our SPA nginx config
COPY nginx.conf /etc/nginx/conf.d/

# Copy built assets
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost/health-check || exit 1

CMD ["nginx", "-g", "daemon off;"]
