-- Migration 107: corporation-owned general technologies and business subscriptions.

CREATE TABLE IF NOT EXISTS corporation_technology_projects (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id) ON DELETE CASCADE,
  technology_key TEXT NOT NULL,
  technology_name TEXT NOT NULL,
  research_cost_credits NUMERIC(20,2) NOT NULL CHECK (research_cost_credits > 0),
  subscription_cost_credits NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (subscription_cost_credits >= 0),
  effect_key TEXT NOT NULL,
  progress NUMERIC(6,3) NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','cancelled')),
  started_game_day BIGINT NOT NULL,
  completed_game_day BIGINT,
  correlation_id TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (corporation_id, technology_key)
);

CREATE INDEX IF NOT EXISTS corporation_technology_projects_status_idx
  ON corporation_technology_projects(corporation_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS business_technology_subscriptions (
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  corporation_id TEXT NOT NULL REFERENCES corporations(id) ON DELETE CASCADE,
  technology_key TEXT NOT NULL,
  subscription_cost_credits NUMERIC(20,2) NOT NULL CHECK (subscription_cost_credits >= 0),
  status TEXT NOT NULL DEFAULT 'inactive' CHECK (status IN ('active','inactive')),
  subscribed_game_day BIGINT,
  unsubscribed_game_day BIGINT,
  last_billed_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (business_id, technology_key)
);

CREATE INDEX IF NOT EXISTS business_technology_subscriptions_billing_idx
  ON business_technology_subscriptions(status, last_billed_game_day, corporation_id);
CREATE INDEX IF NOT EXISTS business_technology_subscriptions_business_idx
  ON business_technology_subscriptions(business_id, status);
