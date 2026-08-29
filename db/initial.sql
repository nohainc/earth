-- EARTH PostgreSQL baseline, current through migration 074.
--
-- This is the canonical starting point for a NEW, empty development database.
-- AI agents: read this file and db/schema-manifest.json to understand the
-- current schema. Do not inspect or modify db/migrations/001–074 unless an
-- investigation explicitly requires historical context. New schema work MUST
-- start with db/migrations/075_<description>.sql (or the next higher number).
--
-- Run with psql so that \ir resolves the paths relative to this file:
--   psql "$DATABASE_URL" -f db/initial.sql
--
-- The included files remain immutable production history. This entry point is
-- intentionally a bootstrap script rather than a copy: it cannot drift from
-- the exact schema that production reached at migration 074.

\ir migrations/001_initial.sql
\ir migrations/002_earth_feature_schema.sql
\ir migrations/003_import_compatibility.sql
\ir migrations/004_correlation_key_compatibility.sql
\ir migrations/005_institution_dissolution.sql
\ir migrations/006_event_outbox.sql
\ir migrations/007_game_time_governance_windows.sql
\ir migrations/008_atomic_credit_transfer.sql
\ir migrations/009_market_order_escrow.sql
\ir migrations/010_market_order_escrow_zero_reservations.sql
\ir migrations/011_institution_credit_accounts.sql
\ir migrations/012_registry_credit_accounts.sql
\ir migrations/013_city_budget_accounts.sql
\ir migrations/014_recycling_idempotency.sql
\ir migrations/015_business_liquidation_idempotency.sql
\ir migrations/016_scheduler_readiness_heartbeat.sql
\ir migrations/017_initialize_scheduler_heartbeat.sql
\ir migrations/018_normalize_json_structures.sql
\ir migrations/019_drop_obsolete_json_columns.sql
\ir migrations/020_migrate_to_nano_markup_text.sql
\ir migrations/021_migrate_world_events_to_nano_markup.sql
\ir migrations/022_effective_genesis_and_simulation_offset.sql
\ir migrations/023_pantheon_cemetery_and_rebirth.sql
\ir migrations/024_communications_and_dispatch.sql
\ir migrations/025_allow_food_resource_balance.sql
\ir migrations/026_automated_supply_contracts_and_escrow.sql
\ir migrations/027_planetary_map_and_territory_concessions.sql
\ir migrations/028_dynasty_lineage_and_heirlooms.sql
\ir migrations/029_commodity_futures_and_candlestick_history.sql
\ir migrations/030_net_worth_snapshots_and_asset_history.sql
\ir migrations/031_auth_email_delivery_observability.sql
\ir migrations/032_social_gameplay.sql
\ir migrations/033_social_relationships_timeline.sql
\ir migrations/034_remove_planetary_map.sql
\ir migrations/035_ensure_components_market.sql
\ir migrations/036_components_market_history.sql
\ir migrations/037_continuous_engine_schema.sql
\ir migrations/038_seed_canonical_institutions.sql
\ir migrations/039_seed_market_catalog.sql
\ir migrations/040_enable_food_market.sql
\ir migrations/041_business_workforce.sql
\ir migrations/042_link_cities_to_corporations.sql
\ir migrations/043_corporation_shared_technology.sql
\ir migrations/044_enable_food_production_events.sql
\ir migrations/045_business_attribution_for_technology_licenses.sql
\ir migrations/046_business_technology_adoption.sql
\ir migrations/047_institution_charter_rules.sql
\ir migrations/048_corporation_membership_policy.sql
\ir migrations/049_community_management_and_roles.sql
\ir migrations/050_real_estate_and_municipal_labor.sql
\ir migrations/051_building_centric_urban_economy.sql
\ir migrations/052_patents_buildings_licensing_integration.sql
\ir migrations/053_harden_buildings_and_patents_canonical_schema.sql
\ir migrations/054_drop_legacy_building_columns.sql
\ir migrations/055_harden_building_accounting_and_constraints.sql
\ir migrations/056_civic_rankings_table.sql
\ir migrations/057_community_application_questions_and_reasons.sql
\ir migrations/058_fix_community_unique_constraints.sql
\ir migrations/059_rename_dynasties_to_houses.sql
\ir migrations/060_constitutional_rule_registry.sql
\ir migrations/061_restore_constitutional_statutes.sql
\ir migrations/062_seed_earth_constitution_values.sql
\ir migrations/063_earth_governance_baseline_and_rule_authority.sql
\ir migrations/064_membership_admission_rules.sql
\ir migrations/065_constitutional_succession_rules.sql
\ir migrations/066_constitutional_public_order_rules.sql
\ir migrations/067_business_tax_allocation_values.sql
\ir migrations/068_remove_social_initiatives.sql
\ir migrations/069_remove_machine_system.sql
\ir migrations/070_remove_patent_system.sql
\ir migrations/071_ai_recommendation_feedback.sql
\ir migrations/072_scheduler_tick_log.sql
\ir migrations/073_personal_life_maintenance.sql
\ir migrations/074_resource_first_life_maintenance.sql
