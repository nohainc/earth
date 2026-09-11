-- Technology & Research V2 Plan 22: recurring license fees are represented by
-- technology_license_contracts.daily_fee_units; remove competing subscription
-- storage and fields.

DROP TABLE IF EXISTS business_technology_subscriptions;
ALTER TABLE corporation_technology_projects
  DROP COLUMN IF EXISTS subscription_cost_credits;
