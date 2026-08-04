// =============================================================================
// booking.bal — Booking business logic, fare calculation, validation
// =============================================================================

import trainlk/backend.models;
import trainlk/backend.db;
import trainlk/backend.config;
import trainlk/backend.utils;
import ballerina/time;
import ballerina/uuid;
import ballerina/regex;
import ballerina/log;
import ballerina/sql;

// ── Booking Creation ──────────────────────────────────────────────────────────
public isolated function createBooking(
        string userId, models:CreateBookingRequest req, string? ip, string? ua)
        returns models:BookingRow|models:ValidationError|models:ConflictError|models:NotFoundError|models:DatabaseError|error {

    // 1. Validate input
    check validateBookingRequest(req);

    // 2. Resolve station orders
    models:StationRow fromStation = check db:dbGetStationById(req.fromStationId);
    models:StationRow toStation   = check db:dbGetStationById(req.toStationId);

    if fromStation.orderIndex >= toStation.orderIndex {
        return error models:ValidationError("Origin must come before destination on the route");
    }

    // 3. Validate travel date (using Sri Lanka timezone UTC+5:30)
    time:Utc utcNow = time:utcNow();
    // Add 5 hours and 30 minutes (19800 seconds) to UTC to get IST/SLST
    time:Utc localNow = [utcNow[0] + 19800, utcNow[1]];
    time:Civil todayCivil = time:utcToCivil(localNow);
    time:Civil|error travelCivil = parseTravelDate(req.travelDate);
    if travelCivil is error {
        return error models:ValidationError("Invalid travel date format (use YYYY-MM-DD)");
    }
    if travelCivil.year < todayCivil.year ||
       (travelCivil.year == todayCivil.year && travelCivil.month < todayCivil.month) ||
       (travelCivil.year == todayCivil.year && travelCivil.month == todayCivil.month &&
        travelCivil.day < todayCivil.day) {
        return error models:ValidationError("Travel date cannot be in the past");
    }

    // 4. Validate seat limit
    if req.seatIds.length() == 0 {
        return error models:ValidationError("At least one seat must be selected");
    }
    if req.seatIds.length() > 6 {
        return error models:ValidationError("Maximum 6 seats allowed per booking");
    }

    // 5. Calculate total fare across all seats
    decimal finalTotal = 0.0d;
    json[] seatBreakdowns = [];

    foreach string sId in req.seatIds {
        models:SeatRow seatRow = check dbGetSeatForFare(sId);
        models:CoachRow coachRow = check dbGetCoachById(seatRow.coachId);
        models:FareBreakdown fare = calculateFare(fromStation, toStation, coachRow.coachClass, travelCivil);
        finalTotal += fare.totalFare;
        seatBreakdowns.push({"seatId": sId, "fare": fare.toJson()});
    }

    // 6. Generate unique reference code
    string referenceCode = generateReferenceCode();

    // 7. Create booking (atomic, with SELECT FOR UPDATE on all seats)
    log:printInfo(string `Creating booking: ${referenceCode} seats=${req.seatIds.toString()} ` +
                  string `${fromStation.code}→${toStation.code} date=${req.travelDate}`);

    json compositeBreakdown = {
        "seatCount": req.seatIds.length(),
        "totalFare": finalTotal,
        "seats": seatBreakdowns
    };

    models:BookingRow booking = check db:dbCreateBooking(
        userId, req, referenceCode,
        fromStation.orderIndex, toStation.orderIndex,
        finalTotal, compositeBreakdown
    );

    // 7. Audit log (async-style — error logged but not fatal)
    error? auditErr = utils:logAudit(
        userId, "USER", "BOOKING_CREATED", "BOOKING", booking.id,
        (), {"referenceCode": referenceCode, "fare": finalTotal}, ip, ua, {}
    );
    if auditErr !is () {
        log:printWarn("Audit log failed for booking creation", 'error = auditErr);
    }

    return booking;
}

// ── Booking Confirmation ──────────────────────────────────────────────────────
public isolated function confirmBooking(string bookingId, string userId) returns error? {
    models:BookingRow booking = check db:dbGetBookingById(bookingId);
    if booking.userId != userId {
        return error models:AuthError("Not authorized to confirm this booking");
    }
    if booking.status != "HELD" {
        return error models:ConflictError("Booking is not in HELD state");
    }
    check db:dbConfirmBooking(bookingId);
    _ = check utils:logAudit(userId, "USER", "BOOKING_CONFIRMED", "BOOKING", bookingId,
            {"status": "HELD"}, {"status": "CONFIRMED"}, (), (), {});
}

// ── Booking Cancellation ──────────────────────────────────────────────────────
public isolated function cancelBooking(string bookingId, string userId, string role)
        returns error? {
    models:BookingRow booking = check db:dbGetBookingById(bookingId);
    // Admin can cancel any booking; passenger can only cancel their own
    if role != "ADMIN" && role != "SUPERADMIN" && booking.userId != userId {
        return error models:AuthError("Not authorized to cancel this booking");
    }

    check db:dbCancelBooking(bookingId);

    // Promote waitlist for all seats
    string[]|error seatIds = db:dbGetBookingSeatIds(bookingId);
    if seatIds is string[] {
        foreach string sId in seatIds {
            error? promoteErr = db:dbPromoteWaitlist(
                sId, booking.fromStationId, booking.toStationId, booking.travelDate
            );
            if promoteErr !is () {
                log:printWarn("Waitlist promotion failed", 'error = promoteErr, seatId = sId);
            }
        }
    } else {
        log:printWarn("Failed to fetch seats for waitlist promotion", 'error = seatIds);
    }

    _ = check utils:logAudit(userId, "USER", "BOOKING_CANCELLED", "BOOKING", bookingId,
            {"status": booking.status}, {"status": "CANCELLED"}, (), (), {});
}

// ── Fare Calculation ──────────────────────────────────────────────────────────
public isolated function calculateFare(
        models:StationRow fromStation, models:StationRow toStation,
        string coachClass, time:Civil travelDate) returns models:FareBreakdown {

    decimal distanceKm = toStation.distanceKm - fromStation.distanceKm;
    decimal baseRate = config:fareBaseRatePerKm;

    decimal classMultiplier = getClassMultiplier(coachClass);
    boolean isPeak = isWeekendOrHoliday(travelDate);
    decimal peakMult = isPeak ? config:farePeakMultiplier : 1.0d;

    decimal subtotal = distanceKm * baseRate * classMultiplier;
    decimal total = subtotal * peakMult;
    // Round to nearest 0.50 LKR
    total = roundToHalf(total);

    return {
        distanceKm: distanceKm,
        baseRatePerKm: baseRate,
        coachClass: coachClass,
        classMultiplier: classMultiplier,
        isPeak: isPeak,
        peakMultiplier: peakMult,
        subtotal: subtotal,
        totalFare: total
    };
}

public isolated function getClassMultiplier(string coachClass) returns decimal {
    match coachClass {
        "FIRST"            => { return 2.5d; }
        "SECOND_RESERVED"  => { return 1.5d; }
        "THIRD_RESERVED"   => { return 1.0d; }
        _                  => { return 1.0d; }
    }
}

public isolated function isWeekendOrHoliday(time:Civil d) returns boolean {
    // Saturday = 7, Sunday = 1 in time:DayOfWeek
    time:DayOfWeek? dow = d.dayOfWeek;
    if dow is () {
        return false;
    }
    return dow == time:SATURDAY || dow == time:SUNDAY;
}

public isolated function roundToHalf(decimal value) returns decimal {
    return <decimal>((<int>(value * 2.0d + 0.5d)) / 2);
}

// ── Fare Estimate (public, no booking) ───────────────────────────────────────
public isolated function estimateFare(models:FareEstimateRequest req)
        returns models:FareBreakdown|models:ValidationError|models:NotFoundError|models:DatabaseError|error {
    if req.coachClass !is "FIRST"|"SECOND_RESERVED"|"THIRD_RESERVED" {
        return error models:ValidationError("Invalid coach class");
    }
    models:StationRow fromStation = check db:dbGetStationById(req.fromStationId);
    models:StationRow toStation   = check db:dbGetStationById(req.toStationId);
    if fromStation.orderIndex >= toStation.orderIndex {
        return error models:ValidationError("Origin must come before destination");
    }
    time:Civil|error travelDate = parseTravelDate(req.travelDate);
    if travelDate is error {
        return error models:ValidationError("Invalid travel date");
    }
    return calculateFare(fromStation, toStation, req.coachClass, travelDate);
}

// ── Reference Code Generation ─────────────────────────────────────────────────
public isolated function generateReferenceCode() returns string {
    string u = regex:replaceAll(uuid:createType4AsString(), "-", "").toUpperAscii();
    return "TK" + u.substring(0, 8);
}

// ── Validation ────────────────────────────────────────────────────────────────
public isolated function validateBookingRequest(models:CreateBookingRequest req) returns models:ValidationError? {
    if req.seatIds.length() == 0 {
        return error models:ValidationError("At least one seat must be selected");
    }
    if req.fromStationId.trim() == "" || req.toStationId.trim() == "" {
        return error models:ValidationError("Origin and destination stations are required");
    }
    if req.fromStationId == req.toStationId {
        return error models:ValidationError("Origin and destination cannot be the same");
    }
    if req.travelDate.trim() == "" {
        return error models:ValidationError("Travel date is required");
    }
    if !regex:matches(req.travelDate, "^\\d{4}-\\d{2}-\\d{2}$") {
        return error models:ValidationError("Travel date must be YYYY-MM-DD format");
    }
    string name = req.passengerName.trim();
    if name.length() < 2 || name.length() > 100 {
        return error models:ValidationError("Passenger name must be 2–100 characters");
    }
    if !isValidEmail(req.passengerEmail) {
        return error models:ValidationError("Invalid passenger email address");
    }
    return ();
}

public isolated function parseTravelDate(string dateStr) returns time:Civil|error {
    // Parse YYYY-MM-DD
    string[] parts = regex:split(dateStr, "-");
    if parts.length() != 3 {
        return error("Invalid date");
    }
    int year  = check int:fromString(parts[0]);
    int month = check int:fromString(parts[1]);
    int day   = check int:fromString(parts[2]);
    return {year: year, month: month, day: day, hour: 0, minute: 0, second: 0d};
}

// ── DB helpers specific to booking ────────────────────────────────────────────
public isolated function dbGetSeatForFare(string seatId) returns models:SeatRow|models:NotFoundError|models:DatabaseError {
    models:SeatRow|sql:Error result = db:dbClient->queryRow(
        `SELECT id::text, coach_id::text AS "coachId", seat_number AS "seatNumber"
           FROM seats WHERE id = ${seatId}::uuid AND deleted_at IS NULL`
    );
    if result is sql:NoRowsError {
        return error models:NotFoundError("Seat not found: " + seatId);
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch seat", result);
    }
    return result;
}

public isolated function dbGetCoachById(string coachId) returns models:CoachRow|models:NotFoundError|models:DatabaseError {
    models:CoachRow|sql:Error result = db:dbClient->queryRow(
        `SELECT id::text, train_id::text AS "trainId", coach_number AS "coachNumber",
                coach_class AS "coachClass", total_seats AS "totalSeats"
           FROM coaches WHERE id = ${coachId}::uuid AND deleted_at IS NULL`
    );
    if result is sql:NoRowsError {
        return error models:NotFoundError("Coach not found: " + coachId);
    }
    if result is sql:Error {
        return error models:DatabaseError("Failed to fetch coach", result);
    }
    return result;
}
