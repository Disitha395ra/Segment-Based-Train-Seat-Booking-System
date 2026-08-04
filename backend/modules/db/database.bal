// =============================================================================
// db.bal — PostgreSQL client initialization and all database queries
// Dependency-injected via function parameters (DI pattern #19)
// =============================================================================

import trainlk/backend.models;
import trainlk/backend.config;
import ballerina/sql;
import ballerina/log;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

// ── Singleton DB client (initialized once, reused via DI) ───────────────────
public final postgresql:Client dbClient = check initDb();

public function initDb() returns postgresql:Client|error {
    postgresql:Options opts = {
        connectTimeout: 10,
        socketTimeout: 30
    };
    postgresql:Client dbPgClient = check new (
        host = config:dbHost,
        port = config:dbPort,
        database = config:dbName,
        username = config:dbUser,
        password = config:dbPassword,
        options = opts,
        connectionPool = {
            maxOpenConnections: 25,
            minIdleConnections: 5,
            maxConnectionLifeTime: 1800.0
        }
    );
    log:printInfo("Database connection pool initialized");
    return dbPgClient;
}

// ── Helper: build standard offset for pagination ─────────────────────────────
public isolated function calcOffset(int page, int 'limit) returns int =>
    ('limit * (page - 1));

// =============================================================================
// STATIONS
// =============================================================================
public isolated function dbGetStations(int page, int 'limit)
        returns models:StationRow[]|models:DatabaseError {
    int offset = calcOffset(page, 'limit);
    stream<models:StationRow, sql:Error?> resultStream = dbClient->query(
        `SELECT id::text, name, code, order_index AS "orderIndex", distance_km AS "distanceKm"
           FROM stations
          WHERE deleted_at IS NULL
          ORDER BY order_index
          LIMIT ${'limit} OFFSET ${offset}`
    );
    models:StationRow[]|error result = from models:StationRow row in resultStream select row;
    if result is error {
        log:printError("dbGetStations failed", 'error = result);
        return error models:DatabaseError("Failed to fetch stations", result);
    }
    return result;
}

public isolated function dbCountStations() returns int|models:DatabaseError {
    int|sql:Error result = dbClient->queryRow(
        `SELECT COUNT(*) FROM stations WHERE deleted_at IS NULL`
    );
    if result is sql:Error {
        return error models:DatabaseError("Failed to count stations", result);
    }
    return result;
}

public isolated function dbGetStationById(string id) returns models:StationRow|models:NotFoundError|models:DatabaseError {
    models:StationRow|sql:Error result = dbClient->queryRow(
        `SELECT id::text, name, code, order_index AS "orderIndex", distance_km AS "distanceKm"
           FROM stations
          WHERE id = ${id}::uuid AND deleted_at IS NULL`
    );
    if result is sql:NoRowsError {
        return error models:NotFoundError("Station not found: " + id);
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch station", result);
    }
    return result;
}

// =============================================================================
// TRAINS & COACHES
// =============================================================================
public isolated function dbGetTrains() returns models:TrainRow[]|models:DatabaseError {
    stream<models:TrainRow, sql:Error?> resultStream = dbClient->query(
        `SELECT id::text, name, train_number AS "trainNumber",
                departure_time::text AS "departureTime", is_active AS "isActive"
           FROM trains WHERE is_active = TRUE ORDER BY name`
    );
    models:TrainRow[]|error result = from models:TrainRow row in resultStream select row;
    if result is error {
        return error models:DatabaseError("Failed to fetch trains", result);
    }
    return result;
}

public isolated function dbGetCoachesByTrain(string trainId) returns models:CoachRow[]|models:DatabaseError {
    stream<models:CoachRow, sql:Error?> resultStream = dbClient->query(
        `SELECT id::text, train_id::text AS "trainId", coach_number AS "coachNumber",
                coach_class AS "coachClass", total_seats AS "totalSeats"
           FROM coaches
          WHERE train_id = ${trainId}::uuid AND deleted_at IS NULL
          ORDER BY coach_number`
    );
    models:CoachRow[]|error result = from models:CoachRow row in resultStream select row;
    if result is error {
        return error models:DatabaseError("Failed to fetch coaches", result);
    }
    return result;
}

// =============================================================================
// SEAT AVAILABILITY — core business query
// Returns all seats for a train + segment, with availability flag
// =============================================================================
public isolated function dbGetSeatAvailability(
        string trainId, string fromStationId, string toStationId, string travelDate)
        returns models:SeatAvailability[]|models:DatabaseError {
    stream<models:SeatAvailability, sql:Error?> resultStream = dbClient->query(
        `SELECT
             s.id::text,
             s.coach_id::text    AS "coachId",
             c.coach_number      AS "coachNumber",
             c.coach_class       AS "coachClass",
             s.seat_number       AS "seatNumber",
             NOT EXISTS (
                 SELECT 1 FROM seat_segment_bookings ssb
                  WHERE ssb.seat_id    = s.id
                    AND ssb.travel_date = ${travelDate}::date
                    AND ssb.status      IN ('HELD','CONFIRMED')
                    AND ssb.from_station_order < (SELECT order_index FROM stations WHERE id = ${toStationId}::uuid)
                    AND ssb.to_station_order   > (SELECT order_index FROM stations WHERE id = ${fromStationId}::uuid)
             ) AS "available",
             (
                 SELECT COUNT(*) FROM waitlist w
                  WHERE w.seat_id         = s.id
                    AND w.from_station_id = ${fromStationId}::uuid
                    AND w.to_station_id   = ${toStationId}::uuid
                    AND w.travel_date     = ${travelDate}::date
                    AND w.status          = 'WAITING'
                    AND w.deleted_at IS NULL
             )::int AS "waitlistCount"
         FROM seats s
         JOIN coaches c ON c.id = s.coach_id
         JOIN trains  t ON t.id = c.train_id
        WHERE t.id = ${trainId}::uuid
          AND c.coach_class != 'UNRESERVED'
          AND s.deleted_at  IS NULL
          AND c.deleted_at  IS NULL
        ORDER BY c.coach_number, s.seat_number`
    );
    models:SeatAvailability[]|error result = from models:SeatAvailability row in resultStream select row;
    if result is error {
        log:printError("dbGetSeatAvailability failed", 'error = result);
        return error models:DatabaseError("Failed to fetch seat availability", result);
    }
    return result;
}

// =============================================================================
// BOOKING — core transaction
// Uses SELECT FOR UPDATE to prevent concurrent double-booking
// =============================================================================
public isolated function dbCreateBooking(
        string userId, models:CreateBookingRequest req, string referenceCode,
        int fromOrder, int toOrder, decimal fare, json fareBreakdown)
        returns models:BookingRow|models:ConflictError|models:NotFoundError|models:DatabaseError|error {

    time:Utc now = time:utcNow();
    time:Utc heldUntil = time:utcAddSeconds(now, <decimal>(models:BOOKING_HOLD_MINUTES * 60));
    string heldUntilStr = time:utcToString(heldUntil);
    string fareBreakdownStr = fareBreakdown.toString();

    transaction {
        // Step 1: Sort seat IDs to prevent deadlocks when locking multiple rows
        string[] sortedSeatIds = req.seatIds.clone();
        string[] sorted = sortedSeatIds.sort();

        // Step 2: Lock and check overlap for ALL seats
        foreach string sId in sorted {
            // Lock the seat row to prevent concurrent modifications
            sql:ExecutionResult|sql:Error lockResult = dbClient->execute(
                `SELECT id FROM seats WHERE id = ${sId}::uuid AND deleted_at IS NULL FOR UPDATE`
            );
            if lockResult is sql:Error {
                fail error models:DatabaseError("Seat lock failed for seat: " + sId, lockResult);
            }

            // Check for overlapping confirmed/held bookings
            int|sql:Error overlapCount = dbClient->queryRow(
                `SELECT COUNT(*) FROM seat_segment_bookings
                  WHERE seat_id            = ${sId}::uuid
                    AND travel_date        = ${req.travelDate}::date
                    AND status             IN ('HELD','CONFIRMED')
                    AND from_station_order < ${toOrder}
                    AND to_station_order   > ${fromOrder}`
            );
            if overlapCount is sql:Error {
                fail error models:DatabaseError("Overlap check failed for seat: " + sId, overlapCount);
            }
            if overlapCount > 0 {
                fail error models:ConflictError("One or more seats already booked for this segment");
            }
        }

        // Step 3: Insert single booking record (seat_id removed from schema)
        sql:ExecutionResult|sql:Error bookingResult = dbClient->execute(
            `INSERT INTO bookings
               (reference_code, user_id, from_station_id, to_station_id,
                travel_date, fare_amount, fare_breakdown, status,
                passenger_name, passenger_email, passenger_phone, held_until)
             VALUES
               (${referenceCode},
                CASE WHEN ${userId} = '' THEN NULL ELSE ${userId}::uuid END,
                ${req.fromStationId}::uuid,
                ${req.toStationId}::uuid,
                ${req.travelDate}::date,
                ${fare},
                ${fareBreakdownStr}::jsonb,
                'HELD',
                ${req.passengerName},
                ${req.passengerEmail},
                ${req.passengerPhone},
                ${heldUntilStr}::timestamptz)`
        );
        if bookingResult is sql:Error {
            fail error models:DatabaseError("Booking insert failed", bookingResult);
        }

        // Step 4: Fetch the generated booking ID
        string|sql:Error newBookingId = dbClient->queryRow(
            `SELECT id::text FROM bookings WHERE reference_code = ${referenceCode}`
        );
        if newBookingId is sql:Error {
            fail error models:DatabaseError("Failed to fetch new booking id", newBookingId);
        }

        // Step 5: Insert seat segment booking for ALL seats
        foreach string sId in sorted {
            sql:ExecutionResult|sql:Error ssbResult = dbClient->execute(
                `INSERT INTO seat_segment_bookings
                   (booking_id, seat_id, from_station_order, to_station_order, travel_date, status)
                 VALUES
                   (${newBookingId}::uuid, ${sId}::uuid, ${fromOrder}, ${toOrder},
                    ${req.travelDate}::date, 'HELD')`
            );
            if ssbResult is sql:Error {
                fail error models:DatabaseError("Segment booking insert failed for seat: " + sId, ssbResult);
            }
        }

        check commit;
    } on fail error err {
        if err is models:ConflictError || err is models:DatabaseError {
            return err;
        }
        return error models:DatabaseError("Transaction failed", err);
    }

    // Return the created booking
    return dbGetBookingByReference(referenceCode);
}

public isolated function dbConfirmBooking(string bookingId) returns error? {
    transaction {
        _ = check dbClient->execute(
            `UPDATE bookings SET status = 'CONFIRMED', held_until = NULL
              WHERE id = ${bookingId}::uuid AND status = 'HELD'`
        );
        _ = check dbClient->execute(
            `UPDATE seat_segment_bookings SET status = 'CONFIRMED'
              WHERE booking_id = ${bookingId}::uuid AND status = 'HELD'`
        );
        check commit;
    }
}

public isolated function dbCancelBooking(string bookingId)
        returns models:NotFoundError|models:DatabaseError|error? {
    transaction {
        sql:ExecutionResult|sql:Error result = dbClient->execute(
            `UPDATE bookings
                SET status = 'CANCELLED', deleted_at = NOW()
              WHERE id = ${bookingId}::uuid
                AND status IN ('HELD','CONFIRMED')
                AND deleted_at IS NULL`
        );
        if result is sql:Error {
            fail error models:DatabaseError("Cancel booking failed", result);
        }
        if result.affectedRowCount == 0 {
            fail error models:NotFoundError("Booking not found or already cancelled");
        }
        _ = check dbClient->execute(
            `UPDATE seat_segment_bookings SET status = 'CANCELLED'
              WHERE booking_id = ${bookingId}::uuid`
        );
        check commit;
    } on fail error err {
        if err is models:NotFoundError || err is models:DatabaseError {
            return err;
        }
        return error models:DatabaseError("Cancel transaction failed", err);
    }
}

public isolated function dbGetBookingByReference(string referenceCode)
        returns models:BookingRow|models:NotFoundError|models:DatabaseError {
    models:BookingRow|sql:Error result = dbClient->queryRow(
        `SELECT id::text, reference_code AS "referenceCode",
                user_id::text AS "userId",
                from_station_id::text AS "fromStationId",
                to_station_id::text AS "toStationId",
                travel_date::text AS "travelDate",
                fare_amount AS "fareAmount",
                fare_breakdown::text AS "fareBreakdown",
                status, passenger_name AS "passengerName",
                passenger_email AS "passengerEmail",
                passenger_phone AS "passengerPhone",
                held_until::text AS "heldUntil",
                created_at::text AS "createdAt",
                updated_at::text AS "updatedAt"
           FROM bookings
          WHERE reference_code = ${referenceCode} AND deleted_at IS NULL`
    );
    if result is sql:NoRowsError {
        return error models:NotFoundError("Booking not found: " + referenceCode);
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch booking", result);
    }
    return result;
}

public isolated function dbGetBookingById(string bookingId)
        returns models:BookingRow|models:NotFoundError|models:DatabaseError {
    models:BookingRow|sql:Error result = dbClient->queryRow(
        `SELECT id::text, reference_code AS "referenceCode",
                user_id::text AS "userId",
                from_station_id::text AS "fromStationId",
                to_station_id::text AS "toStationId",
                travel_date::text AS "travelDate",
                fare_amount AS "fareAmount",
                fare_breakdown::text AS "fareBreakdown",
                status, passenger_name AS "passengerName",
                passenger_email AS "passengerEmail",
                passenger_phone AS "passengerPhone",
                held_until::text AS "heldUntil",
                created_at::text AS "createdAt",
                updated_at::text AS "updatedAt"
           FROM bookings
          WHERE id = ${bookingId}::uuid AND deleted_at IS NULL`
    );
    if result is sql:NoRowsError {
        return error models:NotFoundError("Booking not found: " + bookingId);
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch booking", result);
    }
    return result;
}

public isolated function dbGetBookingSeatIds(string bookingId) returns string[]|models:DatabaseError {
    stream<record {| string seat_id; |}, sql:Error?> resultStream = dbClient->query(
        `SELECT seat_id::text AS seat_id FROM seat_segment_bookings WHERE booking_id = ${bookingId}::uuid`
    );
    string[]|error seatIds = from var row in resultStream select row.seat_id;
    if seatIds is error {
        return error models:DatabaseError("Failed to fetch booking seats", seatIds);
    }
    return seatIds;
}

public isolated function dbGetUserBookings(string userId, int page, int 'limit)
        returns models:BookingRow[]|models:DatabaseError {
    int offset = calcOffset(page, 'limit);
    stream<models:BookingRow, sql:Error?> resultStream = dbClient->query(
        `SELECT id::text, reference_code AS "referenceCode",
                user_id::text AS "userId",
                from_station_id::text AS "fromStationId",
                to_station_id::text AS "toStationId",
                travel_date::text AS "travelDate",
                fare_amount AS "fareAmount",
                fare_breakdown::text AS "fareBreakdown",
                status, passenger_name AS "passengerName",
                passenger_email AS "passengerEmail",
                passenger_phone AS "passengerPhone",
                held_until::text AS "heldUntil",
                created_at::text AS "createdAt",
                updated_at::text AS "updatedAt"
           FROM bookings
          WHERE user_id = ${userId}::uuid AND deleted_at IS NULL
          ORDER BY created_at DESC
          LIMIT ${'limit} OFFSET ${offset}`
    );
    models:BookingRow[]|error result = from models:BookingRow row in resultStream select row;
    if result is error {
        return error models:DatabaseError("Failed to fetch user bookings", result);
    }
    return result;
}

public isolated function dbCountUserBookings(string userId) returns int|models:DatabaseError {
    int|sql:Error result = dbClient->queryRow(
        `SELECT COUNT(*) FROM bookings WHERE user_id = ${userId}::uuid AND deleted_at IS NULL`
    );
    if result is sql:Error {
        return error models:DatabaseError("Failed to count user bookings", result);
    }
    return result;
}

// =============================================================================
// USERS & AUTH
// =============================================================================
public isolated function dbGetUserByEmail(string email)
        returns models:UserRow|models:NotFoundError|models:DatabaseError {
    models:UserRow|sql:Error result = dbClient->queryRow(
        `SELECT id::text, email, password_hash AS "passwordHash",
                password_salt AS "passwordSalt", full_name AS "fullName",
                phone, role, mfa_enabled AS "mfaEnabled",
                mfa_secret_encrypted AS "mfaSecretEncrypted", is_active AS "isActive"
           FROM users
          WHERE email = ${email} AND deleted_at IS NULL`
    );
    if result is sql:NoRowsError {
        return error models:NotFoundError("User not found");
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch user", result);
    }
    return result;
}

public isolated function dbGetUserById(string userId)
        returns models:UserRow|models:NotFoundError|models:DatabaseError {
    models:UserRow|sql:Error result = dbClient->queryRow(
        `SELECT id::text, email, password_hash AS "passwordHash",
                password_salt AS "passwordSalt", full_name AS "fullName",
                phone, role, mfa_enabled AS "mfaEnabled",
                mfa_secret_encrypted AS "mfaSecretEncrypted", is_active AS "isActive"
           FROM users
          WHERE id = ${userId}::uuid AND deleted_at IS NULL`
    );
    if result is sql:NoRowsError {
        return error models:NotFoundError("User not found");
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch user", result);
    }
    return result;
}

public isolated function dbCreateUser(models:RegisterRequest req, string passwordHash, string salt)
        returns string|models:DatabaseError|models:DuplicateEmailError {
    sql:ExecutionResult|sql:Error result = dbClient->execute(
        `INSERT INTO users (email, password_hash, password_salt, full_name, phone)
         VALUES (${req.email}, ${passwordHash}, ${salt}, ${req.fullName}, ${req.phone})`
    );
    if result is sql:Error {
        string msg = result.message();
        if msg.includes("duplicate key value violates unique constraint") || msg.includes("uq_user_email") {
            return error models:DuplicateEmailError("User with this email already exists");
        }
        return error models:DatabaseError("Failed to create user", result);
    }
    string|sql:Error idResult = dbClient->queryRow(
        `SELECT id::text FROM users WHERE email = ${req.email}`
    );
    if idResult is sql:Error {
        return error models:DatabaseError("Failed to retrieve new user id", idResult);
    }
    return idResult;
}

public isolated function dbSaveRefreshToken(
        string userId, string tokenHash, string expiresAt, string? ip, string? ua)
        returns error? {
    _ = check dbClient->execute(
        `INSERT INTO refresh_tokens (user_id, token_hash, expires_at, ip_address, user_agent)
         VALUES (${userId}::uuid, ${tokenHash}, ${expiresAt}::timestamptz, ${ip}::inet, ${ua})`
    );
}

public isolated function dbGetRefreshToken(string tokenHash)
        returns record {|string userId; string expiresAt; string? revokedAt;|}|models:NotFoundError|models:DatabaseError {
    record {|string userId; string expiresAt; string? revokedAt;|}|sql:Error result =
        dbClient->queryRow(
            `SELECT user_id::text AS "userId", expires_at::text AS "expiresAt",
                    revoked_at::text AS "revokedAt"
               FROM refresh_tokens WHERE token_hash = ${tokenHash}`
        );
    if result is sql:NoRowsError {
        return error models:NotFoundError("Refresh token not found");
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch refresh token", result);
    }
    return result;
}

public isolated function dbRevokeRefreshToken(string tokenHash) returns error? {
    _ = check dbClient->execute(
        `UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = ${tokenHash}`
    );
}

public isolated function dbRevokeAllUserRefreshTokens(string userId) returns error? {
    _ = check dbClient->execute(
        `UPDATE refresh_tokens SET revoked_at = NOW()
          WHERE user_id = ${userId}::uuid AND revoked_at IS NULL`
    );
}

public isolated function dbEnableMfa(string userId, string encryptedSecret) returns error? {
    _ = check dbClient->execute(
        `UPDATE users SET mfa_enabled = TRUE, mfa_secret_encrypted = ${encryptedSecret}
          WHERE id = ${userId}::uuid`
    );
}

public isolated function dbSaveBackupCodes(string userId, string[] codeHashes) returns error? {
    foreach string codeHash in codeHashes {
        _ = check dbClient->execute(
            `INSERT INTO mfa_backup_codes (user_id, code_hash)
             VALUES (${userId}::uuid, ${codeHash})`
        );
    }
}

public isolated function dbUseBackupCode(string userId, string codeHash) returns boolean|models:DatabaseError {
    sql:ExecutionResult|sql:Error result = dbClient->execute(
        `UPDATE mfa_backup_codes SET used_at = NOW()
          WHERE user_id = ${userId}::uuid AND code_hash = ${codeHash} AND used_at IS NULL`
    );
    if result is sql:Error {
        return error models:DatabaseError("Failed to use backup code", result);
    }
    return result.affectedRowCount > 0;
}

// =============================================================================
// RATE LIMITING
// =============================================================================
public isolated function dbCheckAndIncrementRateLimit(
        string identifier, string endpointGroup, int windowSeconds, int maxRequests)
        returns boolean|models:DatabaseError {
    time:Utc now = time:utcNow();
    // Truncate to window boundary
    int windowStart = <int>(now[0] / windowSeconds) * windowSeconds;
    string windowStartStr = time:utcToString([windowStart, 0]);

    // Upsert rate limit window
    sql:ExecutionResult|sql:Error upsertResult = dbClient->execute(
        `INSERT INTO rate_limit_windows (identifier, endpoint_group, request_count, window_start)
         VALUES (${identifier}, ${endpointGroup}, 1, ${windowStartStr}::timestamptz)
         ON CONFLICT (identifier, endpoint_group, window_start)
         DO UPDATE SET request_count = rate_limit_windows.request_count + 1,
                       updated_at = NOW()
         RETURNING request_count`
    );
    if upsertResult is sql:Error {
        return error models:DatabaseError("Rate limit upsert failed", upsertResult);
    }

    int|sql:Error countResult = dbClient->queryRow(
        `SELECT request_count FROM rate_limit_windows
          WHERE identifier = ${identifier}
            AND endpoint_group = ${endpointGroup}
            AND window_start = ${windowStartStr}::timestamptz`
    );
    if countResult is sql:Error {
        return error models:DatabaseError("Rate limit query failed", countResult);
    }
    return countResult <= maxRequests;
}

// =============================================================================
// AUDIT LOG — append only
// =============================================================================
public isolated function dbInsertAuditLog(
        string? actorId, string actorType, string action,
        string? entityType, string? entityId,
        json? oldValue, json? newValue,
        string? ipAddress, string? userAgent,
        json metadata) returns error? {
    string? oldValueStr = oldValue is () ? () : oldValue.toString();
    string? newValueStr = newValue is () ? () : newValue.toString();
    string metadataStr = metadata.toString();
    _ = check dbClient->execute(
        `INSERT INTO audit_logs
           (actor_id, actor_type, action, entity_type, entity_id,
            old_value, new_value, ip_address, user_agent, metadata)
         VALUES
           (${actorId}, ${actorType}, ${action}, ${entityType},
            ${entityId}::uuid,
            ${oldValueStr}::jsonb, ${newValueStr}::jsonb,
            ${ipAddress}::inet, ${userAgent}, ${metadataStr}::jsonb)`
    );
}

public isolated function dbGetAuditLogs(string? entityType, string? entityId, int page, int 'limit)
        returns models:AuditLogRow[]|models:DatabaseError {
    int offset = calcOffset(page, 'limit);
    stream<models:AuditLogRow, sql:Error?> resultStream = dbClient->query(
        `SELECT id::text, actor_id AS "actorId", actor_type AS "actorType",
                action, entity_type AS "entityType", entity_id::text AS "entityId",
                old_value::text AS "oldValue", new_value::text AS "newValue",
                ip_address::text AS "ipAddress", created_at::text AS "createdAt"
           FROM audit_logs
          WHERE (${entityType} IS NULL OR entity_type = ${entityType})
            AND (${entityId}   IS NULL OR entity_id   = ${entityId}::uuid)
          ORDER BY created_at DESC
          LIMIT ${'limit} OFFSET ${offset}`
    );
    models:AuditLogRow[]|error result = from models:AuditLogRow row in resultStream select row;
    if result is error {
        return error models:DatabaseError("Failed to fetch audit logs", result);
    }
    return result;
}

// =============================================================================
// WAITLIST
// =============================================================================
public isolated function dbCreateWaitlistEntry(string userId, models:CreateWaitlistRequest req)
        returns models:WaitlistEntry|models:DatabaseError {
    sql:ExecutionResult|sql:Error result = dbClient->execute(
        `INSERT INTO waitlist
           (user_id, seat_id, from_station_id, to_station_id, travel_date,
            passenger_name, passenger_email)
         VALUES
           (CASE WHEN ${userId} = '' THEN NULL ELSE ${userId}::uuid END,
            ${req.seatId}::uuid, ${req.fromStationId}::uuid,
            ${req.toStationId}::uuid, ${req.travelDate}::date,
            ${req.passengerName}, ${req.passengerEmail})`
    );
    if result is sql:Error {
        return error models:DatabaseError("Failed to create waitlist entry", result);
    }
    models:WaitlistEntry|sql:Error entry = dbClient->queryRow(
        `SELECT id::text, seat_id::text AS "seatId",
                from_station_id::text AS "fromStationId",
                to_station_id::text AS "toStationId",
                travel_date::text AS "travelDate",
                passenger_name AS "passengerName",
                passenger_email AS "passengerEmail",
                status, created_at::text AS "createdAt"
           FROM waitlist
          WHERE user_id = CASE WHEN ${userId} = '' THEN NULL ELSE ${userId}::uuid END
            AND seat_id = ${req.seatId}::uuid
            AND travel_date = ${req.travelDate}::date
            AND status = 'WAITING'
          ORDER BY created_at DESC LIMIT 1`
    );
    if entry is sql:Error {
        return error models:DatabaseError("Failed to fetch waitlist entry", entry);
    }
    return entry;
}

public isolated function dbPromoteWaitlist(
        string seatId, string fromStationId, string toStationId, string travelDate)
        returns error? {
    _ = check dbClient->execute(
        `UPDATE waitlist SET status = 'PROMOTED', updated_at = NOW()
          WHERE id = (
              SELECT id FROM waitlist
               WHERE seat_id         = ${seatId}::uuid
                 AND from_station_id = ${fromStationId}::uuid
                 AND to_station_id   = ${toStationId}::uuid
                 AND travel_date     = ${travelDate}::date
                 AND status          = 'WAITING'
                 AND deleted_at IS NULL
               ORDER BY created_at ASC
               LIMIT 1
          )`
    );
}

// =============================================================================
// ADMIN — occupancy & revenue
// =============================================================================
public isolated function dbGetOccupancy(string travelDate)
        returns models:OccupancyRecord[]|models:DatabaseError {
    stream<models:OccupancyRecord, sql:Error?> resultStream = dbClient->query(
        `SELECT c.coach_number AS "coachNumber", c.coach_class AS "coachClass",
                s.seat_number AS "seatNumber",
                sf.code AS "fromStationCode", st.code AS "toStationCode",
                ssb.from_station_order AS "fromOrder",
                ssb.to_station_order   AS "toOrder",
                ssb.status, ssb.travel_date::text AS "travelDate"
           FROM seat_segment_bookings ssb
           JOIN seats   s  ON s.id = ssb.seat_id
           JOIN coaches c  ON c.id = s.coach_id
           JOIN stations sf ON sf.order_index = ssb.from_station_order
           JOIN stations st ON st.order_index = ssb.to_station_order
          WHERE ssb.travel_date = ${travelDate}::date
            AND ssb.status IN ('HELD','CONFIRMED')
          ORDER BY c.coach_number, s.seat_number`
    );
    models:OccupancyRecord[]|error result = from models:OccupancyRecord row in resultStream select row;
    if result is error {
        return error models:DatabaseError("Failed to fetch occupancy", result);
    }
    return result;
}

public isolated function dbGetRevenue(string fromDate, string toDate, int page, int 'limit)
        returns models:RevenueRecord[]|models:DatabaseError {
    int offset = calcOffset(page, 'limit);
    stream<models:RevenueRecord, sql:Error?> resultStream = dbClient->query(
        `WITH booking_classes AS (
             SELECT DISTINCT b.id AS booking_id, c.coach_class
               FROM bookings b
               JOIN seat_segment_bookings ssb ON ssb.booking_id = b.id
               JOIN seats s ON s.id = ssb.seat_id
               JOIN coaches c ON c.id = s.coach_id
              WHERE b.travel_date BETWEEN ${fromDate}::date AND ${toDate}::date
                AND b.status = 'CONFIRMED'
                AND b.deleted_at IS NULL
         )
         SELECT b.travel_date::text AS "travelDate",
                bc.coach_class      AS "coachClass",
                COUNT(b.id)::int    AS "totalBookings",
                SUM(b.fare_amount)  AS "totalRevenue"
           FROM bookings b
           JOIN booking_classes bc ON bc.booking_id = b.id
          WHERE b.travel_date BETWEEN ${fromDate}::date AND ${toDate}::date
            AND b.status = 'CONFIRMED'
            AND b.deleted_at IS NULL
          GROUP BY b.travel_date, bc.coach_class
          ORDER BY b.travel_date DESC, bc.coach_class
          LIMIT ${'limit} OFFSET ${offset}`
    );
    models:RevenueRecord[]|error result = from models:RevenueRecord row in resultStream select row;
    if result is error {
        return error models:DatabaseError("Failed to fetch revenue", result);
    }
    return result;
}

// =============================================================================
// HEALTH CHECK
// =============================================================================
public isolated function dbPingCheck() returns int|error {
    time:Utc t0 = time:utcNow();
    int|sql:Error result = dbClient->queryRow(`SELECT 1`);
    time:Utc t1 = time:utcNow();
    if result is sql:Error {
        return result;
    }
    return <int>((t1[0] - t0[0]) * 1000);
}

// =============================================================================
// EXPIRE STALE HELD BOOKINGS (background job)
// =============================================================================
public isolated function dbExpireHeldBookings() returns error? {
    transaction {
        _ = check dbClient->execute(
            `UPDATE bookings SET status = 'EXPIRED'
              WHERE status = 'HELD' AND held_until < NOW()`
        );
        _ = check dbClient->execute(
            `UPDATE seat_segment_bookings SET status = 'EXPIRED'
              WHERE status = 'HELD'
                AND booking_id IN (SELECT id FROM bookings WHERE status = 'EXPIRED')`
        );
        check commit;
    }
}
