INSERT INTO economic_assets(id, code, asset_kind) VALUES
  (1, 'CREDIT', 'CREDIT'),
  (2, 'MATERIAL', 'RESOURCE'),
  (3, 'COMPONENTS', 'RESOURCE'),
  (4, 'ENERGY', 'RESOURCE'),
  (5, 'COMPUTE', 'RESOURCE'),
  (6, 'FOOD', 'RESOURCE');

INSERT INTO economic_account_types(code, asset_kind, is_escrow) VALUES
  ('WALLET', 'CREDIT', FALSE), ('TREASURY', 'CREDIT', FALSE),
  ('OPERATIONS', 'CREDIT', FALSE), ('RESERVE', 'CREDIT', FALSE),
  ('ESCROW', 'CREDIT', TRUE), ('INVENTORY', 'RESOURCE', FALSE);

INSERT INTO budget_categories(id, institution_kind, category_code, spending_class, priority) VALUES
  ('BUDGET-DEBT', 'CORPORATION', 'DEBT_SERVICE', 'MANDATORY', 1),
  ('BUDGET-ESSENTIAL', 'CORPORATION', 'ESSENTIAL_SERVICES', 'MANDATORY', 2),
  ('BUDGET-OPS', 'CORPORATION', 'OPERATIONS', 'MANDATORY', 2),
  ('BUDGET-RESEARCH', 'CORPORATION', 'RESEARCH', 'DISCRETIONARY', 5),
  ('BUDGET-DIVIDENDS', 'CORPORATION', 'DIVIDENDS', 'DISCRETIONARY', 9);

INSERT INTO fiscal_periods(id, period_type, start_game_day, end_game_day, status)
VALUES ('FISCAL-YEAR-1', 'YEAR', 1, 365, 'ACTIVE');

INSERT INTO constitutional_rules (id, part_number, rule_number, title, description, default_value, permitted_values, authority)
VALUES
  ('CONST-1-1', 1, '1.1', 'Rule Precedence', 'EARTH constitutional rules are authoritative unless a permitted institutional rule applies.', 'EARTH baseline', 'EARTH, CORPORATION', 'EARTH'),
  ('CONST-2-1', 2, '2.1', 'Daily Economy', 'Economic settlement uses the game day as its fundamental accounting period.', 'Daily', 'Daily only', 'EARTH'),
  ('CONST-3-1', 3, '3.1', 'House Continuity', 'House economic property survives Human succession.', 'Persistent House ownership', 'House', 'EARTH')
ON CONFLICT (id) DO NOTHING;

INSERT INTO economic_policy_rules (code, output_multiplier, cost_multiplier, decay_multiplier, description)
VALUES
  ('balanced', 1.0000, 1.0000, 1.0000, 'Normal production and operating costs'),
  ('high_output', 1.3000, 1.4000, 1.0000, 'Higher output with higher operating cost'),
  ('halted', 0.0000, 0.2000, 1.0000, 'Production halted with minimum operating cost')
ON CONFLICT (code) DO NOTHING;

INSERT INTO tax_governance_rules (scope, category, maximum_rate_bps, allowed_tax_base_definitions, beneficiary_scope, rules_version)
VALUES
  ('EARTH', 'basic_levy', 2000, '["fixed_daily_obligation"]', 'EARTH', 'tax-constitution-v1'),
  ('EARTH', 'personal_income', 3000, '["positive_realized_daily_income"]', 'EARTH', 'tax-constitution-v1'),
  ('EARTH', 'market_transaction', 1000, '["external_market_trade"]', 'EARTH', 'tax-constitution-v1'),
  ('CORPORATION', 'personal_income', 3000, '["positive_realized_daily_income"]', 'CORPORATION', 'tax-constitution-v1'),
  ('CORPORATION', 'corporate_income', 4000, '["positive_realized_daily_taxable_profit"]', 'CORPORATION', 'tax-constitution-v1')
ON CONFLICT (scope, category) DO NOTHING;

INSERT INTO building_catalog (
  id, code, tier, ownership_scope, construction_credit_units, construction_minutes,
  operating_credit_units, resource_input_units, resource_output_units,
  service_type, service_capacity_units, slot_footprint, definition_version
) VALUES
  ('MATERIAL-FAB-T1', 'material_fab_t1', 1, 'PRIVATE', 50000, 1440, 250,
   '{"ENERGY":10}'::jsonb, '{"MATERIAL":100}'::jsonb, NULL, 0, 1, 'building-v1'),
  ('COMPONENT-FAB-T1', 'component_fab_t1', 1, 'PRIVATE', 75000, 2160, 400,
   '{"MATERIAL":25,"ENERGY":20}'::jsonb, '{"COMPONENTS":50}'::jsonb, NULL, 0, 2, 'building-v1'),
  ('ENERGY-PLANT-T1', 'energy_plant_t1', 1, 'PRIVATE', 60000, 1440, 300,
   '{"MATERIAL":10}'::jsonb, '{"ENERGY":120}'::jsonb, NULL, 0, 1, 'building-v1'),
  ('FOOD-FARM-T1', 'food_farm_t1', 1, 'PRIVATE', 45000, 1440, 200,
   '{"ENERGY":8}'::jsonb, '{"FOOD":80}'::jsonb, NULL, 0, 1, 'building-v1'),
  ('HOUSING-T1', 'housing_t1', 1, 'PRIVATE', 80000, 2880, 350,
   '{"ENERGY":15}'::jsonb, '{}'::jsonb, 'HOUSING', 100, 2, 'building-v1')
ON CONFLICT (id) DO NOTHING;

INSERT INTO building_catalog (
  id, code, tier, ownership_scope, construction_credit_units, construction_minutes,
  operating_credit_units, resource_input_units, resource_output_units,
  service_type, service_capacity_units, slot_footprint, definition_version
) VALUES
  ('DISTRICT-MODULE-T1', 'urban-district-module', 1, 'PUBLIC', 100000, 2880, 500,
   '{"MATERIAL":50,"ENERGY":25}'::jsonb, '{}'::jsonb, 'TERRITORY_INFRASTRUCTURE', 0, 1, 'territory-capacity-v1')
ON CONFLICT (id) DO NOTHING;

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
VALUES
  ('DISTRICT-MODULE-T1', 'POPULATION_CAPACITY', 10),
  ('DISTRICT-MODULE-T1', 'PRIVATE_SLOTS', 100),
  ('DISTRICT-MODULE-T1', 'PUBLIC_SLOTS', 20)
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;

INSERT INTO building_catalog_effects (catalog_id, effect_code, effect_value)
SELECT id, 'SERVICE_CAPACITY', service_capacity_units
FROM building_catalog
WHERE service_capacity_units > 0
ON CONFLICT (catalog_id, effect_code, rules_version) DO NOTHING;

INSERT INTO technology_catalog (
  id, code, name, patentable, definition_version, research_points_required, credit_cost_units
) VALUES
  ('TECH-AUTOMATION-V1', 'automation', 'Industrial Automation', TRUE, 'tech-v1', 1000, 25000),
  ('TECH-CLEAN-ENERGY-V1', 'clean_energy', 'Clean Energy Systems', TRUE, 'tech-v1', 1200, 30000),
  ('TECH-FOOD-SCIENCE-V1', 'food_science', 'Food Science', FALSE, 'tech-v1', 900, 18000),
  ('TECH-LOGISTICS-V1', 'logistics', 'Logistics Optimization', FALSE, 'tech-v1', 800, 16000),
  ('TECH-RESEARCH-METHODS-V1', 'research_methods', 'Research Methodology', FALSE, 'tech-v1', 1500, 35000)
ON CONFLICT (id) DO NOTHING;

INSERT INTO technology_effects (technology_id, effect_type, target_key, modifier_bps)
VALUES
  ('TECH-AUTOMATION-V1', 'PRODUCTION_OUTPUT', 'ALL', 1000),
  ('TECH-CLEAN-ENERGY-V1', 'ENERGY_INPUT', 'ALL', -1000),
  ('TECH-FOOD-SCIENCE-V1', 'PRODUCTION_OUTPUT', 'FOOD', 1000),
  ('TECH-LOGISTICS-V1', 'SERVICE_CAPACITY', 'ALL', 500),
  ('TECH-RESEARCH-METHODS-V1', 'RESEARCH_CAPACITY', 'ALL', 500)
ON CONFLICT (technology_id, effect_type, target_key) DO NOTHING;
