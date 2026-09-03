-- Migration 101: immutable Tier 1 catalog foundation.
-- Resource-vector order: credits, energy, food, materials, components, compute.

ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS effects JSONB NOT NULL DEFAULT '{}';
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS building_role TEXT NOT NULL DEFAULT 'production';
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS is_original BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS dividend_share_percent NUMERIC(5,2);

CREATE OR REPLACE FUNCTION earth_catalog_value(resource_values JSONB, index_pos INTEGER)
RETURNS NUMERIC LANGUAGE SQL IMMUTABLE AS $$
  SELECT COALESCE((resource_values ->> (index_pos - 1))::numeric, 0)
$$;

CREATE TEMP TABLE earth_tier1_catalog (
  id TEXT PRIMARY KEY, building_type TEXT NOT NULL, name TEXT NOT NULL,
  category TEXT NOT NULL, ownership_class TEXT NOT NULL, slot_footprint INTEGER NOT NULL,
  construction_days INTEGER NOT NULL, construction_minutes INTEGER NOT NULL,
  build_cost JSONB NOT NULL, daily_output JSONB NOT NULL, daily_upkeep JSONB NOT NULL,
  daily_operating JSONB NOT NULL, building_role TEXT NOT NULL, effects JSONB NOT NULL,
  description TEXT NOT NULL, dividend_share_percent NUMERIC(5,2)
);

INSERT INTO earth_tier1_catalog VALUES
('private-estate-plot','private-estate-plot','Private Estate Plot','commercial','private',0,1,1440,'[0,0,0,0,0,0]','[0,0,0,0,0,0]','[0,1,1,0,0,0.250]','[10,0,0,0,0,0]','housing','{"private_space":10}','Personal residential plot and private shelter.',NULL),
('residential-habitation-block','residential-habitation-block','Residential Habitation Block','commercial','private',2,2,2880,'[18000,0,120,80,20,5]','[0,0,0,0,0,0]','[0,1.2,0.8,0.1,0.1,0.1]','[45,0.1,0,0,0,0]','housing','{"private_space":6}','Higher-capacity private housing.',NULL),
('restaurant','restaurant','Bistro & Molecular Diner','commercial','private',1,1,1440,'[8500,0,0,120,0,0]','[620,0,0,0,0,0]','[0,0.5,0.3,0.05,0.05,0]','[120,0,0,0,0,0]','commerce','{}','Food-service business producing credits.',NULL),
('retail-store','retail-store','Retail Hardware Outlet','commercial','private',1,1,1440,'[9200,0,0,140,0,0]','[710,0,0,0,0,0]','[0,0.4,0,0.1,0.15,0.05]','[140,0,0,0,0,0]','commerce','{}','Consumer retail business producing credits.',NULL),
('server-farm','server-farm','Submerged Server Cluster','compute','private',2,2,2880,'[14500,0,0,180,20,10]','[0,0,0,0,0,5]','[0,3,0,0.05,0.2,0]','[180,0,0,0,0,0]','compute','{}','Private compute facility.',NULL),
('solar-array-complex','solar-array-complex','Photovoltaic Collector Field','energy','private',2,2,2880,'[10500,0,0,100,10,0]','[0,4.5,0,0,0,0]','[0,0,0,0.05,0.1,0]','[80,0,0,0,0,0]','energy','{}','Private solar generation facility.',NULL),
('vertical-farm','vertical-farm','Aeroponic Tower Array','food','private',2,2,2880,'[11200,0,0,120,10,10]','[0,0,3.8,0,0,0]','[0,1.2,0,0.1,0.1,0.1]','[110,0,0,0,0,0]','food','{}','Private vertical farm.',NULL),
('chemical-foundry','chemical-foundry','Catalytic Refining Cell','manufacturing','private',2,2,2880,'[14000,0,0,180,15,10]','[0,0,0,4.8,0,0]','[0,2.2,0,0.8,0.15,0.1]','[160,0,0,0,0,0]','materials','{}','Private materials facility.',NULL),
('fabrication-plant','fabrication-plant','CNC Milling Workshop','manufacturing','private',2,2,2880,'[13500,0,0,160,20,15]','[0,0,0,0,2.2,0]','[0,2,0,1.5,0.1,0.2]','[150,0,0,0,0,0]','components','{}','Private components facility.',NULL),
('medical-clinic','medical-clinic','Community Cyber-Clinic','medical','private',2,2,2880,'[16000,0,0,160,25,20]','[1200,0,0,0,0,0]','[0,1.5,0.2,0.1,0.25,0.5]','[220,0,0,0,0,0]','service','{"private_health_service":true}','Private medical service.',NULL),
('water-reclamation-plant','water-reclamation-plant','Water Reclamation Plant','energy','private',2,2,2880,'[12500,0,0,140,15,10]','[0,0,0,0,0,0]','[0,1.4,0,0.15,0.1,0.1]','[130,0,0,0,0,0]','utility','{"private_resource_loss_modifier":-0.08}','Reduces private resource waste.',NULL),
('battery-storage-array','battery-storage-array','Battery Storage Array','energy','private',1,2,2880,'[13000,0,0,100,30,5]','[0,0,0,0,0,0]','[0,0.1,0,0,0.1,0.05]','[90,0,0,0,0,0]','utility','{"private_energy_reliability":0.20}','Stores surplus private energy.',NULL),
('logistics-warehouse','logistics-warehouse','Logistics Warehouse','commercial','private',2,2,2880,'[11800,0,0,180,10,10]','[0,0,0,0,0,0]','[0,0,0,0.2,0.1,0.1]','[100,0,0,0,0,0]','logistics','{"private_operating_modifier":-0.04}','Reduces private logistics costs.',NULL),
('fabrication-laboratory','fabrication-laboratory','Fabrication Laboratory','manufacturing','private',3,3,4320,'[22000,0,0,260,60,80]','[0,0,0,0,3.5,0]','[0,3,0,2,0.3,1.2]','[260,0,0,0,0,0]','advanced_manufacturing','{}','Advanced component production.',NULL),
('data-services-studio','data-services-studio','Data Services Studio','compute','private',2,2,2880,'[19000,0,0,120,30,60]','[900,0,0,0,0,2.5]','[0,2,0,0.1,0.2,0.5]','[240,0,0,0,0,0]','data_services','{}','Private data and compute services.',NULL),
('biotech-greenhouse','biotech-greenhouse','Biotech Greenhouse','food','private',3,3,4320,'[21000,0,120,220,35,50]','[0,0,3.2,0.5,0,0]','[0,2.5,0.4,0.3,0.3,0.8]','[210,0,0,0,0,0]','biotechnology','{"medical_inputs":0.5}','Food and medical-input production.',NULL),
('recycling-cooperative','recycling-cooperative','Recycling Cooperative','manufacturing','private',2,2,2880,'[15000,0,0,180,25,20]','[0,0,0,2.4,1.2,0]','[0,1.5,0,0.5,0.2,0.2]','[140,0,0,0,0,0]','recycling','{}','Converts waste into materials and components.',NULL),
('transit-terminus','transit-terminus','Local Transit Interchange','civic','civic',4,4,5760,'[28000,0,0,400,80,20]','[0,0,0,0,0,0]','[0,2,0,0.2,0.2,0]','[260,0,0,0,0,0]','connectivity','{"connectivity_capacity":8}','Municipal transit infrastructure.',NULL),
('urban-district-module','urban-district-module','Standard Urban District Module','civic','civic',0,1,1440,'[50000,0,0,600,100,20]','[0,0,0,0,0,0]','[0,10,0,0.5,0.5,0]','[100,0,0,0,0,0]','capacity','{"city_space":20,"population_capacity":20}','City district and population expansion.',NULL),
('geothermal-grid','geothermal-grid','Deep Magmatic Well Tap','energy','civic',3,3,4320,'[32000,0,0,300,60,20]','[0,14,0,0,0,0]','[0,0,0,0.2,0.4,0.2]','[300,0,0,0,0,0]','energy','{"energy_capacity":20}','Municipal geothermal energy.',NULL),
('municipal-medical-center','municipal-medical-center','Municipal Medical Center','medical','civic',4,4,5760,'[45000,0,80,400,100,120]','[0,0,0,0,0,0]','[0,4,1,0.3,0.8,1.2]','[450,0,0,0,0,0]','health','{"health_capacity":20,"population_capacity":5}','City medical capacity.',NULL),
('water-sanitation-authority','water-sanitation-authority','Water & Sanitation Authority','civic','civic',4,4,5760,'[38000,0,0,350,90,80]','[0,0,0,0,0,0]','[0,3,0,0.8,0.6,0.8]','[380,0,0,0,0,0]','health','{"health_capacity":12,"population_capacity":5}','Municipal sanitation infrastructure.',NULL),
('civic-housing-authority','civic-housing-authority','Civic Housing Authority','civic','civic',5,5,7200,'[55000,0,160,500,120,40]','[0,0,0,0,0,0]','[0,8,2,0.5,0.4,0.2]','[300,0,0,0,0,0]','housing','{"housing_capacity":40,"population_capacity":20}','Public housing capacity.',NULL),
('public-education-campus','public-education-campus','Public Education Campus','civic','civic',4,4,5760,'[42000,0,100,300,80,180]','[0,0,0,0,0,1]','[0,3,1,0.3,0.4,2]','[380,0,0,0,0,0]','education','{"workforce_quality":10,"research_capacity":5}','Public education and workforce development.',NULL),
('emergency-response-command','emergency-response-command','Emergency Response Command','civic','civic',3,3,4320,'[46000,0,0,380,120,140]','[0,2,0,0.5,0.8,1]','[350,0,0,0,0,0]','[0,0,0,0,0,0]','resilience','{"resilience":25}','City emergency and resilience services.',NULL),
('municipal-resource-exchange','municipal-resource-exchange','Municipal Resource Exchange','civic','civic',3,3,4320,'[36000,0,0,300,80,160]','[0,0,0,0,0,0]','[0,2,0,0.4,0.3,1.4]','[300,0,0,0,0,0]','logistics','{"city_transfer_loss_modifier":-0.15}','City resource-balancing infrastructure.',NULL),
('atmospheric-processing-station','atmospheric-processing-station','Atmospheric Processing Station','civic','civic',5,5,7200,'[52000,0,0,500,140,250]','[0,0,0,0,0,0]','[0,6,0,0.8,0.7,2.5]','[500,0,0,0,0,0]','environment','{"health_capacity":10,"resilience":10}','Environmental health infrastructure.',NULL),
('civic-data-network','civic-data-network','Civic Data Network','civic','civic',3,3,4320,'[40000,0,0,260,70,300]','[0,0,0,0,0,2]','[0,3,0,0.2,0.2,3]','[420,0,0,0,0,0]','connectivity','{"connectivity_capacity":20,"administration_efficiency":5}','City communications network.',NULL),
('public-food-reserve','public-food-reserve','Public Food Reserve','food','civic',3,3,4320,'[34000,0,300,300,60,60]','[0,0,6,0,0,0]','[0,1,0,0.5,0.2,0.5]','[180,0,0,0,0,0]','food_security','{"food_reserve":30}','Municipal food security reserve.',NULL),
('urban-climate-grid','urban-climate-grid','Urban Cooling and Climate Grid','energy','civic',5,5,7200,'[58000,0,0,550,140,180]','[0,0,0,0,0,0]','[0,8,0,0.8,0.6,2]','[520,0,0,0,0,0]','climate','{"energy_stress_modifier":-0.15,"health_capacity":8}','Urban climate and cooling infrastructure.',NULL),
('transit-hyperloop','transit-hyperloop','District Hyperloop Hub','civic','public_investment',3,3,4320,'[38000,0,0,500,100,60]','[3200,0,0,0,0,0]','[0,4,0,0.3,0.5,0.6]','[500,0,0,0,0,0]','regional_transport','{"connectivity_capacity":15}','Large inter-district transport project.',35),
('commercial-mall','commercial-mall','District Galleria Center','commercial','public_investment',4,4,5760,'[42000,0,0,550,90,80]','[4200,0,0,0,0,0]','[0,3.5,0.8,0.3,0.5,0.6]','[600,0,0,0,0,0]','regional_commerce','{"commerce_capacity":8}','Public commercial center.',35),
('orbital-spaceport','orbital-spaceport','Sub-Orbital Launch Complex','orbital','public_investment',6,6,8640,'[95000,0,0,1200,300,500]','[10500,0,0,0,0,0]','[0,10,1,1.2,1.5,2.5]','[1500,0,0,0,0,0]','strategic_orbital','{"strategic_connectivity":10}','Strategic space infrastructure.',35),
('municipal-power-exchange','municipal-power-exchange','Municipal Power Exchange','energy','public_investment',5,5,7200,'[90000,0,0,900,220,300]','[6000,18,0,0,0,0]','[0,5,0,0.5,0.8,2]','[900,0,0,0,0,0]','regional_energy','{"energy_capacity":50}','Large city power-distribution project.',35),
('planetary-freight-terminal','planetary-freight-terminal','Planetary Freight Terminal','commercial','public_investment',6,6,8640,'[80000,0,0,1000,250,240]','[5500,0,0,0,0,0]','[0,4,0,1,1,1.5]','[850,0,0,0,0,0]','regional_logistics','{"connectivity_capacity":20,"trade_capacity":10}','Large inter-city freight infrastructure.',35),
('regional-waterworks-consortium','regional-waterworks-consortium','Regional Waterworks Consortium','civic','public_investment',5,5,7200,'[85000,0,0,900,220,240]','[4800,0,0,0,0,0]','[0,5,0,1,1,1.5]','[800,0,0,0,0,0]','regional_utility','{"health_capacity":25,"population_capacity":20}','Regional water infrastructure.',35),
('orbital-communications-array','orbital-communications-array','Orbital Communications Array','orbital','public_investment',5,5,7200,'[110000,0,0,1000,280,700]','[7200,0,0,0,0,6]','[0,7,0,0.5,1.2,3]','[1200,0,0,0,0,0]','regional_connectivity','{"connectivity_capacity":35,"compute_capacity":10}','Orbital communications infrastructure.',35),
('medical-research-campus','medical-research-campus','Medical Research Campus','medical','public_investment',5,5,7200,'[100000,0,100,900,240,500]','[6500,0,0,0,0,3]','[0,6,1,0.8,1.2,2.5]','[1100,0,0,0,0,0]','regional_health','{"health_capacity":15,"research_capacity":10}','Large health and research complex.',35),
('advanced-materials-foundry','advanced-materials-foundry','Advanced Materials Foundry','manufacturing','public_investment',6,6,8640,'[105000,0,0,1200,300,400]','[7000,0,0,6,1.5,0]','[0,8,0,2,1.5,2.5]','[1100,0,0,0,0,0]','regional_industry','{"materials_capacity":8}','Large industrial materials project.',35),
('metropolitan-housing-trust','metropolitan-housing-trust','Metropolitan Housing Trust','civic','public_investment',6,6,8640,'[95000,0,250,1100,260,180]','[5200,0,0,0,0,0]','[0,6,2,1,1,1]','[900,0,0,0,0,0]','regional_housing','{"housing_capacity":60,"population_capacity":30}','Investor-funded metropolitan housing.',35),
('agricultural-reserve-network','agricultural-reserve-network','Agricultural Reserve Network','food','public_investment',5,5,7200,'[78000,0,500,800,160,180]','[4200,0,10,0,0,0]','[0,4,1,0.8,0.5,1]','[700,0,0,0,0,0]','regional_food','{"food_reserve":40}','Regional food-security infrastructure.',35),
('carbon-capture-atmosphere-works','carbon-capture-atmosphere-works','Carbon Capture and Atmosphere Works','energy','public_investment',5,5,7200,'[88000,0,0,900,220,350]','[4500,0,0,0,0,0]','[0,5,0,1,0.8,2]','[750,0,0,0,0,0]','regional_environment','{"resilience":20,"health_capacity":12}','Environmental infrastructure.',35),
('inter-city-data-exchange','inter-city-data-exchange','Inter-City Data Exchange','compute','public_investment',4,4,5760,'[92000,0,0,700,180,550]','[6000,0,0,0,0,8]','[0,6,0,0.5,1,3]','[1000,0,0,0,0,0]','regional_data','{"connectivity_capacity":30,"compute_capacity":10}','Inter-city data infrastructure.',35);

INSERT INTO building_catalog (
  id, building_type, name, tier, prev_catalog_id, next_catalog_id, category, ownership_class,
  slot_footprint, cost_credits, cost_energy, cost_food, cost_materials, cost_components, cost_compute,
  output_credits, output_energy, output_food, output_materials, output_components, output_compute,
  upkeep_credits, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
  operating_credits, operating_energy, operating_food, operating_materials, operating_components, operating_compute,
  description, construction_days, construction_minutes, is_active, research_project_id,
  effects, building_role, is_original, dividend_share_percent
)
SELECT id, building_type, name, 1, NULL, NULL, category, ownership_class, slot_footprint,
  earth_catalog_value(build_cost,1), earth_catalog_value(build_cost,2), earth_catalog_value(build_cost,3), earth_catalog_value(build_cost,4), earth_catalog_value(build_cost,5), earth_catalog_value(build_cost,6),
  earth_catalog_value(daily_output,1), earth_catalog_value(daily_output,2), earth_catalog_value(daily_output,3), earth_catalog_value(daily_output,4), earth_catalog_value(daily_output,5), earth_catalog_value(daily_output,6),
  earth_catalog_value(daily_upkeep,1), earth_catalog_value(daily_upkeep,2), earth_catalog_value(daily_upkeep,3), earth_catalog_value(daily_upkeep,4), earth_catalog_value(daily_upkeep,5), earth_catalog_value(daily_upkeep,6),
  earth_catalog_value(daily_operating,1), earth_catalog_value(daily_operating,2), earth_catalog_value(daily_operating,3), earth_catalog_value(daily_operating,4), earth_catalog_value(daily_operating,5), earth_catalog_value(daily_operating,6),
  description, construction_days, construction_minutes, true, NULL, effects, building_role, true, dividend_share_percent
FROM earth_tier1_catalog
ON CONFLICT (id) DO UPDATE SET
  building_type=EXCLUDED.building_type, name=EXCLUDED.name, tier=1, prev_catalog_id=NULL, next_catalog_id=NULL,
  category=EXCLUDED.category, ownership_class=EXCLUDED.ownership_class, slot_footprint=EXCLUDED.slot_footprint,
  cost_credits=EXCLUDED.cost_credits, cost_energy=EXCLUDED.cost_energy, cost_food=EXCLUDED.cost_food, cost_materials=EXCLUDED.cost_materials, cost_components=EXCLUDED.cost_components, cost_compute=EXCLUDED.cost_compute,
  output_credits=EXCLUDED.output_credits, output_energy=EXCLUDED.output_energy, output_food=EXCLUDED.output_food, output_materials=EXCLUDED.output_materials, output_components=EXCLUDED.output_components, output_compute=EXCLUDED.output_compute,
  upkeep_credits=EXCLUDED.upkeep_credits, upkeep_energy=EXCLUDED.upkeep_energy, upkeep_food=EXCLUDED.upkeep_food, upkeep_materials=EXCLUDED.upkeep_materials, upkeep_components=EXCLUDED.upkeep_components, upkeep_compute=EXCLUDED.upkeep_compute,
  operating_credits=EXCLUDED.operating_credits, operating_energy=EXCLUDED.operating_energy, operating_food=EXCLUDED.operating_food, operating_materials=EXCLUDED.operating_materials, operating_components=EXCLUDED.operating_components, operating_compute=EXCLUDED.operating_compute,
  description=EXCLUDED.description, construction_days=EXCLUDED.construction_days, construction_minutes=EXCLUDED.construction_minutes,
  is_active=true, research_project_id=NULL, effects=EXCLUDED.effects, building_role=EXCLUDED.building_role, is_original=true, dividend_share_percent=EXCLUDED.dividend_share_percent, updated_at=CURRENT_TIMESTAMP;

UPDATE buildings SET building_type='vertical-farm', catalog_id='vertical-farm-t1', name='Aeroponic Tower Array'
WHERE building_type='hydroponic_farm';
UPDATE buildings SET building_type='solar-array-complex', catalog_id='solar-array-complex-t1', name='Photovoltaic Collector Field'
WHERE building_type='solar_power_plant';

CREATE UNIQUE INDEX IF NOT EXISTS building_catalog_original_type_idx
  ON building_catalog(building_type) WHERE is_original=true AND tier=1;

CREATE OR REPLACE FUNCTION earth_prevent_original_catalog_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.is_original AND (
    NEW.building_type IS DISTINCT FROM OLD.building_type OR NEW.name IS DISTINCT FROM OLD.name OR
    NEW.category IS DISTINCT FROM OLD.category OR NEW.ownership_class IS DISTINCT FROM OLD.ownership_class OR
    NEW.slot_footprint IS DISTINCT FROM OLD.slot_footprint OR NEW.cost_credits IS DISTINCT FROM OLD.cost_credits OR
    NEW.cost_energy IS DISTINCT FROM OLD.cost_energy OR NEW.cost_food IS DISTINCT FROM OLD.cost_food OR
    NEW.cost_materials IS DISTINCT FROM OLD.cost_materials OR NEW.cost_components IS DISTINCT FROM OLD.cost_components OR
    NEW.cost_compute IS DISTINCT FROM OLD.cost_compute OR NEW.output_credits IS DISTINCT FROM OLD.output_credits OR
    NEW.output_energy IS DISTINCT FROM OLD.output_energy OR NEW.output_food IS DISTINCT FROM OLD.output_food OR
    NEW.output_materials IS DISTINCT FROM OLD.output_materials OR NEW.output_components IS DISTINCT FROM OLD.output_components OR
    NEW.output_compute IS DISTINCT FROM OLD.output_compute OR NEW.effects IS DISTINCT FROM OLD.effects
  ) THEN
    RAISE EXCEPTION 'Original Tier 1 building catalog records are immutable';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS building_catalog_original_immutable ON building_catalog;
CREATE TRIGGER building_catalog_original_immutable BEFORE UPDATE ON building_catalog FOR EACH ROW EXECUTE FUNCTION earth_prevent_original_catalog_mutation();
