CREATE TABLE IF NOT EXISTS business_tax_allocation_rules (
  id text PRIMARY KEY,
  city_share numeric(10,6) NOT NULL CHECK (city_share >= 0 AND city_share <= 1),
  corporation_share numeric(10,6) NOT NULL CHECK (corporation_share >= 0 AND corporation_share <= 1),
  earth_share numeric(10,6) NOT NULL CHECK (earth_share >= 0 AND earth_share <= 1),
  active boolean NOT NULL DEFAULT true,
  version integer NOT NULL DEFAULT 1,
  CHECK (city_share + corporation_share + earth_share = 1)
);

INSERT INTO business_tax_allocation_rules (id, city_share, corporation_share, earth_share, active, version)
VALUES ('BUSINESS-TAX-ALLOCATION-EARTH', 0.60, 0.25, 0.15, true, 1)
ON CONFLICT (id) DO NOTHING;
