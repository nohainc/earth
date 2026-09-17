-- EARTH ACTIVE MIGRATION: V5 Building Catalog Alpha (11 families, Tiers 1-4)

-- 1. Deactivate old obsolete catalog items
UPDATE building_catalog
   SET active = FALSE
 WHERE id IN ('HOUSING-T1', 'DISTRICT-MODULE-T1', 'MATERIAL-FAB-T1', 'ENERGY-PLANT-T1', 'COMPONENT-FAB-T1', 'COMPUTE-FAB-T1', 'FOOD-FARM-T1');

-- 2. Insert the 11 V5 Building Families (Tiers 1-4)
INSERT INTO building_catalog (
  id, code, name, description, family_code, design_code, tier, category, ownership_scope, technology_domain,
  construction_credit_units, construction_minutes, operating_credit_units, service_type, service_capacity_units,
  slot_footprint, minimum_scale_capability, active, definition_version, research_credit_units, research_duration_game_days, economic_role
) VALUES
  -- 1. SOLAR MICROGRID (House ENERGY)
  ('SOLAR-MICROGRID-T1', 'solar_microgrid_t1', 'Solar Microgrid', 'Compact private generation and storage infrastructure providing distributed ENERGY production.', 'SOLAR_MICROGRID', 'standard', 1, 'COMMODITY', 'PRIVATE', 'ENERGY', 12000, 2880, 80, NULL, 0, 2, 'SCALE_NONE', TRUE, 'v5-alpha-1', 24000, 5, 'PRODUCER'),
  ('SOLAR-MICROGRID-T2', 'solar_microgrid_t2', 'Commercial Solar Array', 'Expanded commercial photovoltaic array with high-efficiency inverters.', 'SOLAR_MICROGRID', 'standard', 2, 'COMMODITY', 'PRIVATE', 'ENERGY', 30000, 4320, 168, NULL, 0, 4, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 60000, 7, 'PRODUCER'),
  ('SOLAR-MICROGRID-T3', 'solar_microgrid_t3', 'Industrial Solar Field', 'High-output industrial solar energy field with integrated energy buffers.', 'SOLAR_MICROGRID', 'standard', 3, 'COMMODITY', 'PRIVATE', 'ENERGY', 68000, 7200, 344, NULL, 0, 8, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 136000, 10, 'PRODUCER'),
  ('SOLAR-MICROGRID-T4', 'solar_microgrid_t4', 'Strategic Solar Complex', 'Civilization-tier concentrated photovoltaic power generation complex.', 'SOLAR_MICROGRID', 'standard', 4, 'COMMODITY', 'PRIVATE', 'ENERGY', 156000, 11520, 720, NULL, 0, 16, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 312000, 14, 'PRODUCER'),

  -- 2. VERTICAL FARM (House FOOD)
  ('VERTICAL-FARM-T1', 'vertical_farm_t1', 'Vertical Farm', 'Controlled-environment agricultural facility converting ENERGY and computation into reliable FOOD production.', 'VERTICAL_FARM', 'standard', 1, 'COMMODITY', 'PRIVATE', 'FOOD', 12500, 2880, 110, NULL, 0, 2, 'SCALE_NONE', TRUE, 'v5-alpha-1', 25000, 5, 'TRANSFORMER'),
  ('VERTICAL-FARM-T2', 'vertical_farm_t2', 'Commercial Hydroponic Facility', 'Commercial multi-tier aeroponic agricultural farm.', 'VERTICAL_FARM', 'standard', 2, 'COMMODITY', 'PRIVATE', 'FOOD', 31250, 4320, 231, NULL, 0, 4, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 62500, 7, 'TRANSFORMER'),
  ('VERTICAL-FARM-T3', 'vertical_farm_t3', 'Industrial Agronomic Complex', 'Automated high-yield biological food production factory.', 'VERTICAL_FARM', 'standard', 3, 'COMMODITY', 'PRIVATE', 'FOOD', 71250, 7200, 473, NULL, 0, 8, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 142500, 10, 'TRANSFORMER'),
  ('VERTICAL-FARM-T4', 'vertical_farm_t4', 'Strategic Biosphere Enclosure', 'Closed-loop ecological food synthesis dome with maximum food security.', 'VERTICAL_FARM', 'standard', 4, 'COMMODITY', 'PRIVATE', 'FOOD', 162500, 11520, 990, NULL, 0, 16, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 325000, 14, 'TRANSFORMER'),

  -- 3. MATERIALS RECOVERY WORKSHOP (House MATERIAL)
  ('MATERIALS-RECOVERY-T1', 'materials_recovery_t1', 'Materials Recovery Workshop', 'Small-scale recycling, reclamation and local processing facility producing Industrial MATERIAL.', 'MATERIALS_RECOVERY', 'standard', 1, 'COMMODITY', 'PRIVATE', 'MATERIAL', 11000, 2880, 120, NULL, 0, 2, 'SCALE_NONE', TRUE, 'v5-alpha-1', 22000, 5, 'TRANSFORMER'),
  ('MATERIALS-RECOVERY-T2', 'materials_recovery_t2', 'Commercial Reclamation Plant', 'Commercial secondary materials recovery and refining workshop.', 'MATERIALS_RECOVERY', 'standard', 2, 'COMMODITY', 'PRIVATE', 'MATERIAL', 27500, 4320, 252, NULL, 0, 4, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 55000, 7, 'TRANSFORMER'),
  ('MATERIALS-RECOVERY-T3', 'materials_recovery_t3', 'Industrial Processing Facility', 'Heavy industrial scrap separation and feedstock synthesis facility.', 'MATERIALS_RECOVERY', 'standard', 3, 'COMMODITY', 'PRIVATE', 'MATERIAL', 62700, 7200, 516, NULL, 0, 8, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 125400, 10, 'TRANSFORMER'),
  ('MATERIALS-RECOVERY-T4', 'materials_recovery_t4', 'Strategic Reclamation Hub', 'High-throughput strategic material synthesis and secondary refining complex.', 'MATERIALS_RECOVERY', 'standard', 4, 'COMMODITY', 'PRIVATE', 'MATERIAL', 143000, 11520, 1080, NULL, 0, 16, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 286000, 14, 'TRANSFORMER'),

  -- 4. PRECISION FABRICATION WORKSHOP (House COMPONENTS)
  ('PRECISION-FAB-T1', 'precision_fab_t1', 'Precision Fabrication Workshop', 'Manufacturing facility converting Industrial MATERIAL and ENERGY into precision COMPONENTS.', 'PRECISION_FABRICATION', 'standard', 1, 'COMMODITY', 'PRIVATE', 'COMPONENTS', 15000, 4320, 160, NULL, 0, 2, 'SCALE_NONE', TRUE, 'v5-alpha-1', 30000, 6, 'TRANSFORMER'),
  ('PRECISION-FAB-T2', 'precision_fab_t2', 'Commercial Machining Facility', 'Computerized numerical machining and electronic assembly facility.', 'PRECISION_FABRICATION', 'standard', 2, 'COMMODITY', 'PRIVATE', 'COMPONENTS', 37500, 6480, 336, NULL, 0, 4, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 75000, 9, 'TRANSFORMER'),
  ('PRECISION-FAB-T3', 'precision_fab_t3', 'Industrial Precision Works', 'Automated industrial robotics and component fabrication lines.', 'PRECISION_FABRICATION', 'standard', 3, 'COMMODITY', 'PRIVATE', 'COMPONENTS', 85500, 10800, 688, NULL, 0, 8, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 171000, 12, 'TRANSFORMER'),
  ('PRECISION-FAB-T4', 'precision_fab_t4', 'Strategic Manufacturing Center', 'Strategic precision manufacturing complex with advanced microfabrication.', 'PRECISION_FABRICATION', 'standard', 4, 'COMMODITY', 'PRIVATE', 'COMPONENTS', 195000, 17280, 1440, NULL, 0, 16, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 390000, 16, 'TRANSFORMER'),

  -- 5. COMPUTE CLUSTER (House COMPUTE)
  ('COMPUTE-CLUSTER-T1', 'compute_cluster_t1', 'Compute Cluster', 'High-density processing facility converting ENERGY and COMPONENT wear into tradable COMPUTE capacity.', 'COMPUTE_CLUSTER', 'standard', 1, 'COMMODITY', 'PRIVATE', 'COMPUTE', 17000, 4320, 190, NULL, 0, 2, 'SCALE_NONE', TRUE, 'v5-alpha-1', 34000, 6, 'TRANSFORMER'),
  ('COMPUTE-CLUSTER-T2', 'compute_cluster_t2', 'Commercial Data Processing Center', 'High-efficiency server bank providing commercial compute resources.', 'COMPUTE_CLUSTER', 'standard', 2, 'COMMODITY', 'PRIVATE', 'COMPUTE', 42500, 6480, 399, NULL, 0, 4, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 85000, 9, 'TRANSFORMER'),
  ('COMPUTE-CLUSTER-T3', 'compute_cluster_t3', 'Industrial Server Array', 'Cryo-cooled industrial computing farm with high throughput.', 'COMPUTE_CLUSTER', 'standard', 3, 'COMMODITY', 'PRIVATE', 'COMPUTE', 96900, 10800, 817, NULL, 0, 8, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 193800, 12, 'TRANSFORMER'),
  ('COMPUTE-CLUSTER-T4', 'compute_cluster_t4', 'Strategic Supercompute Complex', 'Planetary-scale quantum and neural computation architecture.', 'COMPUTE_CLUSTER', 'standard', 4, 'COMMODITY', 'PRIVATE', 'COMPUTE', 221000, 17280, 1710, NULL, 0, 16, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 442000, 16, 'TRANSFORMER'),

  -- 6. DATA SERVICES STUDIO (House CONNECTIVITY)
  ('DATA-SERVICES-T1', 'data_services_studio_t1', 'Data Services Studio', 'Commercial communications, analytics and data-services operation consuming ENERGY and COMPUTE to provide CONNECTIVITY.', 'DATA_SERVICES_STUDIO', 'standard', 1, 'SERVICE', 'PRIVATE', 'CONNECTIVITY', 10000, 2880, 120, 'CONNECTIVITY', 8, 1, 'SCALE_NONE', TRUE, 'v5-alpha-1', 20000, 5, 'SERVICE'),
  ('DATA-SERVICES-T2', 'data_services_studio_t2', 'Commercial Network Node', 'High-speed routing and local data relay station.', 'DATA_SERVICES_STUDIO', 'standard', 2, 'SERVICE', 'PRIVATE', 'CONNECTIVITY', 25000, 4320, 252, 'CONNECTIVITY', 18, 2, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 50000, 7, 'SERVICE'),
  ('DATA-SERVICES-T3', 'data_services_studio_t3', 'Regional Communications Hub', 'Regional telecom gateway providing dense low-latency connectivity.', 'DATA_SERVICES_STUDIO', 'standard', 3, 'SERVICE', 'PRIVATE', 'CONNECTIVITY', 57000, 7200, 516, 'CONNECTIVITY', 40, 4, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 114000, 10, 'SERVICE'),
  ('DATA-SERVICES-T4', 'data_services_studio_t4', 'Strategic Telemetry Center', 'Strategic orbital uplink and global data routing nerve-center.', 'DATA_SERVICES_STUDIO', 'standard', 4, 'SERVICE', 'PRIVATE', 'CONNECTIVITY', 130000, 11520, 1080, 'CONNECTIVITY', 88, 8, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 260000, 14, 'SERVICE'),

  -- 7. COMMUNITY CLINIC (House HEALTH)
  ('COMMUNITY-CLINIC-T1', 'community_clinic_t1', 'Community Clinic', 'Private medical service facility consuming FOOD, ENERGY, COMPONENTS and COMPUTE to provide HEALTH capacity.', 'COMMUNITY_CLINIC', 'standard', 1, 'SERVICE', 'PRIVATE', 'HEALTH', 16000, 2880, 220, 'HEALTH', 8, 2, 'SCALE_NONE', TRUE, 'v5-alpha-1', 32000, 5, 'SERVICE'),
  ('COMMUNITY-CLINIC-T2', 'community_clinic_t2', 'Commercial Health Center', 'Expanded outpatient medical center with surgical capabilities.', 'COMMUNITY_CLINIC', 'standard', 2, 'SERVICE', 'PRIVATE', 'HEALTH', 40000, 4320, 462, 'HEALTH', 18, 4, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 80000, 7, 'SERVICE'),
  ('COMMUNITY-CLINIC-T3', 'community_clinic_t3', 'Regional Medical Center', 'Full-service regional hospital with intensive care and life support.', 'COMMUNITY_CLINIC', 'standard', 3, 'SERVICE', 'PRIVATE', 'HEALTH', 91200, 7200, 946, 'HEALTH', 40, 8, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 182400, 10, 'SERVICE'),
  ('COMMUNITY-CLINIC-T4', 'community_clinic_t4', 'Advanced Healthcare Pavilion', 'Advanced biomedical research hospital with regenerative therapies.', 'COMMUNITY_CLINIC', 'standard', 4, 'SERVICE', 'PRIVATE', 'HEALTH', 208000, 11520, 1980, 'HEALTH', 88, 16, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 416000, 14, 'SERVICE'),

  -- 8. EXTRACTION & REFINING COMPLEX (Corporation MATERIAL)
  ('EXTRACTION-REFINING-T1', 'extraction_refining_complex_t1', 'Extraction & Refining Complex', 'Large-scale Corporation primary material extraction and industrial smelting facility.', 'EXTRACTION_REFINING_COMPLEX', 'standard', 1, 'COMMODITY', 'PUBLIC', 'MATERIAL', 70000, 7200, 800, NULL, 0, 5, 'SCALE_NONE', TRUE, 'v5-alpha-1', 140000, 8, 'TRANSFORMER'),
  ('EXTRACTION-REFINING-T2', 'extraction_refining_complex_t2', 'Expanded Extraction Complex', 'Heavy open-pit and subterranean primary raw material extraction plant.', 'EXTRACTION_REFINING_COMPLEX', 'standard', 2, 'COMMODITY', 'PUBLIC', 'MATERIAL', 175000, 10800, 1680, NULL, 0, 10, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 350000, 11, 'TRANSFORMER'),
  ('EXTRACTION-REFINING-T3', 'extraction_refining_complex_t3', 'Industrial Mining Consortium', 'Highly automated primary mineral and chemical refining complex.', 'EXTRACTION_REFINING_COMPLEX', 'standard', 3, 'COMMODITY', 'PUBLIC', 'MATERIAL', 399000, 18000, 3440, NULL, 0, 20, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 798000, 15, 'TRANSFORMER'),
  ('EXTRACTION-REFINING-T4', 'extraction_refining_complex_t4', 'Strategic Megamine Complex', 'Civilization-scale robotic extraction and molecular metallurgical synthesis foundry.', 'EXTRACTION_REFINING_COMPLEX', 'standard', 4, 'COMMODITY', 'PUBLIC', 'MATERIAL', 910000, 28800, 7200, NULL, 0, 40, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 1820000, 20, 'TRANSFORMER'),

  -- 9. CIVIC DATA NETWORK (Corporation CONNECTIVITY)
  ('CIVIC-DATA-T1', 'civic_data_network_t1', 'Civic Data Network', 'Municipal telecommunications network ensuring high CONNECTIVITY service for member Houses.', 'CIVIC_DATA_NETWORK', 'standard', 1, 'SERVICE', 'PUBLIC', 'CONNECTIVITY', 50000, 5760, 500, 'CONNECTIVITY', 100, 3, 'SCALE_NONE', TRUE, 'v5-alpha-1', 100000, 7, 'INFRASTRUCTURE'),
  ('CIVIC-DATA-T2', 'civic_data_network_t2', 'Municipal Backbone Network', 'Metropolitan fiber and satellite network backbone.', 'CIVIC_DATA_NETWORK', 'standard', 2, 'SERVICE', 'PUBLIC', 'CONNECTIVITY', 125000, 8640, 1050, 'CONNECTIVITY', 230, 6, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 250000, 10, 'INFRASTRUCTURE'),
  ('CIVIC-DATA-T3', 'civic_data_network_t3', 'Regional Mesh Infrastructure', 'High-bandwidth regional communications grid with failover routing.', 'CIVIC_DATA_NETWORK', 'standard', 3, 'SERVICE', 'PUBLIC', 'CONNECTIVITY', 285000, 14400, 2150, 'CONNECTIVITY', 500, 12, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 570000, 14, 'INFRASTRUCTURE'),
  ('CIVIC-DATA-T4', 'civic_data_network_t4', 'Civilization Planetary Array', 'Global orbital constellation providing planetary-wide seamless connectivity.', 'CIVIC_DATA_NETWORK', 'standard', 4, 'SERVICE', 'PUBLIC', 'CONNECTIVITY', 650000, 23040, 4500, 'CONNECTIVITY', 1100, 24, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 1300000, 18, 'INFRASTRUCTURE'),

  -- 10. PUBLIC MEDICAL CENTER (Corporation HEALTH)
  ('PUBLIC-MEDICAL-T1', 'public_medical_center_t1', 'Public Medical Center', 'Comprehensive Corporation hospital providing public HEALTH service to member Houses.', 'PUBLIC_MEDICAL_CENTER', 'standard', 1, 'SERVICE', 'PUBLIC', 'HEALTH', 60000, 7200, 650, 'HEALTH', 100, 4, 'SCALE_NONE', TRUE, 'v5-alpha-1', 120000, 8, 'INFRASTRUCTURE'),
  ('PUBLIC-MEDICAL-T2', 'public_medical_center_t2', 'District General Hospital', 'Major public medical center providing comprehensive inpatient care.', 'PUBLIC_MEDICAL_CENTER', 'standard', 2, 'SERVICE', 'PUBLIC', 'HEALTH', 150000, 10800, 1365, 'HEALTH', 230, 8, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 300000, 11, 'INFRASTRUCTURE'),
  ('PUBLIC-MEDICAL-T3', 'public_medical_center_t3', 'Regional Medical Complex', 'Advanced trauma, specialized medicine, and biological research hospital.', 'PUBLIC_MEDICAL_CENTER', 'standard', 3, 'SERVICE', 'PUBLIC', 'HEALTH', 342000, 18000, 2795, 'HEALTH', 500, 16, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 684000, 15, 'INFRASTRUCTURE'),
  ('PUBLIC-MEDICAL-T4', 'public_medical_center_t4', 'Strategic Healthcare Sanctuary', 'Planetary-scale medical sanctuary ensuring full health and longevity coverage.', 'PUBLIC_MEDICAL_CENTER', 'standard', 4, 'SERVICE', 'PUBLIC', 'HEALTH', 780000, 28800, 5850, 'HEALTH', 1100, 32, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 1560000, 20, 'INFRASTRUCTURE'),

  -- 11. RESEARCH & EDUCATION CAMPUS (Corporation RESEARCH)
  ('RESEARCH-CAMPUS-T1', 'research_education_campus_t1', 'Research & Education Campus', 'Institutional research facility producing RESEARCH capacity from ENERGY, COMPONENTS and COMPUTE.', 'RESEARCH_EDUCATION_CAMPUS', 'standard', 1, 'RESEARCH', 'PUBLIC', 'RESEARCH', 65000, 7200, 700, 'RESEARCH', 50, 4, 'SCALE_NONE', TRUE, 'v5-alpha-1', 130000, 8, 'INFRASTRUCTURE'),
  ('RESEARCH-CAMPUS-T2', 'research_education_campus_t2', 'Institutional Research Institute', 'Advanced specialized laboratories expanding institutional research output.', 'RESEARCH_EDUCATION_CAMPUS', 'standard', 2, 'RESEARCH', 'PUBLIC', 'RESEARCH', 162500, 10800, 1470, 'RESEARCH', 115, 8, 'SCALE_COMMERCIAL', TRUE, 'v5-alpha-1', 325000, 11, 'INFRASTRUCTURE'),
  ('RESEARCH-CAMPUS-T3', 'research_education_campus_t3', 'Advanced Scientific Academy', 'Premier scientific institution pioneering technological frontier discoveries.', 'RESEARCH_EDUCATION_CAMPUS', 'standard', 3, 'RESEARCH', 'PUBLIC', 'RESEARCH', 370500, 18000, 3010, 'RESEARCH', 250, 16, 'SCALE_INDUSTRIAL', TRUE, 'v5-alpha-1', 741000, 15, 'INFRASTRUCTURE'),
  ('RESEARCH-CAMPUS-T4', 'research_education_campus_t4', 'Strategic Civilization Laboratory', 'Supreme civilization-scale theoretical and experimental scientific complex.', 'RESEARCH_EDUCATION_CAMPUS', 'standard', 4, 'RESEARCH', 'PUBLIC', 'RESEARCH', 845000, 28800, 6300, 'RESEARCH', 550, 32, 'SCALE_STRATEGIC', TRUE, 'v5-alpha-1', 1690000, 20, 'INFRASTRUCTURE')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  family_code = EXCLUDED.family_code,
  design_code = EXCLUDED.design_code,
  tier = EXCLUDED.tier,
  category = EXCLUDED.category,
  ownership_scope = EXCLUDED.ownership_scope,
  technology_domain = EXCLUDED.technology_domain,
  construction_credit_units = EXCLUDED.construction_credit_units,
  construction_minutes = EXCLUDED.construction_minutes,
  operating_credit_units = EXCLUDED.operating_credit_units,
  service_type = EXCLUDED.service_type,
  service_capacity_units = EXCLUDED.service_capacity_units,
  slot_footprint = EXCLUDED.slot_footprint,
  minimum_scale_capability = EXCLUDED.minimum_scale_capability,
  active = EXCLUDED.active,
  definition_version = EXCLUDED.definition_version,
  research_credit_units = EXCLUDED.research_credit_units,
  research_duration_game_days = EXCLUDED.research_duration_game_days,
  economic_role = EXCLUDED.economic_role;

-- 3. Populate building design life rules for all V5 buildings
INSERT INTO building_design_life_rules (catalog_id, design_life_days, overdue_burden_bps_per_day, maximum_burden_bps, rules_version)
SELECT id, 3650, 2, 15000, 'building-life-v5' FROM building_catalog WHERE active = TRUE
ON CONFLICT (catalog_id) DO UPDATE SET
  design_life_days = EXCLUDED.design_life_days,
  overdue_burden_bps_per_day = EXCLUDED.overdue_burden_bps_per_day,
  maximum_burden_bps = EXCLUDED.maximum_burden_bps;

-- 4. Populate building_catalog_resource_flows for all V5 buildings
-- Asset IDs: CREDIT = 1, MATERIAL = 2, COMPONENTS = 3, ENERGY = 4, COMPUTE = 5, FOOD = 6
WITH flows(catalog_id, asset_code, construction, input, output) AS (
  VALUES
    -- SOLAR MICROGRID (T1-T4)
    ('SOLAR-MICROGRID-T1', 'MATERIAL', 120, 0, 0),
    ('SOLAR-MICROGRID-T1', 'COMPONENTS', 12, 0, 0),
    ('SOLAR-MICROGRID-T1', 'COMPUTE', 5, 0, 0),
    ('SOLAR-MICROGRID-T1', 'ENERGY', 0, 0, 5),

    ('SOLAR-MICROGRID-T2', 'MATERIAL', 300, 0, 0),
    ('SOLAR-MICROGRID-T2', 'COMPONENTS', 30, 0, 0),
    ('SOLAR-MICROGRID-T2', 'COMPUTE', 12, 0, 0),
    ('SOLAR-MICROGRID-T2', 'ENERGY', 0, 0, 12),

    ('SOLAR-MICROGRID-T3', 'MATERIAL', 680, 0, 0),
    ('SOLAR-MICROGRID-T3', 'COMPONENTS', 68, 0, 0),
    ('SOLAR-MICROGRID-T3', 'COMPUTE', 28, 0, 0),
    ('SOLAR-MICROGRID-T3', 'ENERGY', 0, 0, 25),

    ('SOLAR-MICROGRID-T4', 'MATERIAL', 1560, 0, 0),
    ('SOLAR-MICROGRID-T4', 'COMPONENTS', 156, 0, 0),
    ('SOLAR-MICROGRID-T4', 'COMPUTE', 65, 0, 0),
    ('SOLAR-MICROGRID-T4', 'ENERGY', 0, 0, 55),

    -- VERTICAL FARM (T1-T4)
    ('VERTICAL-FARM-T1', 'MATERIAL', 120, 0, 0),
    ('VERTICAL-FARM-T1', 'COMPONENTS', 10, 0, 0),
    ('VERTICAL-FARM-T1', 'COMPUTE', 10, 1, 0),
    ('VERTICAL-FARM-T1', 'ENERGY', 0, 1, 0),
    ('VERTICAL-FARM-T1', 'FOOD', 0, 0, 4),

    ('VERTICAL-FARM-T2', 'MATERIAL', 300, 0, 0),
    ('VERTICAL-FARM-T2', 'COMPONENTS', 25, 0, 0),
    ('VERTICAL-FARM-T2', 'COMPUTE', 25, 2, 0),
    ('VERTICAL-FARM-T2', 'ENERGY', 0, 2, 0),
    ('VERTICAL-FARM-T2', 'FOOD', 0, 0, 9),

    ('VERTICAL-FARM-T3', 'MATERIAL', 684, 0, 0),
    ('VERTICAL-FARM-T3', 'COMPONENTS', 57, 0, 0),
    ('VERTICAL-FARM-T3', 'COMPUTE', 57, 4, 0),
    ('VERTICAL-FARM-T3', 'ENERGY', 0, 5, 0),
    ('VERTICAL-FARM-T3', 'FOOD', 0, 0, 20),

    ('VERTICAL-FARM-T4', 'MATERIAL', 1560, 0, 0),
    ('VERTICAL-FARM-T4', 'COMPONENTS', 130, 0, 0),
    ('VERTICAL-FARM-T4', 'COMPUTE', 130, 8, 0),
    ('VERTICAL-FARM-T4', 'ENERGY', 0, 10, 0),
    ('VERTICAL-FARM-T4', 'FOOD', 0, 0, 44),

    -- MATERIALS RECOVERY WORKSHOP (T1-T4)
    ('MATERIALS-RECOVERY-T1', 'MATERIAL', 80, 0, 3),
    ('MATERIALS-RECOVERY-T1', 'COMPONENTS', 8, 0, 0),
    ('MATERIALS-RECOVERY-T1', 'COMPUTE', 5, 1, 0),
    ('MATERIALS-RECOVERY-T1', 'ENERGY', 0, 2, 0),

    ('MATERIALS-RECOVERY-T2', 'MATERIAL', 200, 0, 6),
    ('MATERIALS-RECOVERY-T2', 'COMPONENTS', 20, 0, 0),
    ('MATERIALS-RECOVERY-T2', 'COMPUTE', 12, 2, 0),
    ('MATERIALS-RECOVERY-T2', 'ENERGY', 0, 3, 0),

    ('MATERIALS-RECOVERY-T3', 'MATERIAL', 456, 0, 13),
    ('MATERIALS-RECOVERY-T3', 'COMPONENTS', 45, 0, 0),
    ('MATERIALS-RECOVERY-T3', 'COMPUTE', 28, 4, 0),
    ('MATERIALS-RECOVERY-T3', 'ENERGY', 0, 7, 0),

    ('MATERIALS-RECOVERY-T4', 'MATERIAL', 1040, 0, 28),
    ('MATERIALS-RECOVERY-T4', 'COMPONENTS', 104, 0, 0),
    ('MATERIALS-RECOVERY-T4', 'COMPUTE', 65, 8, 0),
    ('MATERIALS-RECOVERY-T4', 'ENERGY', 0, 15, 0),

    -- PRECISION FABRICATION WORKSHOP (T1-T4)
    ('PRECISION-FAB-T1', 'MATERIAL', 160, 2, 0),
    ('PRECISION-FAB-T1', 'COMPONENTS', 20, 0, 4),
    ('PRECISION-FAB-T1', 'COMPUTE', 15, 0, 0),
    ('PRECISION-FAB-T1', 'ENERGY', 0, 2, 0),

    ('PRECISION-FAB-T2', 'MATERIAL', 400, 4, 0),
    ('PRECISION-FAB-T2', 'COMPONENTS', 50, 0, 8),
    ('PRECISION-FAB-T2', 'COMPUTE', 37, 0, 0),
    ('PRECISION-FAB-T2', 'ENERGY', 0, 4, 0),

    ('PRECISION-FAB-T3', 'MATERIAL', 912, 7, 0),
    ('PRECISION-FAB-T3', 'COMPONENTS', 114, 0, 18),
    ('PRECISION-FAB-T3', 'COMPUTE', 85, 0, 0),
    ('PRECISION-FAB-T3', 'ENERGY', 0, 7, 0),

    ('PRECISION-FAB-T4', 'MATERIAL', 2080, 15, 0),
    ('PRECISION-FAB-T4', 'COMPONENTS', 260, 0, 40),
    ('PRECISION-FAB-T4', 'COMPUTE', 195, 0, 0),
    ('PRECISION-FAB-T4', 'ENERGY', 0, 15, 0),

    -- COMPUTE CLUSTER (T1-T4)
    ('COMPUTE-CLUSTER-T1', 'MATERIAL', 180, 0, 0),
    ('COMPUTE-CLUSTER-T1', 'COMPONENTS', 30, 1, 0),
    ('COMPUTE-CLUSTER-T1', 'COMPUTE', 20, 0, 5),
    ('COMPUTE-CLUSTER-T1', 'ENERGY', 0, 3, 0),

    ('COMPUTE-CLUSTER-T2', 'MATERIAL', 450, 0, 0),
    ('COMPUTE-CLUSTER-T2', 'COMPONENTS', 75, 1, 0),
    ('COMPUTE-CLUSTER-T2', 'COMPUTE', 50, 0, 12),
    ('COMPUTE-CLUSTER-T2', 'ENERGY', 0, 6, 0),

    ('COMPUTE-CLUSTER-T3', 'MATERIAL', 1026, 0, 0),
    ('COMPUTE-CLUSTER-T3', 'COMPONENTS', 171, 2, 0),
    ('COMPUTE-CLUSTER-T3', 'COMPUTE', 114, 0, 25),
    ('COMPUTE-CLUSTER-T3', 'ENERGY', 0, 13, 0),

    ('COMPUTE-CLUSTER-T4', 'MATERIAL', 2340, 0, 0),
    ('COMPUTE-CLUSTER-T4', 'COMPONENTS', 390, 3, 0),
    ('COMPUTE-CLUSTER-T4', 'COMPUTE', 260, 0, 55),
    ('COMPUTE-CLUSTER-T4', 'ENERGY', 0, 27, 0),

    -- DATA SERVICES STUDIO (T1-T4)
    ('DATA-SERVICES-T1', 'MATERIAL', 90, 0, 0),
    ('DATA-SERVICES-T1', 'COMPONENTS', 15, 0, 0),
    ('DATA-SERVICES-T1', 'COMPUTE', 25, 1, 0),
    ('DATA-SERVICES-T1', 'ENERGY', 0, 1, 0),

    ('DATA-SERVICES-T2', 'MATERIAL', 225, 0, 0),
    ('DATA-SERVICES-T2', 'COMPONENTS', 37, 0, 0),
    ('DATA-SERVICES-T2', 'COMPUTE', 62, 2, 0),
    ('DATA-SERVICES-T2', 'ENERGY', 0, 2, 0),

    ('DATA-SERVICES-T3', 'MATERIAL', 513, 0, 0),
    ('DATA-SERVICES-T3', 'COMPONENTS', 85, 0, 0),
    ('DATA-SERVICES-T3', 'COMPUTE', 142, 3, 0),
    ('DATA-SERVICES-T3', 'ENERGY', 0, 4, 0),

    ('DATA-SERVICES-T4', 'MATERIAL', 1170, 0, 0),
    ('DATA-SERVICES-T4', 'COMPONENTS', 195, 0, 0),
    ('DATA-SERVICES-T4', 'COMPUTE', 325, 6, 0),
    ('DATA-SERVICES-T4', 'ENERGY', 0, 8, 0),

    -- COMMUNITY CLINIC (T1-T4)
    ('COMMUNITY-CLINIC-T1', 'MATERIAL', 150, 0, 0),
    ('COMMUNITY-CLINIC-T1', 'COMPONENTS', 25, 1, 0),
    ('COMMUNITY-CLINIC-T1', 'COMPUTE', 35, 1, 0),
    ('COMMUNITY-CLINIC-T1', 'ENERGY', 0, 1, 0),
    ('COMMUNITY-CLINIC-T1', 'FOOD', 0, 1, 0),

    ('COMMUNITY-CLINIC-T2', 'MATERIAL', 375, 0, 0),
    ('COMMUNITY-CLINIC-T2', 'COMPONENTS', 62, 1, 0),
    ('COMMUNITY-CLINIC-T2', 'COMPUTE', 87, 1, 0),
    ('COMMUNITY-CLINIC-T2', 'ENERGY', 0, 2, 0),
    ('COMMUNITY-CLINIC-T2', 'FOOD', 0, 1, 0),

    ('COMMUNITY-CLINIC-T3', 'MATERIAL', 855, 0, 0),
    ('COMMUNITY-CLINIC-T3', 'COMPONENTS', 142, 1, 0),
    ('COMMUNITY-CLINIC-T3', 'COMPUTE', 199, 2, 0),
    ('COMMUNITY-CLINIC-T3', 'ENERGY', 0, 5, 0),
    ('COMMUNITY-CLINIC-T3', 'FOOD', 0, 2, 0),

    ('COMMUNITY-CLINIC-T4', 'MATERIAL', 1950, 0, 0),
    ('COMMUNITY-CLINIC-T4', 'COMPONENTS', 325, 2, 0),
    ('COMMUNITY-CLINIC-T4', 'COMPUTE', 455, 4, 0),
    ('COMMUNITY-CLINIC-T4', 'ENERGY', 0, 9, 0),
    ('COMMUNITY-CLINIC-T4', 'FOOD', 0, 3, 0),

    -- EXTRACTION & REFINING COMPLEX (T1-T4)
    ('EXTRACTION-REFINING-T1', 'MATERIAL', 600, 0, 30),
    ('EXTRACTION-REFINING-T1', 'COMPONENTS', 150, 0, 0),
    ('EXTRACTION-REFINING-T1', 'COMPUTE', 100, 1, 0),
    ('EXTRACTION-REFINING-T1', 'ENERGY', 0, 12, 0),

    ('EXTRACTION-REFINING-T2', 'MATERIAL', 1500, 0, 69),
    ('EXTRACTION-REFINING-T2', 'COMPONENTS', 375, 0, 0),
    ('EXTRACTION-REFINING-T2', 'COMPUTE', 250, 2, 0),
    ('EXTRACTION-REFINING-T2', 'ENERGY', 0, 26, 0),

    ('EXTRACTION-REFINING-T3', 'MATERIAL', 3420, 0, 150),
    ('EXTRACTION-REFINING-T3', 'COMPONENTS', 855, 0, 0),
    ('EXTRACTION-REFINING-T3', 'COMPUTE', 570, 5, 0),
    ('EXTRACTION-REFINING-T3', 'ENERGY', 0, 54, 0),

    ('EXTRACTION-REFINING-T4', 'MATERIAL', 7800, 0, 330),
    ('EXTRACTION-REFINING-T4', 'COMPONENTS', 1950, 0, 0),
    ('EXTRACTION-REFINING-T4', 'COMPUTE', 1300, 9, 0),
    ('EXTRACTION-REFINING-T4', 'ENERGY', 0, 113, 0),

    -- CIVIC DATA NETWORK (T1-T4)
    ('CIVIC-DATA-T1', 'MATERIAL', 350, 0, 0),
    ('CIVIC-DATA-T1', 'COMPONENTS', 100, 1, 0),
    ('CIVIC-DATA-T1', 'COMPUTE', 300, 6, 0),
    ('CIVIC-DATA-T1', 'ENERGY', 0, 4, 0),

    ('CIVIC-DATA-T2', 'MATERIAL', 875, 0, 0),
    ('CIVIC-DATA-T2', 'COMPONENTS', 250, 1, 0),
    ('CIVIC-DATA-T2', 'COMPUTE', 750, 13, 0),
    ('CIVIC-DATA-T2', 'ENERGY', 0, 9, 0),

    ('CIVIC-DATA-T3', 'MATERIAL', 1995, 0, 0),
    ('CIVIC-DATA-T3', 'COMPONENTS', 570, 2, 0),
    ('CIVIC-DATA-T3', 'COMPUTE', 1710, 27, 0),
    ('CIVIC-DATA-T3', 'ENERGY', 0, 18, 0),

    ('CIVIC-DATA-T4', 'MATERIAL', 4550, 0, 0),
    ('CIVIC-DATA-T4', 'COMPONENTS', 1300, 4, 0),
    ('CIVIC-DATA-T4', 'COMPUTE', 3900, 56, 0),
    ('CIVIC-DATA-T4', 'ENERGY', 0, 38, 0),

    -- PUBLIC MEDICAL CENTER (T1-T4)
    ('PUBLIC-MEDICAL-T1', 'MATERIAL', 500, 0, 0),
    ('PUBLIC-MEDICAL-T1', 'COMPONENTS', 160, 1, 0),
    ('PUBLIC-MEDICAL-T1', 'COMPUTE', 220, 2, 0),
    ('PUBLIC-MEDICAL-T1', 'ENERGY', 0, 4, 0),
    ('PUBLIC-MEDICAL-T1', 'FOOD', 0, 2, 0),

    ('PUBLIC-MEDICAL-T2', 'MATERIAL', 1250, 0, 0),
    ('PUBLIC-MEDICAL-T2', 'COMPONENTS', 400, 2, 0),
    ('PUBLIC-MEDICAL-T2', 'COMPUTE', 550, 4, 0),
    ('PUBLIC-MEDICAL-T2', 'ENERGY', 0, 9, 0),
    ('PUBLIC-MEDICAL-T2', 'FOOD', 0, 4, 0),

    ('PUBLIC-MEDICAL-T3', 'MATERIAL', 2850, 0, 0),
    ('PUBLIC-MEDICAL-T3', 'COMPONENTS', 912, 4, 0),
    ('PUBLIC-MEDICAL-T3', 'COMPUTE', 1254, 9, 0),
    ('PUBLIC-MEDICAL-T3', 'ENERGY', 0, 18, 0),
    ('PUBLIC-MEDICAL-T3', 'FOOD', 0, 9, 0),

    ('PUBLIC-MEDICAL-T4', 'MATERIAL', 6500, 0, 0),
    ('PUBLIC-MEDICAL-T4', 'COMPONENTS', 2080, 8, 0),
    ('PUBLIC-MEDICAL-T4', 'COMPUTE', 2860, 19, 0),
    ('PUBLIC-MEDICAL-T4', 'ENERGY', 0, 38, 0),
    ('PUBLIC-MEDICAL-T4', 'FOOD', 0, 19, 0),

    -- RESEARCH & EDUCATION CAMPUS (T1-T4)
    ('RESEARCH-CAMPUS-T1', 'MATERIAL', 450, 0, 0),
    ('RESEARCH-CAMPUS-T1', 'COMPONENTS', 150, 1, 0),
    ('RESEARCH-CAMPUS-T1', 'COMPUTE', 350, 5, 0),
    ('RESEARCH-CAMPUS-T1', 'ENERGY', 0, 4, 0),

    ('RESEARCH-CAMPUS-T2', 'MATERIAL', 1125, 0, 0),
    ('RESEARCH-CAMPUS-T2', 'COMPONENTS', 375, 2, 0),
    ('RESEARCH-CAMPUS-T2', 'COMPUTE', 875, 11, 0),
    ('RESEARCH-CAMPUS-T2', 'ENERGY', 0, 9, 0),

    ('RESEARCH-CAMPUS-T3', 'MATERIAL', 2565, 0, 0),
    ('RESEARCH-CAMPUS-T3', 'COMPONENTS', 855, 4, 0),
    ('RESEARCH-CAMPUS-T3', 'COMPUTE', 1995, 23, 0),
    ('RESEARCH-CAMPUS-T3', 'ENERGY', 0, 18, 0),

    ('RESEARCH-CAMPUS-T4', 'MATERIAL', 5850, 0, 0),
    ('RESEARCH-CAMPUS-T4', 'COMPONENTS', 1950, 8, 0),
    ('RESEARCH-CAMPUS-T4', 'COMPUTE', 4550, 47, 0),
    ('RESEARCH-CAMPUS-T4', 'ENERGY', 0, 38, 0)
)
INSERT INTO building_catalog_resource_flows (catalog_id, asset_id, construction_units, operating_input_units, operating_output_units)
SELECT f.catalog_id, a.id, f.construction, f.input, f.output
  FROM flows f
  JOIN economic_assets a ON a.code = f.asset_code
ON CONFLICT (catalog_id, asset_id) DO UPDATE SET
  construction_units = EXCLUDED.construction_units,
  operating_input_units = EXCLUDED.operating_input_units,
  operating_output_units = EXCLUDED.operating_output_units;
