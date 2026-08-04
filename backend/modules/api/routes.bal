// =============================================================================
// service.bal — Main HTTP service: all API resources for /api/v1
// API versioning via URL prefix, response standardization throughout
// =============================================================================

import trainlk/backend.models;
import trainlk/backend.db;
import trainlk/backend.config;
import trainlk/backend.controllers;
import trainlk/backend.utils;
import ballerina/http;
import ballerina/time;
import ballerina/log;
import ballerina/task;
import ballerina/cache;

// ── Cache instances (Dependency Injection #19: injected via function params) ─
final cache:Cache stationCache = new ({
    capacity: 100,
    evictionFactor: 0.2,
    defaultMaxAge: 3600,    // 1 hour — stations rarely change
    cleanupInterval: 600
});

final cache:Cache availabilityCache = new ({
    capacity: 500,
    evictionFactor: 0.25,
    defaultMaxAge: 10,      // 10 seconds — acceptable staleness for availability
    cleanupInterval: 30
});

// ── Listener with interceptor pipeline ───────────────────────────────────────
listener http:Listener httpListener = new (9090, {
    httpVersion: http:HTTP_1_1
});

// ── Background: expire held bookings every 2 minutes ─────────────────────────
function init() returns error? {
    _ = check task:scheduleJobRecurByFrequency(new ExpiryJob(), 120);
    log:printInfo("Train Booking API starting on port 9090");
    log:printInfo("Environment: " + config:appEnv);
}

class ExpiryJob {
    *task:Job;
    public isolated function execute() {
        error? err = db:dbExpireHeldBookings();
        if err !is () {
            log:printWarn("Booking expiry job failed", 'error = err);
        }
    }
}

// =============================================================================
// HEALTH CHECK — /health
// =============================================================================
service /health on httpListener {
    resource function get .() returns json|error {

        int|error dbLatency = db:dbPingCheck();

        string dbStatus = dbLatency is int ? "up" : "down";
        int?   dbMs     = dbLatency is int ? dbLatency : ();

        string overall = dbStatus == "up" ? "healthy" : "degraded";
        int statusCode = overall == "healthy" ? 200 : 503;

        json body = {
            "status":    overall,
            "version":   "1.0.0",
            "timestamp": time:utcToString(time:utcNow()),
            "checks": {
                "database": {"status": dbStatus, "latencyMs": dbMs},
                "cache":    {"status": "up"}
            }
        };

        http:Response resp = new;
        resp.statusCode = statusCode;
        resp.setJsonPayload(body);
        return body;
    }
}

// =============================================================================
// API v1 — /api/v1
// =============================================================================
@http:ServiceConfig {
    cors: {
        allowOrigins: [config:corsAllowedOrigins],
        allowCredentials: true,
        allowHeaders: ["Authorization", "Content-Type", "X-Request-ID"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    }
}
service http:InterceptableService /api/v1 on httpListener {

    public function createInterceptors() returns [utils:RateLimitInterceptor, utils:AuthInterceptor, utils:SecurityHeadersInterceptor, utils:ErrorInterceptor] {
        return [
            new utils:RateLimitInterceptor(),
            new utils:AuthInterceptor(),
            new utils:SecurityHeadersInterceptor(),
            new utils:ErrorInterceptor()
        ];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUTH ENDPOINTS
    // ═══════════════════════════════════════════════════════════════════════

    // POST /api/v1/auth/register
    resource function post auth/register(http:RequestContext ctx, http:Request req,
            @http:Payload models:RegisterRequest body) returns json|error {
        models:UserProfile profile = check controllers:registerUser(body);
        http:Response resp = new;
        resp.statusCode = 201;
        return utils:okResponse(profile.toJson());
    }

    // POST /api/v1/auth/login
    resource function post auth/login(http:RequestContext ctx, http:Request req,
            @http:Payload models:LoginRequest body) returns json|error {
        models:TokenPair tokens = check controllers:loginUser(body, utils:clientIp(req), utils:clientUa(req));
        return utils:okResponse(tokens.toJson());
    }

    // POST /api/v1/auth/refresh
    resource function post auth/refresh(http:RequestContext ctx, http:Request req,
            @http:Payload models:RefreshRequest body) returns json|error {
        models:TokenPair tokens = check controllers:refreshTokens(body.refreshToken, utils:clientIp(req), utils:clientUa(req));
        return utils:okResponse(tokens.toJson());
    }

    // POST /api/v1/auth/logout
    resource function post auth/logout(http:RequestContext ctx, http:Request req,
            @http:Payload models:RefreshRequest body) returns json|error {
        string userId = utils:ctxUserId(ctx);
        check controllers:logoutUser(body.refreshToken, userId);
        return utils:okResponse("Logged out successfully");
    }

    // GET /api/v1/auth/me
    resource function get auth/me(http:RequestContext ctx) returns json|error {
        string userId = utils:ctxUserId(ctx);
        if userId == "" {
            return error models:AuthError("Not authenticated");
        }
        models:UserRow user = check db:dbGetUserById(userId);
        models:UserProfile profile = {
            id:         user.id,
            email:      user.email,
            fullName:   user.fullName,
            phone:      user.phone,
            role:       user.role,
            mfaEnabled: user.mfaEnabled,
            createdAt:  time:utcToString(time:utcNow())
        };
        return utils:okResponse(profile.toJson());
    }

    // POST /api/v1/auth/mfa/setup
    resource function post auth/mfa/setup(http:RequestContext ctx) returns json|error {
        string userId = utils:ctxUserId(ctx);
        if userId == "" {
            return error models:AuthError("Not authenticated");
        }
        models:MfaSetupResponse setup = check controllers:setupMfa(userId);
        return utils:okResponse(setup.toJson());
    }

    // POST /api/v1/auth/mfa/verify
    resource function post auth/mfa/verify(http:RequestContext ctx,
            @http:Payload models:MfaVerifyRequest body) returns json|error {
        string userId = utils:ctxUserId(ctx);
        if userId == "" {
            return error models:AuthError("Not authenticated");
        }
        check controllers:verifyAndEnableMfa(userId, body.totpCode);
        return utils:okResponse("MFA enabled successfully");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATIONS
    // ═══════════════════════════════════════════════════════════════════════

    // GET /api/v1/stations?page=1&limit=50
    resource function get stations(http:RequestContext ctx,
            int page = 1, int 'limit = 50) returns json|error {
        // Cache check
        string cacheKey = string `stations:${page}:${'limit}`;
        any|cache:Error cached = stationCache.get(cacheKey);
        if cached is json {
            return cached;
        }

        models:StationRow[] stations = check db:dbGetStations(page, 'limit);
        int total = check db:dbCountStations();
        models:PaginationMeta pMeta = utils:paginationMeta(page, 'limit, total);

        json response = utils:okResponse(stations.toJson(), pMeta);
        cache:Error? putErr = stationCache.put(cacheKey, response);
        if putErr !is () {
            log:printWarn("Station cache put failed", 'error = putErr);
        }
        return response;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRAINS
    // ═══════════════════════════════════════════════════════════════════════

    // GET /api/v1/trains
    resource function get trains() returns json|error {
        models:TrainRow[] trains = check db:dbGetTrains();
        return utils:okResponse(trains.toJson());
    }

    // GET /api/v1/trains/{trainId}/coaches
    resource function get trains/[string trainId]/coaches() returns json|error {
        models:CoachRow[] coaches = check db:dbGetCoachesByTrain(trainId);
        return utils:okResponse(coaches.toJson());
    }

    // GET /api/v1/trains/{trainId}/seats/availability?from=...&to=...&date=...
    resource function get trains/[string trainId]/seats/availability(
            http:Request req,
            string 'from, string to, string date) returns json|error {

        // Cache check
        string cacheKey = string `avail:${trainId}:${'from}:${to}:${date}`;
        any|cache:Error cached = availabilityCache.get(cacheKey);
        if cached is json {
            return cached;
        }

        models:SeatAvailability[] seats = check db:dbGetSeatAvailability(trainId, 'from, to, date);
        json response = utils:okResponse(seats.toJson());
        check availabilityCache.put(cacheKey, response);
        return response;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FARE ESTIMATE
    // ═══════════════════════════════════════════════════════════════════════

    // GET /api/v1/fare/estimate?from=...&to=...&coachClass=...&date=...
    resource function get fare/estimate(
            string 'from, string to, string coachClass, string date) returns json|error {
        models:FareEstimateRequest req = {
            fromStationId: 'from,
            toStationId:   to,
            coachClass:    coachClass,
            travelDate:    date
        };
        models:FareBreakdown fare = check controllers:estimateFare(req);
        return utils:okResponse(fare.toJson());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BOOKINGS
    // ═══════════════════════════════════════════════════════════════════════

    // POST /api/v1/bookings
    resource function post bookings(http:RequestContext ctx, http:Request req,
            @http:Payload models:CreateBookingRequest body) returns json|http:Response|error {
        string userId = utils:ctxUserId(ctx);
        models:BookingRow booking = check controllers:createBooking(userId, body, utils:clientIp(req), utils:clientUa(req));
        http:Response resp = new;
        resp.statusCode = 201;
        resp.setJsonPayload(utils:okResponse(booking.toJson()));
        return resp;
    }

    // GET /api/v1/bookings — list current user's bookings
    resource function get bookings(http:RequestContext ctx, int page = 1, int 'limit = 20)
            returns json|error {
        string userId = utils:ctxUserId(ctx);
        if userId == "" {
            return error models:AuthError("Not authenticated");
        }
        models:BookingRow[] bookings = check db:dbGetUserBookings(userId, page, 'limit);
        int total = check db:dbCountUserBookings(userId);
        return utils:okResponse(bookings.toJson(), utils:paginationMeta(page, 'limit, total));
    }

    // GET /api/v1/bookings/{id}
    resource function get bookings/[string id](http:RequestContext ctx) returns json|error {
        string userId = utils:ctxUserId(ctx);
        string role   = utils:ctxRole(ctx);
        models:BookingRow booking = check db:dbGetBookingById(id);
        // Passengers can only view their own bookings
        if role == "PASSENGER" && booking.userId != userId {
            return error models:AuthError("Not authorized to view this booking");
        }
        return utils:okResponse(booking.toJson());
    }

    // GET /api/v1/bookings/ref/{referenceCode}
    resource function get bookings/ref/[string referenceCode]() returns json|error {
        models:BookingRow booking = check db:dbGetBookingByReference(referenceCode);
        return utils:okResponse(booking.toJson());
    }

    // POST /api/v1/bookings/{id}/confirm
    resource function post bookings/[string id]/confirm(http:RequestContext ctx)
            returns json|error {
        string userId = utils:ctxUserId(ctx);
        check controllers:confirmBooking(id, userId);
        return utils:okResponse("Booking confirmed");
    }

    // DELETE /api/v1/bookings/{id}
    resource function delete bookings/[string id](http:RequestContext ctx, http:Request req)
            returns json|error {
        string userId = utils:ctxUserId(ctx);
        string role   = utils:ctxRole(ctx);
        check controllers:cancelBooking(id, userId, role);
        return utils:okResponse("Booking cancelled");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WAITLIST
    // ═══════════════════════════════════════════════════════════════════════

    // POST /api/v1/waitlist
    resource function post waitlist(http:RequestContext ctx, http:Request req,
            @http:Payload models:CreateWaitlistRequest body) returns json|http:Response|error {
        string userId = utils:ctxUserId(ctx);
        models:WaitlistEntry entry = check db:dbCreateWaitlistEntry(userId, body);
        http:Response resp = new;
        resp.statusCode = 201;
        resp.setJsonPayload(utils:okResponse(entry.toJson()));
        return resp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN ENDPOINTS (require ADMIN or SUPERADMIN role)
    // ═══════════════════════════════════════════════════════════════════════

    // GET /api/v1/admin/occupancy?date=YYYY-MM-DD
    resource function get admin/occupancy(http:RequestContext ctx, string date)
            returns json|error {
        models:AuthError? roleCheck = utils:requireRole(ctx, ["ADMIN", "SUPERADMIN"]);
        if roleCheck !is () {
            return roleCheck;
        }
        models:OccupancyRecord[] occ = check db:dbGetOccupancy(date);
        return utils:okResponse(occ.toJson());
    }

    // GET /api/v1/admin/revenue?from=YYYY-MM-DD&to=YYYY-MM-DD&page=1&limit=20
    resource function get admin/revenue(http:RequestContext ctx,
            string 'from, string to, int page = 1, int 'limit = 20)
            returns json|error {
        models:AuthError? roleCheck = utils:requireRole(ctx, ["ADMIN", "SUPERADMIN"]);
        if roleCheck !is () {
            return roleCheck;
        }
        models:RevenueRecord[] revenue = check db:dbGetRevenue('from, to, page, 'limit);
        return utils:okResponse(revenue.toJson());
    }

    // GET /api/v1/admin/audit?entityType=BOOKING&entityId=...&page=1&limit=50
    resource function get admin/audit(http:RequestContext ctx,
            string? entityType = (), string? entityId = (),
            int page = 1, int 'limit = 50)
            returns json|error {
        models:AuthError? roleCheck = utils:requireRole(ctx, ["ADMIN", "SUPERADMIN"]);
        if roleCheck !is () {
            return roleCheck;
        }
        models:AuditLogRow[] logs = check db:dbGetAuditLogs(entityType, entityId, page, 'limit);
        return utils:okResponse(logs.toJson());
    }

    // GET /api/v1/docs — OpenAPI spec (redirect to Swagger UI hosted separately)
    resource function get docs() returns http:Response {
        http:Response resp = new;
        resp.statusCode = 200;
        resp.setJsonPayload({
            "info": "OpenAPI 3.1 spec available at GET /api/v1/openapi.json",
            "ui":   "Deploy swagger-ui pointing to /api/v1/openapi.json"
        });
        return resp;
    }
}
