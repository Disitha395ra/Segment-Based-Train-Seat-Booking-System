#!/bin/sh
# =============================================================================
# entrypoint.sh — Generate Config.toml from environment variables at runtime
# This keeps all secrets out of the Docker image layer.
# =============================================================================
set -e

CONFIG_FILE="/home/ballerina/Config.toml"

cat > "$CONFIG_FILE" << TOML
[trainlk.backend.config]
dbHost                 = "${POSTGRES_HOST:-db}"
dbPort                 = ${POSTGRES_PORT:-5432}
dbName                 = "${POSTGRES_DB:-trainbooking}"
dbUser                 = "${POSTGRES_USER:-trainuser}"
dbPassword             = "${POSTGRES_PASSWORD}"
jwtSecret              = "${JWT_SECRET}"
jwtAccessExpirySeconds = ${JWT_ACCESS_EXPIRY_SECONDS:-900}
jwtRefreshExpiryDays   = ${JWT_REFRESH_EXPIRY_DAYS:-7}
mfaEncryptionKey       = "${MFA_ENCRYPTION_KEY}"
fareBaseRatePerKm      = ${FARE_BASE_RATE_PER_KM:-2.50}
farePeakMultiplier     = ${FARE_PEAK_MULTIPLIER:-1.2}
rateLimitGeneral       = ${RATE_LIMIT_GENERAL:-100}
rateLimitBooking       = ${RATE_LIMIT_BOOKING:-20}
rateLimitAuth          = ${RATE_LIMIT_AUTH:-10}
corsAllowedOrigins     = "${CORS_ALLOWED_ORIGINS:-http://localhost:3000}"
appEnv                 = "${APP_ENV:-production}"
TOML

echo "Config.toml generated."

# Run the Ballerina service JAR
exec java -jar /home/ballerina/backend.jar
