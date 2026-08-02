# README — Segment-Based Train Seat Booking System
## Sri Lanka Railways · Colombo Fort – Badulla Line

A production-grade full-stack booking system that lets a single reserved seat be independently booked for multiple non-overlapping legs of the same scenic rail journey.

---

## Architecture

```
┌─────────────┐   HTTP/REST   ┌──────────────────┐   SQL/JDBC   ┌──────────────┐
│  React SPA  │ ────────────► │  Ballerina API   │ ──────────► │ PostgreSQL   │
│  (Vite)     │               │  (Swan Lake)     │              │  16          │
│  Port 3000  │               │  Port 9090       │              │  Port 5432   │
└─────────────┘               └──────────────────┘              └──────────────┘
                                        │
                               ┌────────┴──────────┐
                               │  Flyway Migrations │
                               │  V1 schema         │
                               │  V2 indexes        │
                               │  R seed data       │
                               └───────────────────┘
```

---

## Quick Start

### Prerequisites
- Docker Desktop (with Compose v2)
- `git`

### 1. Clone & configure

```bash
git clone <repo>
cd Segment-Based-Train-Seat-Booking-System

# Create environment file
cp .env.example .env

# Edit secrets (REQUIRED before running)
notepad .env
```

`.env` minimum required values:
```env
POSTGRES_PASSWORD=choose_a_strong_password
JWT_SECRET=at_least_32_chars_random_string
MFA_ENCRYPTION_KEY=64_hex_chars_random  # e.g. openssl rand -hex 32
```

### 2. Start with Docker Compose

```bash
docker compose up --build
```

Services start in dependency order:
1. **PostgreSQL 16** (db) — waits for healthcheck
2. **Flyway** (migrate) — runs schema + index + seed migrations
3. **Ballerina API** (backend) — starts on port 9090
4. **React SPA** (frontend) — starts on port 3000

### 3. Open the app

- **App:** http://localhost:3000
- **Health check:** http://localhost:9090/health
- **API:** http://localhost:9090/api/v1

---

## Development (without Docker)

### Backend (Ballerina)

```bash
# Install Ballerina Swan Lake 2201.10.0 from https://ballerina.io
# Then:
cd backend
cp Config.toml.template Config.toml
# Edit Config.toml with your local Postgres credentials
bal run
```

### Frontend (React + Vite)

```bash
cd frontend
cp .env.example .env
npm install
npm run dev      # http://localhost:3000
```

---

## API Reference

All endpoints are under `/api/v1`. All responses follow the standard envelope:
```json
{
  "success": true,
  "data": { ... },
  "error": null,
  "meta": { "requestId": "...", "apiVersion": "v1", "timestamp": "..." }
}
```

### Auth
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | Public | Create account |
| POST | `/auth/login` | Public | Login (returns access + refresh token) |
| POST | `/auth/refresh` | Public | Rotate refresh token |
| POST | `/auth/logout` | Bearer | Revoke refresh token |
| GET | `/auth/me` | Bearer | Get current user profile |
| POST | `/auth/mfa/setup` | Bearer | Initiate TOTP MFA setup |
| POST | `/auth/mfa/verify` | Bearer | Enable MFA after verifying TOTP code |

### Booking
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/bookings` | Public | Create booking (segment-based) |
| GET | `/bookings` | Bearer | List my bookings (paginated) |
| GET | `/bookings/:id` | Bearer | Get booking by ID |
| GET | `/bookings/ref/:code` | Public | Get booking by reference code |
| POST | `/bookings/:id/confirm` | Bearer | Confirm held booking |
| DELETE | `/bookings/:id` | Bearer | Cancel booking |

### Availability
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/stations` | Public | List all stations |
| GET | `/trains` | Public | List active trains |
| GET | `/trains/:id/seats/availability?from=&to=&date=` | Public | Real-time seat map |
| GET | `/fare/estimate?from=&to=&coachClass=&date=` | Public | Fare calculation |

### Admin
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/admin/occupancy?date=` | ADMIN | Coach occupancy grid |
| GET | `/admin/revenue?from=&to=` | ADMIN | Revenue by class and date |
| GET | `/admin/audit` | ADMIN | Append-only audit logs |

---

## Industry Features Implemented

| # | Feature | Implementation |
|---|---------|----------------|
| 1 | **Refresh Tokens** | Rotating refresh tokens with reuse detection + token revocation table |
| 2 | **MFA** | RFC 6238 TOTP with AES-256 encrypted secret, 8 backup codes |
| 3 | **Rate Limiting** | Sliding window per-IP per-endpoint-group in PostgreSQL |
| 4 | **Input Validation** | Ballerina regex + length checks; React `required`, `pattern` attrs |
| 5 | **Data Sanitization** | Parameterized queries throughout (zero string interpolation in SQL) |
| 6 | **Centralized Error Handling** | `ErrorInterceptor` maps typed errors → HTTP status + envelope |
| 7 | **API Versioning** | All endpoints under `/api/v1` |
| 8 | **Environment Variables** | `Config.toml` generated from Docker env vars at runtime |
| 9 | **Caching** | Ballerina `cache:Cache` — stations (1h TTL), availability (10s TTL) |
| 10 | **Database Indexing** | Composite indexes on segment overlap query + booking lookups |
| 11 | **Database Transactions** | `SERIALIZABLE` + `SELECT FOR UPDATE` for concurrent booking safety |
| 12 | **Soft Delete** | `deleted_at` column on all mutable tables |
| 13 | **Audit Logs** | Append-only `audit_logs` table — no UPDATE/DELETE, INSERT only |
| 14 | **API Documentation** | OpenAPI spec endpoint at `/api/v1/docs` |
| 15 | **Health Check** | `/health` with database latency and cache status |
| 16 | **Response Standardization** | `{ success, data, error, meta }` envelope on every response |
| 17 | **Security Headers** | HSTS, CSP, X-Frame-Options, X-XSS-Protection via interceptor |
| 18 | **Database Migration** | Flyway versioned migrations (V1 schema, V2 indexes, R seed) |
| 19 | **Dependency Injection** | Ballerina function parameter injection pattern; DB client singleton |

---

## Segment Booking Logic

The core innovation: one physical seat can be booked by multiple passengers for non-overlapping legs.

**Overlap detection (SQL):**
```sql
SELECT COUNT(*) FROM seat_segment_bookings
 WHERE seat_id            = $seatId
   AND travel_date        = $date
   AND status             IN ('HELD','CONFIRMED')
   AND from_station_order < $toOrder    -- existing booking starts before new booking ends
   AND to_station_order   > $fromOrder  -- existing booking ends after new booking starts
```

This uses the half-open interval `[from, to)` model — if zero rows are returned, the seat is available for the requested segment.

**Concurrency safety:**
1. `SELECT ... FOR UPDATE` on the seat row acquires a row-level lock
2. Overlap check runs inside the same transaction
3. Insert proceeds only if overlap count = 0
4. Transaction isolation: `SERIALIZABLE`
5. Concurrent bookings for the same segment → one succeeds, one gets `ConflictError → HTTP 409`

---

## Core Design Decisions & Reasoning

1. **Database-Backed Segment Tracking (Relational Model):**
   * **Decision:** Modeled bookings using `seat_segment_bookings` with `from_station_order` and `to_station_order` on a continuous integer axis.
   * **Reasoning:** Sri Lanka's train network is strictly linear (Colombo to Badulla). By assigning an integer index to each station based on its order, overlap detection reduces to a mathematically proven 1D intersection check (`startA < endB AND endA > startB`). This avoids complex graph databases or storing arrays of "occupied stations" per seat, keeping the database normalized and queries blazing fast.

2. **Concurrency Control (Pessimistic Locking + Serializable Transactions):**
   * **Decision:** Used `SELECT ... FOR UPDATE` wrapped in `SERIALIZABLE` isolation blocks inside Ballerina.
   * **Reasoning:** The challenge explicitly requires handling concurrent booking attempts on the same seat. Optimistic locking (version columns) might lead to high failure rates during peak booking seasons (e.g., holidays). Pessimistic locking guarantees that once a user starts the booking transaction, overlapping bookings are immediately rejected, ensuring zero double-bookings.

3. **Backend Choice (Ballerina Swan Lake):**
   * **Decision:** Chose Ballerina instead of traditional Node.js/Spring Boot.
   * **Reasoning:** Ballerina offers built-in network primitives, native JSON handling, and powerful concurrency features (like isolated functions). Its strict typing and compiler-enforced safety made implementing the complex transactional logic much more reliable.

## Alternatives Considered

1. **NoSQL / Document Store (MongoDB):**
   * *Considered:* Storing a document per seat with an array of "booked segments".
   * *Rejected because:* Ensuring cross-document transactional integrity during concurrent bookings in NoSQL is harder and more error-prone. Relational models with ACID compliance are vastly superior for financial/booking ledgers.

2. **In-Memory Locks (Redis) for Concurrency:**
   * *Considered:* Using Redis distributed locks before hitting the database.
   * *Rejected because:* It introduces a point of failure and complexity. PostgreSQL's native row-level locking (`FOR UPDATE`) is battle-tested, simpler to maintain, and sufficiently performant for this scale.

## Challenges Faced

1. **Ballerina Concurrency Strictness:**
   * Ballerina's `isolated` function paradigm ensures thread safety by preventing shared mutable state. However, capturing external variables inside `foreach` loops within `isolated` transaction blocks initially caused compiler errors. This required refactoring the closure logic to strictly adhere to concurrency rules.
2. **Dockerizing Ballerina with PostgreSQL:**
   * Ensuring the backend only starts executing queries *after* Flyway has completely finished migrating the seed data required careful orchestration using `depends_on` and `condition: service_completed_successfully` in Docker Compose.

## Extra Credit Features Built

1. **Seat Map Visualization (Frontend):**
   * Visual representation of coaches showing exact seat availability for the selected segment, making it highly intuitive for passengers. Partially-booked seats along the route are accurately represented.
2. **Multi-Seat (Family) Booking:**
   * Transitioned the system from a strict "1 Booking = 1 Seat" to "1 Booking = N Seats" model. A family can select multiple seats in the same transaction, receiving a single Reference Code and paying a combined total fare, which accurately maps to real-world travel needs.
3. **Waitlisting for Fully Booked Segments:**
   * Implemented a waitlist feature for segments where a coach is fully booked. Passengers can leave their email to be notified if a seat becomes available due to a cancellation or expired hold.
4. **Admin Dashboard (Occupancy & Revenue):**
   * Created a dedicated dashboard for railway department staff to view coach-by-coach occupancy tables for any given date and analyze revenue reports grouped by travel date and coach class.
5. **Clear Handling of Booking Conflicts:**
   * In a high-concurrency scenario, if two users try to book the same overlapping segment simultaneously, the UI handles the 409 Conflict gracefully, warning the user that the seat was just taken and prompting them to choose another, rather than throwing a generic error.
6. **Fare Logic Beyond Simple Distance:**
   * Implemented base rates per km combined with coach class multipliers and peak/weekend multipliers (configurable via `.env`), reflecting realistic dynamic pricing models rather than hardcoded flat fees.
7. **Advanced Security (JWT + MFA + Rate Limiting):**
   * Went beyond basic auth to include rolling refresh tokens, TOTP-based Multi-Factor Authentication (MFA), and sliding-window rate limiting per endpoint group to make this truly production-ready.

---

## Default Seed Data

After `docker compose up`, the database contains:
- **22 stations** from Colombo Fort to Badulla (real station names and km)
- **1 train**: Podi Menike (express) departing 05:55
- **3 reserved coaches**: 1st Class, 2nd Reserved, 3rd Reserved
- **1 admin account**: `admin@railways.lk` / `Admin123!`

---

## Project Structure

```
.
├── backend/
│   ├── Ballerina.toml       # Package manifest
│   ├── types.bal            # All record types, DTOs, custom errors
│   ├── db.bal               # All PostgreSQL queries (parameterized)
│   ├── auth.bal             # JWT, refresh tokens, TOTP MFA
│   ├── booking.bal          # Booking logic & fare calculation
│   ├── audit.bal            # Centralized audit logging
│   ├── interceptors.bal     # Rate limit, auth, security headers, error handler
│   ├── service.bal          # HTTP service: all API endpoints
│   ├── entrypoint.sh        # Docker: generates Config.toml from env
│   └── Dockerfile
├── frontend/
│   ├── src/
│   │   ├── api/             # Axios client + endpoint functions
│   │   ├── components/      # Layout, SeatMap, Toast
│   │   ├── context/         # AuthContext
│   │   ├── pages/           # All route pages
│   │   └── styles/          # CSS variables + base reset
│   ├── nginx.conf           # nginx SPA config
│   └── Dockerfile
├── db/
│   └── migrations/
│       ├── V1__create_schema.sql
│       ├── V2__create_indexes.sql
│       └── R__seed_data.sql
├── docker-compose.yml
└── .env.example
```
