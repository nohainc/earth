-- Migration 038: complete the canonical local institution seed rows.
-- The institutions table alone is insufficient for city/corporation foreign keys.

INSERT INTO institutions (id, kind, name, status)
VALUES
  ('CITY-0084', 'CITY', 'New Carthage', 'active'),
  ('CORP-001', 'CORPORATION', 'Helios Cooperative', 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury)
VALUES ('CITY-0084', 'CITY-0084', 0, 100, 100, 100, 50, 0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO corporations (id, institution_id, member_count, treasury, constitution_version)
VALUES ('CORP-001', 'CORP-001', 0, 0, 1)
ON CONFLICT (id) DO NOTHING;
