// =============================================================================
// interceptors.bal — All HTTP interceptors:
//   1. SecurityHeadersInterceptor  — security headers on every response
//   2. RateLimitInterceptor        — sliding window per-IP rate limiting
//   3. AuthInterceptor             — JWT validation + role injection
//   4. ErrorInterceptor            — centralized error → standard response
// =============================================================================

import ballerina/http;
import ballerina/jwt;
import ballerina/time;
import ballerina/uuid;
import ballerina/log;
import ballerina/regex;

// ═════════════════════════════════════════════════════════════════════════════
// 1. SECURITY HEADERS INTERCEPTOR (Response)
// ═════════════════════════════════════════════════════════════════════════════
public isolated service class SecurityHeadersInterceptor {
    *http:ResponseInterceptor;

    remote isolated function interceptResponse(
            http:RequestContext ctx, http:Response res) returns http:NextService|error? {
        res.setHeader("Access-Control-Allow-Origin",  corsAllowedOrigins);
        res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Request-ID");
        res.setHeader("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload");
        res.setHeader("Content-Security-Policy",   "default-src 'none'");
        res.setHeader("X-Content-Type-Options",    "nosniff");
        res.setHeader("X-Frame-Options",           "DENY");
        res.setHeader("X-XSS-Protection",          "1; mode=block");
        res.setHeader("Referrer-Policy",           "strict-origin-when-cross-origin");
        res.setHeader("Permissions-Policy",        "geolocation=(), microphone=(), camera=()");
        res.setHeader("API-Version",               "v1");
        return ctx.next();
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. RATE LIMIT INTERCEPTOR (Request)
// ═════════════════════════════════════════════════════════════════════════════
public isolated service class RateLimitInterceptor {
    *http:RequestInterceptor;

    resource isolated function 'default [string... path](
            http:RequestContext ctx, http:Request req)
            returns http:NextService|error? {
        string|http:HeaderNotFoundError fwdHeader = req.getHeader("X-Forwarded-For");
        string ip = fwdHeader is string ? fwdHeader : "unknown";
        // Strip port if present
        if ip.includes(",") {
            ip = regex:split(ip, ",")[0].trim();
        }

        // Determine endpoint group from path
        string pathStr = "/" + string:'join("/", ...path);
        string group;
        int maxReqs;
        if pathStr.startsWith("/auth") {
            group = RATE_LIMIT_GROUP_AUTH;
            maxReqs = rateLimitAuth;
        } else if pathStr.startsWith("/bookings") || pathStr == "/bookings" {
            group = RATE_LIMIT_GROUP_BOOKING;
            maxReqs = rateLimitBooking;
        } else {
            group = RATE_LIMIT_GROUP_GENERAL;
            maxReqs = rateLimitGeneral;
        }

        boolean|DatabaseError allowed = dbCheckAndIncrementRateLimit(ip, group, 60, maxReqs);
        if allowed is DatabaseError {
            log:printWarn("Rate limit DB check failed, allowing request", 'error = allowed);
            return ctx.next();
        }
        if !allowed {
            return error RateLimitError("Rate limit exceeded for " + group + " endpoint group");
        }

        // Inject rate limit headers
        ctx.set("rl-limit", maxReqs);
        ctx.set("rl-group", group);
        return ctx.next();
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. AUTH INTERCEPTOR — validates JWT and injects user context
// ═════════════════════════════════════════════════════════════════════════════
public isolated service class AuthInterceptor {
    *http:RequestInterceptor;

    resource isolated function 'default [string... path](
            http:RequestContext ctx, http:Request req)
            returns http:NextService|error? {
        // Skip auth for public routes
        string pathStr = "/" + string:'join("/", ...path);
        if isPublicRoute(pathStr, req.method) {
            return ctx.next();
        }

        string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
        if authHeader is http:HeaderNotFoundError || !authHeader.startsWith("Bearer ") {
            return error AuthError("Authorization header missing or malformed");
        }

        string token = authHeader.substring(7);
        jwt:Payload|AuthError payload = validateAccessToken(token);
        if payload is AuthError {
            return payload;
        }

        // Inject claims into context
        string? userId = extractClaim(payload, JWT_CLAIM_USER_ID);
        string? role   = extractClaim(payload, JWT_CLAIM_ROLE);
        ctx.set("userId", userId ?: "");
        ctx.set("role",   role   ?: "PASSENGER");

        return ctx.next();
    }
}

isolated function isPublicRoute(string path, string method) returns boolean {
    if method == "OPTIONS" {
        return true;
    }
    // GET stations, trains, availability — no auth required
    if method == "GET" && (
        path.startsWith("/stations") ||
        path.startsWith("/trains")   ||
        path.startsWith("/fare")     ||
        path.startsWith("/docs")
    ) {
        return true;
    }
    // Auth endpoints are public
    if path.startsWith("/auth/login")    ||
       path.startsWith("/auth/register") ||
       path.startsWith("/auth/refresh") {
        return true;
    }
    return false;
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. ERROR INTERCEPTOR — maps all errors to standard response envelope
// ═════════════════════════════════════════════════════════════════════════════
public isolated service class ErrorInterceptor {
    *http:ResponseErrorInterceptor;

    remote isolated function interceptResponseError(
            error err, http:RequestContext ctx,
            http:Request req, http:Response res) returns http:Response|error {

        string requestId = uuid:createType4AsString();
        string timestamp = time:utcToString(time:utcNow());

        int statusCode;
        string errorCode;
        string message;

        if err is ValidationError {
            statusCode = 422;
            errorCode  = "VALIDATION_ERROR";
            message    = err.message();
        } else if err is ConflictError {
            statusCode = 409;
            errorCode  = "SEAT_CONFLICT";
            message    = err.message();
        } else if err is NotFoundError {
            statusCode = 404;
            errorCode  = "NOT_FOUND";
            message    = err.message();
        } else if err is AuthError {
            statusCode = 401;
            errorCode  = "UNAUTHORIZED";
            message    = err.message();
        } else if err is RateLimitError {
            statusCode = 429;
            errorCode  = "RATE_LIMIT_EXCEEDED";
            message    = "Too many requests. Please slow down.";
        } else if err is MfaRequiredError {
            statusCode = 403;
            errorCode  = "MFA_REQUIRED";
            message    = "Multi-factor authentication required";
        } else if err is DatabaseError {
            statusCode = 500;
            errorCode  = "DATABASE_ERROR";
            // Never expose internal DB errors to clients
            message    = appEnv == "development" ? err.message() : "Internal server error";
        } else {
            statusCode = 500;
            errorCode  = "INTERNAL_ERROR";
            message    = appEnv == "development" ? err.message() : "Internal server error";
        }

        log:printError("Request error", statusCode = statusCode,
                       errorCode = errorCode, path = req.rawPath,
                       method = req.method, requestId = requestId,
                       'error = err);

        json body = {
            "success": false,
            "data": null,
            "error": {
                "code":    errorCode,
                "message": message,
                "details": null
            },
            "meta": {
                "requestId":  requestId,
                "apiVersion": "v1",
                "timestamp":  timestamp
            }
        };

        http:Response response = new;
        response.statusCode = statusCode;
        response.setJsonPayload(body);
        response.setHeader("Content-Type", "application/json");

        if statusCode == 429 {
            response.setHeader("Retry-After", "60");
        }

        return response;
    }
}

// ── Helper: build standard success response ───────────────────────────────────
public isolated function okResponse(json data, PaginationMeta? pagination = ()) returns json {
    return {
        "success": true,
        "data": data,
        "error": null,
        "meta": {
            "requestId":  uuid:createType4AsString(),
            "apiVersion": "v1",
            "timestamp":  time:utcToString(time:utcNow()),
            "pagination": pagination
        }
    };
}

public isolated function paginationMeta(int page, int 'limit, int total) returns PaginationMeta {
    int totalPages = total == 0 ? 0 : (<int>(total / 'limit)) + (total % 'limit == 0 ? 0 : 1);
    return {page: page, 'limit: 'limit, total: total, totalPages: totalPages};
}

// ── Extract context values set by AuthInterceptor ─────────────────────────────
public isolated function ctxUserId(http:RequestContext ctx) returns string =>
    (ctx.get("userId") is string) ? <string>ctx.get("userId") : "";

public isolated function ctxRole(http:RequestContext ctx) returns string =>
    (ctx.get("role") is string) ? <string>ctx.get("role") : "PASSENGER";

public isolated function requireRole(http:RequestContext ctx, string[] allowedRoles)
        returns AuthError? {
    string role = ctxRole(ctx);
    boolean found = false;
    foreach string r in allowedRoles {
        if r == role {
            found = true;
            break;
        }
    }
    if !found {
        return error AuthError("Insufficient permissions. Required role: " + allowedRoles.toString());
    }
    return ();
}

// ── Extract client IP ─────────────────────────────────────────────────────────
public isolated function clientIp(http:Request req) returns string? {
    string|http:HeaderNotFoundError fwd = req.getHeader("X-Forwarded-For");
    if fwd is string {
        return regex:split(fwd, ",")[0].trim();
    }
    return ();
}

public isolated function clientUa(http:Request req) returns string? {
    string|http:HeaderNotFoundError ua = req.getHeader("User-Agent");
    return ua is string ? ua : ();
}
