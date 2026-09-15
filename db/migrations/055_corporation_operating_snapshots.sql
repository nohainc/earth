-- EARTH ACTIVE MIGRATION: deterministic corporation operating projection

CREATE TABLE IF NOT EXISTS corporation_operating_snapshots (
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  active_territory_count INTEGER NOT NULL CHECK (active_territory_count >= 0),
  active_house_count INTEGER NOT NULL CHECK (active_house_count >= 0),
  active_building_count INTEGER NOT NULL CHECK (active_building_count >= 0),
  service_capacity_units BIGINT NOT NULL CHECK (service_capacity_units >= 0),
  service_allocated_units BIGINT NOT NULL CHECK (service_allocated_units >= 0),
  operating_cost_units BIGINT NOT NULL CHECK (operating_cost_units >= 0),
  service_revenue_units BIGINT NOT NULL CHECK (service_revenue_units >= 0),
  active_research_project_count INTEGER NOT NULL CHECK (active_research_project_count >= 0),
  organization_financial_status TEXT CHECK (organization_financial_status IN ('HEALTHY','WATCH','STRESS','INSOLVENT','RESOLUTION')),
  rules_version TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_id, game_day)
);

CREATE INDEX IF NOT EXISTS corporation_operating_snapshots_day_idx
  ON corporation_operating_snapshots (game_day, corporation_id);
