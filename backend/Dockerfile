# =============================================================================
# Dockerfile — Ballerina Backend
# Stage 1: Build (Ballerina → JAR)
# Stage 2: Runtime (JRE only — no build tools, minimal attack surface)
# =============================================================================

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM ballerina/ballerina:2201.10.0 AS builder

WORKDIR /home/ballerina/app

# Copy project files
COPY Ballerina.toml Cloud.toml ./
COPY *.bal ./
COPY modules/ ./modules/

# Build the fat JAR
RUN bal build

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine

WORKDIR /home/ballerina

# Install curl for health check
RUN apk add --no-cache curl

# Copy compiled JAR from builder
COPY --from=builder /home/ballerina/app/target/bin/backend.jar .

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Non-root user for security
RUN addgroup -S trainapp && adduser -S trainapp -G trainapp
RUN chown -R trainapp:trainapp /home/ballerina
USER trainapp

EXPOSE 9090

HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=30s \
    CMD curl -sf http://localhost:9090/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
