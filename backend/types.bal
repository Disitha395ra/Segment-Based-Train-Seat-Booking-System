// =============================================================================
// types.bal — All record types, DTOs, and enums for the Train Booking API
// =============================================================================

// ── Configurable Variables ────────────────────────────────────────────────────
configurable string   dbHost                = ?;
configurable int      dbPort                = 5432;
configurable string   dbName                = ?;
configurable string   dbUser                = ?;
configurable string   dbPassword            = ?;
configurable string   jwtSecret             = ?;
configurable int      jwtAccessExpirySeconds = 900;
configurable int      jwtRefreshExpiryDays  = 7;
configurable string   mfaEncryptionKey      = ?;
configurable decimal  fareBaseRatePerKm     = 2.50d;
configurable decimal  farePeakMultiplier    = 1.2d;
configurable int      rateLimitGeneral      = 100;
configurable int      rateLimitBooking      = 20;
configurable int      rateLimitAuth         = 10;
configurable string   corsAllowedOrigins    = "http://localhost:3000";
configurable string   appEnv                = "development";

// ── API Response Envelope ─────────────────────────────────────────────────────
public type ApiResponse record {|
    boolean success;
    json?   data;
    ApiError? 'error;
    ResponseMeta meta;
|};

public type ApiError record {|
    string code;
    string message;
    json?  details;
|};

public type ResponseMeta record {|
    string requestId;
    string apiVersion = "v1";
    string timestamp;
    PaginationMeta? pagination = ();
|};

public type PaginationMeta record {|
    int page;
    int 'limit;
    int total;
    int totalPages;
|};

// ── Custom Error Types ────────────────────────────────────────────────────────
public type ValidationError distinct error;
public type ConflictError    distinct error;
public type NotFoundError    distinct error;
public type AuthError        distinct error;
public type RateLimitError   distinct error;
public type DatabaseError    distinct error;
public type MfaRequiredError distinct error;

// ── Station ───────────────────────────────────────────────────────────────────
public type StationRow record {|
    string  id;
    string  name;
    string  code;
    int     orderIndex;
    decimal distanceKm;
|};

// ── Train ─────────────────────────────────────────────────────────────────────
public type TrainRow record {|
    string  id;
    string  name;
    string  trainNumber;
    string  departureTime;
    boolean isActive;
|};

// ── Coach ─────────────────────────────────────────────────────────────────────
public type CoachRow record {|
    string id;
    string trainId;
    int    coachNumber;
    string coachClass;
    int    totalSeats;
|};

// ── Seat ──────────────────────────────────────────────────────────────────────
public type SeatRow record {|
    string id;
    string coachId;
    int    seatNumber;
|};

// Seat with availability info (computed)
public type SeatAvailability record {|
    string  id;
    string  coachId;
    int     coachNumber;
    string  coachClass;
    int     seatNumber;
    boolean available;
    int     waitlistCount;
|};

// ── User ──────────────────────────────────────────────────────────────────────
public type UserRow record {|
    string  id;
    string  email;
    string  passwordHash;
    string  passwordSalt;
    string  fullName;
    string? phone;
    string  role;
    boolean mfaEnabled;
    string? mfaSecretEncrypted;
    boolean isActive;
|};

public type RegisterRequest record {|
    string email;
    string password;
    string fullName;
    string? phone = ();
|};

public type LoginRequest record {|
    string email;
    string password;
    string? totpCode = ();
|};

public type RefreshRequest record {|
    string refreshToken;
|};

public type TokenPair record {|
    string  accessToken;
    string  refreshToken;
    string  tokenType = "Bearer";
    int     expiresIn;
    boolean mfaRequired = false;
|};

public type MfaSetupResponse record {|
    string qrUri;
    string secret;
    string[] backupCodes;
|};

public type MfaVerifyRequest record {|
    string totpCode;
|};

public type UserProfile record {|
    string  id;
    string  email;
    string  fullName;
    string? phone;
    string  role;
    boolean mfaEnabled;
    string  createdAt;
|};

// ── Booking ───────────────────────────────────────────────────────────────────
public type CreateBookingRequest record {|
    string  seatId;
    string  fromStationId;
    string  toStationId;
    string  travelDate;    // ISO date: YYYY-MM-DD
    string  passengerName;
    string  passengerEmail;
    string? passengerPhone = ();
|};

public type BookingRow record {|
    string  id;
    string  referenceCode;
    string? userId;
    string  seatId;
    string  fromStationId;
    string  toStationId;
    string  travelDate;
    decimal fareAmount;
    string  fareBreakdown;  // JSON string from JSONB
    string  status;
    string  passengerName;
    string  passengerEmail;
    string? passengerPhone;
    string? heldUntil;
    string  createdAt;
    string  updatedAt;
|};

public type BookingDetail record {|
    string  id;
    string  referenceCode;
    string  status;
    string  passengerName;
    string  passengerEmail;
    string? passengerPhone;
    string  travelDate;
    decimal fareAmount;
    json    fareBreakdown;
    string? heldUntil;
    string  createdAt;
    SeatInfo seat;
    StationInfo fromStation;
    StationInfo toStation;
|};

public type SeatInfo record {|
    string id;
    int    seatNumber;
    int    coachNumber;
    string coachClass;
|};

public type StationInfo record {|
    string id;
    string name;
    string code;
    int    orderIndex;
|};

// ── Fare ──────────────────────────────────────────────────────────────────────
public type FareEstimateRequest record {|
    string fromStationId;
    string toStationId;
    string coachClass;
    string travelDate;
|};

public type FareBreakdown record {|
    decimal distanceKm;
    decimal baseRatePerKm;
    string  coachClass;
    decimal classMultiplier;
    boolean isPeak;
    decimal peakMultiplier;
    decimal subtotal;
    decimal totalFare;
|};

// ── Waitlist ──────────────────────────────────────────────────────────────────
public type CreateWaitlistRequest record {|
    string  seatId;
    string  fromStationId;
    string  toStationId;
    string  travelDate;
    string  passengerName;
    string  passengerEmail;
|};

public type WaitlistEntry record {|
    string id;
    string seatId;
    string fromStationId;
    string toStationId;
    string travelDate;
    string passengerName;
    string passengerEmail;
    string status;
    string createdAt;
|};

// ── Admin ─────────────────────────────────────────────────────────────────────
public type OccupancyRecord record {|
    int    coachNumber;
    string coachClass;
    int    seatNumber;
    string fromStationCode;
    string toStationCode;
    int    fromOrder;
    int    toOrder;
    string status;
    string travelDate;
|};

public type RevenueRecord record {|
    string  travelDate;
    string  coachClass;
    int     totalBookings;
    decimal totalRevenue;
|};

public type AuditLogRow record {|
    string  id;
    string? actorId;
    string  actorType;
    string  action;
    string? entityType;
    string? entityId;
    string? oldValue;
    string? newValue;
    string? ipAddress;
    string  createdAt;
|};

// ── Health ────────────────────────────────────────────────────────────────────
public type HealthStatus record {|
    string status;
    string 'version;
    string timestamp;
    HealthChecks checks;
|};

public type HealthChecks record {|
    ComponentHealth database;
    ComponentHealth cache;
|};

public type ComponentHealth record {|
    string status;
    int?   latencyMs = ();
|};

// ── Pagination query params ───────────────────────────────────────────────────
public type PaginationParams record {|
    int page  = 1;
    int 'limit = 20;
|};

// ── Rate limit context key ────────────────────────────────────────────────────
public const string RATE_LIMIT_GROUP_GENERAL = "general";
public const string RATE_LIMIT_GROUP_BOOKING = "booking";
public const string RATE_LIMIT_GROUP_AUTH    = "auth";

// ── JWT claim keys ────────────────────────────────────────────────────────────
public const string JWT_CLAIM_USER_ID   = "userId";
public const string JWT_CLAIM_ROLE      = "role";
public const string JWT_CLAIM_MFA_DONE  = "mfaDone";

// ── Booking hold duration (minutes) ──────────────────────────────────────────
public const int BOOKING_HOLD_MINUTES = 10;
