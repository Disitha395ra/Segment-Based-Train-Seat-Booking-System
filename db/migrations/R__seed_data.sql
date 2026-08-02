-- =============================================================================
-- R__seed_data.sql — Repeatable seed (Flyway re-runs if checksum changes)
-- Colombo Fort → Badulla — 22 stations, 1 train, 8 coaches, 290 seats
-- =============================================================================

-- =============================================================================
-- STATIONS — Colombo Fort → Badulla (22 stations, 0-indexed)
-- =============================================================================
INSERT INTO stations (id, name, code, order_index, distance_km) VALUES
  (gen_random_uuid(), 'Colombo Fort',         'CMB', 0,  0.00),
  (gen_random_uuid(), 'Ragama',               'RGM', 1,  18.20),
  (gen_random_uuid(), 'Gampaha',              'GMP', 2,  27.50),
  (gen_random_uuid(), 'Veyangoda',            'VYG', 3,  38.00),
  (gen_random_uuid(), 'Polgahawela',          'PLG', 4,  73.00),
  (gen_random_uuid(), 'Kandy',                'KDY', 5,  121.00),
  (gen_random_uuid(), 'Peradeniya Junction',  'PJN', 6,  124.50),
  (gen_random_uuid(), 'Gampola',              'GLA', 7,  133.00),
  (gen_random_uuid(), 'Nawalapitiya',         'NWT', 8,  155.00),
  (gen_random_uuid(), 'Hatton',               'HTN', 9,  179.00),
  (gen_random_uuid(), 'Talawakele',           'TWK', 10, 190.00),
  (gen_random_uuid(), 'Nanu Oya',             'NOY', 11, 200.00),
  (gen_random_uuid(), 'Ambewela',             'ABW', 12, 209.00),
  (gen_random_uuid(), 'Pattipola',            'PPL', 13, 215.00),
  (gen_random_uuid(), 'Ohiya',               'OHY', 14, 222.00),
  (gen_random_uuid(), 'Idalgashinna',         'IDG', 15, 234.00),
  (gen_random_uuid(), 'Haputale',             'HPT', 16, 244.00),
  (gen_random_uuid(), 'Diyatalawa',           'DYT', 17, 252.00),
  (gen_random_uuid(), 'Bandarawela',          'BDW', 18, 260.00),
  (gen_random_uuid(), 'Ella',                 'ELL', 19, 276.00),
  (gen_random_uuid(), 'Demodara',             'DMD', 20, 282.00),
  (gen_random_uuid(), 'Badulla',              'BDL', 21, 292.00)
ON CONFLICT (code) DO UPDATE SET
  name        = EXCLUDED.name,
  order_index = EXCLUDED.order_index,
  distance_km = EXCLUDED.distance_km,
  updated_at  = NOW();

-- =============================================================================
-- TRAIN — Podi Menike (5:55 AM Colombo Fort departure)
-- =============================================================================
INSERT INTO trains (id, name, train_number, departure_time, is_active)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  'Podi Menike',
  'ML-1',
  '05:55:00',
  TRUE
) ON CONFLICT (train_number) DO UPDATE SET
  name           = EXCLUDED.name,
  departure_time = EXCLUDED.departure_time,
  is_active      = EXCLUDED.is_active,
  updated_at     = NOW();

-- =============================================================================
-- COACHES
-- Coach layout: 1 First Class (40 seats), 2 Second Reserved (50 seats each),
--               5 Unreserved (no seat assignment)
-- =============================================================================
-- Coach 1 — First Class (40 seats)
INSERT INTO coaches (id, train_id, coach_number, coach_class, total_seats)
VALUES (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  1, 'FIRST', 40
) ON CONFLICT (train_id, coach_number) DO UPDATE SET
  coach_class = EXCLUDED.coach_class,
  total_seats = EXCLUDED.total_seats,
  updated_at  = NOW();

-- Coach 2 — Second Reserved (50 seats)
INSERT INTO coaches (id, train_id, coach_number, coach_class, total_seats)
VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  2, 'SECOND_RESERVED', 50
) ON CONFLICT (train_id, coach_number) DO UPDATE SET
  coach_class = EXCLUDED.coach_class,
  total_seats = EXCLUDED.total_seats,
  updated_at  = NOW();

-- Coach 3 — Second Reserved (50 seats)
INSERT INTO coaches (id, train_id, coach_number, coach_class, total_seats)
VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '11111111-1111-1111-1111-111111111111',
  3, 'SECOND_RESERVED', 50
) ON CONFLICT (train_id, coach_number) DO UPDATE SET
  coach_class = EXCLUDED.coach_class,
  total_seats = EXCLUDED.total_seats,
  updated_at  = NOW();

-- Coaches 4–8 — Unreserved (no seat rows needed)
INSERT INTO coaches (id, train_id, coach_number, coach_class, total_seats) VALUES
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-1111-1111-1111-111111111111', 4, 'UNRESERVED', 80),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '11111111-1111-1111-1111-111111111111', 5, 'UNRESERVED', 80),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '11111111-1111-1111-1111-111111111111', 6, 'UNRESERVED', 80),
  ('gggggggg-gggg-gggg-gggg-gggggggggggg', '11111111-1111-1111-1111-111111111111', 7, 'UNRESERVED', 80),
  ('hhhhhhhh-hhhh-hhhh-hhhh-hhhhhhhhhhhh', '11111111-1111-1111-1111-111111111111', 8, 'UNRESERVED', 80)
ON CONFLICT (train_id, coach_number) DO NOTHING;

-- =============================================================================
-- SEATS — Coach 1 (40 seats: 1–40)
-- =============================================================================
INSERT INTO seats (coach_id, seat_number)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', generate_series(1, 40)
ON CONFLICT (coach_id, seat_number) DO NOTHING;

-- SEATS — Coach 2 (50 seats: 1–50)
INSERT INTO seats (coach_id, seat_number)
SELECT 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', generate_series(1, 50)
ON CONFLICT (coach_id, seat_number) DO NOTHING;

-- SEATS — Coach 3 (50 seats: 1–50)
INSERT INTO seats (coach_id, seat_number)
SELECT 'cccccccc-cccc-cccc-cccc-cccccccccccc', generate_series(1, 50)
ON CONFLICT (coach_id, seat_number) DO NOTHING;

-- =============================================================================
-- DEFAULT ADMIN USER
-- email:    admin@trainlk.lk
-- password: Admin@Train2026!  (SHA-256 with salt — change in production)
-- salt: fixed for seed (change post-deploy)
-- password_hash = SHA256(salt || password)
-- =============================================================================
INSERT INTO users (
  id, email, password_hash, password_salt,
  full_name, role, mfa_enabled, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'admin@trainlk.lk',
  encode(
    sha256(('seedsalt2026' || 'Admin@Train2026!')::bytea),
    'hex'
  ),
  'seedsalt2026',
  'System Administrator',
  'ADMIN',
  FALSE,
  TRUE
) ON CONFLICT (email) DO NOTHING;
