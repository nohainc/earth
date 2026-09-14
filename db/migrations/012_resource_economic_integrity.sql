-- EARTH ACTIVE MIGRATION: final physical-economy integrity checks

CREATE OR REPLACE FUNCTION earth_resource_economic_integrity_report()
RETURNS TABLE(check_name TEXT, violation_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'every_tradable_resource_has_producer', COUNT(*) FROM economic_assets a
   WHERE a.asset_kind = 'RESOURCE' AND NOT EXISTS (
     SELECT 1 FROM building_catalog_resource_flows f JOIN building_catalog c ON c.id=f.catalog_id
      WHERE f.asset_id=a.id AND f.operating_output_units>0 AND c.ownership_scope='PRIVATE')
  UNION ALL SELECT 'every_resource_has_sink', COUNT(*) FROM economic_assets a
   WHERE a.asset_kind='RESOURCE' AND a.code<>'FOOD' AND NOT EXISTS (
     SELECT 1 FROM building_catalog_resource_flows f WHERE f.asset_id=a.id AND (f.operating_input_units>0 OR f.construction_units>0))
  UNION ALL SELECT 'compute_has_active_producer', CASE WHEN EXISTS (
     SELECT 1 FROM building_catalog_resource_flows f JOIN economic_assets a ON a.id=f.asset_id JOIN building_catalog c ON c.id=f.catalog_id
      WHERE a.code='COMPUTE' AND c.ownership_scope='PRIVATE' AND f.operating_output_units>0) THEN 0 ELSE 1 END
  UNION ALL SELECT 'food_maintenance_is_active', CASE WHEN to_regclass('personal_life_maintenance') IS NOT NULL THEN 0 ELSE 1 END
  UNION ALL SELECT 'construction_and_operating_inputs_are_independent', COUNT(*) FROM building_catalog_resource_flows
   WHERE construction_units<0 OR operating_input_units<0 OR operating_output_units<0
  UNION ALL SELECT 'private_producers_do_not_create_credit', COUNT(*) FROM building_catalog_resource_flows f JOIN building_catalog c ON c.id=f.catalog_id JOIN economic_assets a ON a.id=f.asset_id
   WHERE c.ownership_scope='PRIVATE' AND a.asset_kind='CREDIT' AND f.operating_output_units>0
  UNION ALL SELECT 'public_infrastructure_does_not_produce_resources', COUNT(*) FROM building_catalog_resource_flows f JOIN building_catalog c ON c.id=f.catalog_id JOIN economic_assets a ON a.id=f.asset_id
   WHERE c.ownership_scope='PUBLIC' AND a.asset_kind='RESOURCE' AND (f.construction_units>0 OR f.operating_input_units>0 OR f.operating_output_units>0)
  UNION ALL SELECT 'daily_house_consumption_within_opening_balance', COUNT(*) FROM house_resource_daily_flow
   WHERE consumption_units > opening_balance_units + transfer_in_units
  UNION ALL SELECT 'market_resource_transfers_balance', COUNT(*) FROM (
     SELECT t.id FROM economic_transactions t JOIN economic_entries e ON e.transaction_id=t.id
      WHERE t.transaction_kind='ASSET_TRANSFER' AND e.asset_id IN (SELECT id FROM economic_assets WHERE asset_kind='RESOURCE')
      GROUP BY t.id,e.asset_id HAVING SUM(e.delta_units)<>0) unbalanced
  UNION ALL SELECT 'resource_production_consumption_reconcile_globally', COUNT(*) FROM (
     SELECT t.id FROM economic_transactions t JOIN economic_entries e ON e.transaction_id=t.id
      WHERE t.transaction_kind IN ('RESOURCE_PRODUCTION','RESOURCE_CONSUMPTION') AND e.asset_id IN (SELECT id FROM economic_assets WHERE asset_kind='RESOURCE')
      GROUP BY t.id,e.asset_id HAVING SUM(e.delta_units)<>0) unreconciled;
$$;
