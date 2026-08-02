-- =============================================================================
-- V2 — Database Indexes
-- Carefully chosen to cover all critical query paths
-- =============================================================================

-- ── Stations ──────────────────────────────────────────────────────────────────
-- Primary lookup (active only) with sort order
CREATE INDEX idx_stations_active_order ON stations (order_index)
    WHERE deleted_at IS NULL;

-- ── Coaches ───────────────────────────────────────────────────────────────────
CREATE INDEX idx_coaches_train_id ON coaches (train_id)
    WHERE deleted_at IS NULL;

-- ── Seats ─────────────────────────────────────────────────────────────────────
CREATE INDEX idx_seats_coach_id ON seats (coach_id)
    WHERE deleted_at IS NULL;

-- ── Users ─────────────────────────────────────────────────────────────────────
-- Login lookup
CREATE INDEX idx_users_email ON users (email)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_users_role ON users (role)
    WHERE deleted_at IS NULL;

-- ── Refresh Tokens ────────────────────────────────────────────────────────────
-- Token validation (hot path)
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens (token_hash)
    WHERE revoked_at IS NULL;

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens (user_id, expires_at);

-- ── Bookings ──────────────────────────────────────────────────────────────────
-- Reference code lookup (confirmation page)
CREATE INDEX idx_bookings_reference ON bookings (reference_code)
    WHERE deleted_at IS NULL;

-- User's booking list
CREATE INDEX idx_bookings_user_id ON bookings (user_id, created_at DESC)
    WHERE deleted_at IS NULL;

-- Admin occupancy/revenue queries
CREATE INDEX idx_bookings_travel_date ON bookings (travel_date, status)
    WHERE deleted_at IS NULL;

-- Expired HELD bookings cleanup job
CREATE INDEX idx_bookings_held_expiry ON bookings (held_until)
    WHERE status = 'HELD';

-- ── Seat Segment Bookings (CRITICAL PATH) ────────────────────────────────────
-- The overlap check query:
--   WHERE seat_id = $1
--     AND travel_date = $2
--     AND status IN ('HELD','CONFIRMED')
--     AND from_station_order < $toOrder
--     AND to_station_order  > $fromOrder
-- This composite index is the most important in the system.
CREATE INDEX idx_ssb_overlap_check ON seat_segment_bookings
    (seat_id, travel_date, status, from_station_order, to_station_order);

-- Admin occupancy report by coach
CREATE INDEX idx_ssb_travel_date_status ON seat_segment_bookings (travel_date, status);

-- ── Waitlist ──────────────────────────────────────────────────────────────────
-- FIFO promotion: find next waiting entry for a seat on a date
CREATE INDEX idx_waitlist_seat_date_status ON waitlist
    (seat_id, travel_date, status, created_at ASC)
    WHERE deleted_at IS NULL;

-- ── Rate Limit Windows ────────────────────────────────────────────────────────
-- Hot path: every request checks this
CREATE INDEX idx_rate_limit_lookup ON rate_limit_windows
    (identifier, endpoint_group, window_start);

-- ── Audit Logs ────────────────────────────────────────────────────────────────
-- Admin audit log browser (time-sorted, filterable by entity)
CREATE INDEX idx_audit_created_at ON audit_logs (created_at DESC);
CREATE INDEX idx_audit_entity ON audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs (actor_id, created_at DESC);
