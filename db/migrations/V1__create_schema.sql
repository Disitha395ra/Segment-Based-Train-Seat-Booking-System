-- =============================================================================
-- V1 — Complete Schema
-- Train Seat Booking System — Colombo Fort → Badulla
-- =============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- STATIONS
-- =============================================================================
CREATE TABLE stations (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(100) NOT NULL,
    code          VARCHAR(10)  NOT NULL,
    order_index   SMALLINT    NOT NULL,   -- 0 = Colombo Fort, 21 = Badulla
    distance_km   NUMERIC(8,2) NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ,
    CONSTRAINT uq_station_code        UNIQUE (code),
    CONSTRAINT uq_station_order_index UNIQUE (order_index)
);

-- =============================================================================
-- TRAINS
-- =============================================================================
CREATE TABLE trains (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) NOT NULL,
    train_number    VARCHAR(20)  NOT NULL,
    departure_time  TIME        NOT NULL,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_train_number UNIQUE (train_number)
);

-- =============================================================================
-- COACHES
-- =============================================================================
CREATE TABLE coaches (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    train_id     UUID        NOT NULL REFERENCES trains(id) ON DELETE RESTRICT,
    coach_number SMALLINT    NOT NULL,
    coach_class  VARCHAR(25) NOT NULL,
    total_seats  SMALLINT    NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMPTZ,
    CONSTRAINT uq_coach_train_number UNIQUE (train_id, coach_number),
    CONSTRAINT chk_coach_class CHECK (
        coach_class IN ('FIRST', 'SECOND_RESERVED', 'THIRD_RESERVED', 'UNRESERVED')
    ),
    CONSTRAINT chk_total_seats CHECK (total_seats > 0 AND total_seats <= 200)
);

-- =============================================================================
-- SEATS
-- =============================================================================
CREATE TABLE seats (
    id           UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id     UUID     NOT NULL REFERENCES coaches(id) ON DELETE RESTRICT,
    seat_number  SMALLINT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMPTZ,
    CONSTRAINT uq_seat_coach_number UNIQUE (coach_id, seat_number)
);

-- =============================================================================
-- USERS (passengers + admins)
-- =============================================================================
CREATE TABLE users (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email                 VARCHAR(255) NOT NULL,
    password_hash         VARCHAR(128) NOT NULL,
    password_salt         VARCHAR(64)  NOT NULL,
    full_name             VARCHAR(100) NOT NULL,
    phone                 VARCHAR(20),
    role                  VARCHAR(20)  NOT NULL DEFAULT 'PASSENGER',
    mfa_enabled           BOOLEAN      NOT NULL DEFAULT FALSE,
    mfa_secret_encrypted  VARCHAR(512),
    is_active             BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at            TIMESTAMPTZ,
    CONSTRAINT uq_user_email UNIQUE (email),
    CONSTRAINT chk_user_role CHECK (role IN ('PASSENGER', 'ADMIN', 'SUPERADMIN'))
);

-- =============================================================================
-- REFRESH TOKENS
-- =============================================================================
CREATE TABLE refresh_tokens (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(128) NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    ip_address  INET,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash)
);

-- =============================================================================
-- MFA BACKUP CODES
-- =============================================================================
CREATE TABLE mfa_backup_codes (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash  VARCHAR(128) NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- BOOKINGS
-- =============================================================================
CREATE TABLE bookings (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    reference_code   VARCHAR(20)  NOT NULL,
    user_id          UUID         REFERENCES users(id) ON DELETE SET NULL,
    seat_id          UUID         NOT NULL REFERENCES seats(id) ON DELETE RESTRICT,
    from_station_id  UUID         NOT NULL REFERENCES stations(id) ON DELETE RESTRICT,
    to_station_id    UUID         NOT NULL REFERENCES stations(id) ON DELETE RESTRICT,
    travel_date      DATE         NOT NULL,
    fare_amount      NUMERIC(10,2) NOT NULL,
    fare_breakdown   JSONB        NOT NULL DEFAULT '{}',
    status           VARCHAR(20)  NOT NULL DEFAULT 'HELD',
    passenger_name   VARCHAR(100) NOT NULL,
    passenger_email  VARCHAR(255) NOT NULL,
    passenger_phone  VARCHAR(20),
    held_until       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ,
    CONSTRAINT uq_booking_reference UNIQUE (reference_code),
    CONSTRAINT chk_booking_status CHECK (
        status IN ('HELD', 'CONFIRMED', 'CANCELLED', 'EXPIRED')
    )
);

-- =============================================================================
-- SEAT SEGMENT BOOKINGS — core concurrency-safe table
-- Each row represents one booked interval on a physical seat for one travel_date
-- Overlap rule: two bookings conflict iff
--   from_station_order < other.to_station_order AND to_station_order > other.from_station_order
-- =============================================================================
CREATE TABLE seat_segment_bookings (
    id                  UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id          UUID     NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    seat_id             UUID     NOT NULL REFERENCES seats(id) ON DELETE RESTRICT,
    from_station_order  SMALLINT NOT NULL,  -- inclusive
    to_station_order    SMALLINT NOT NULL,  -- exclusive
    travel_date         DATE     NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'HELD',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_ssb_order CHECK (from_station_order < to_station_order),
    CONSTRAINT chk_ssb_status CHECK (status IN ('HELD', 'CONFIRMED', 'CANCELLED', 'EXPIRED'))
);

-- =============================================================================
-- WAITLIST
-- =============================================================================
CREATE TABLE waitlist (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID        REFERENCES users(id) ON DELETE SET NULL,
    seat_id          UUID        NOT NULL REFERENCES seats(id) ON DELETE RESTRICT,
    from_station_id  UUID        NOT NULL REFERENCES stations(id) ON DELETE RESTRICT,
    to_station_id    UUID        NOT NULL REFERENCES stations(id) ON DELETE RESTRICT,
    travel_date      DATE        NOT NULL,
    passenger_name   VARCHAR(100) NOT NULL,
    passenger_email  VARCHAR(255) NOT NULL,
    status           VARCHAR(20) NOT NULL DEFAULT 'WAITING',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ,
    CONSTRAINT chk_waitlist_status CHECK (
        status IN ('WAITING', 'PROMOTED', 'EXPIRED', 'CANCELLED')
    )
);

-- =============================================================================
-- RATE LIMIT WINDOWS (sliding window per IP per endpoint group)
-- =============================================================================
CREATE TABLE rate_limit_windows (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    identifier     VARCHAR(100) NOT NULL,  -- IP address or user_id
    endpoint_group VARCHAR(50)  NOT NULL,  -- 'general' | 'booking' | 'auth'
    request_count  INT         NOT NULL DEFAULT 0,
    window_start   TIMESTAMPTZ NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_rate_limit UNIQUE (identifier, endpoint_group, window_start)
);

-- =============================================================================
-- AUDIT LOGS — immutable append-only
-- =============================================================================
CREATE TABLE audit_logs (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id     VARCHAR(100),               -- user UUID or 'SYSTEM'
    actor_type   VARCHAR(20) NOT NULL DEFAULT 'USER',  -- USER | ADMIN | SYSTEM
    action       VARCHAR(60) NOT NULL,       -- e.g. BOOKING_CREATED, USER_LOGIN
    entity_type  VARCHAR(50),                -- BOOKING | USER | SEAT | etc.
    entity_id    UUID,
    old_value    JSONB,
    new_value    JSONB,
    ip_address   INET,
    user_agent   TEXT,
    metadata     JSONB        NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Trigger to prevent UPDATE/DELETE on audit_logs
CREATE OR REPLACE FUNCTION prevent_audit_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit log records are immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_immutable
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION prevent_audit_modification();

-- =============================================================================
-- updated_at auto-trigger
-- =============================================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stations_updated_at   BEFORE UPDATE ON stations   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_trains_updated_at     BEFORE UPDATE ON trains     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_coaches_updated_at    BEFORE UPDATE ON coaches    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_seats_updated_at      BEFORE UPDATE ON seats      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_users_updated_at      BEFORE UPDATE ON users      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_bookings_updated_at   BEFORE UPDATE ON bookings   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ssb_updated_at        BEFORE UPDATE ON seat_segment_bookings FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_waitlist_updated_at   BEFORE UPDATE ON waitlist   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
