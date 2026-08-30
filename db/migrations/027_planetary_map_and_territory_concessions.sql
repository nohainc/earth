-- Migration 027: Interactive Planetary Regional Grid & Territory Concessions

CREATE TABLE IF NOT EXISTS planetary_regions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(140) NOT NULL,
    biome_type VARCHAR(64) NOT NULL,
    description TEXT NOT NULL,
    climate_status VARCHAR(64) NOT NULL DEFAULT 'optimal',
    base_solar_index NUMERIC(6, 2) NOT NULL DEFAULT 1.00,
    base_geothermal_index NUMERIC(6, 2) NOT NULL DEFAULT 1.00,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS territory_plots (
    id VARCHAR(64) PRIMARY KEY,
    region_id VARCHAR(64) NOT NULL REFERENCES planetary_regions(id) ON DELETE CASCADE,
    plot_name VARCHAR(140) NOT NULL,
    coord_x NUMERIC(6, 2) NOT NULL DEFAULT 0.00,
    coord_y NUMERIC(6, 2) NOT NULL DEFAULT 0.00,
    terrain_type VARCHAR(64) NOT NULL DEFAULT 'plains',
    primary_resource VARCHAR(32) NOT NULL DEFAULT 'energy',
    base_yield_rate NUMERIC(10, 2) NOT NULL DEFAULT 10.00,
    development_level INTEGER NOT NULL DEFAULT 1,
    max_level INTEGER NOT NULL DEFAULT 5,
    infrastructure_name VARCHAR(140) NOT NULL DEFAULT 'Standard Resource Rig',
    lease_holder_id VARCHAR(64) REFERENCES humans(id) ON DELETE SET NULL,
    daily_lease_fee NUMERIC(14, 2) NOT NULL DEFAULT 50.00,
    lease_expires_game_day INTEGER,
    accumulated_yield NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    last_harvested_game_day INTEGER,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS territory_plot_leases (
    id VARCHAR(64) PRIMARY KEY,
    plot_id VARCHAR(64) NOT NULL REFERENCES territory_plots(id) ON DELETE CASCADE,
    human_id VARCHAR(64) NOT NULL REFERENCES humans(id) ON DELETE CASCADE,
    corporation_id VARCHAR(64) REFERENCES corporations(id) ON DELETE SET NULL,
    starts_game_day INTEGER NOT NULL,
    expires_game_day INTEGER NOT NULL,
    total_paid NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS plot_yield_logs (
    id VARCHAR(64) PRIMARY KEY,
    plot_id VARCHAR(64) NOT NULL REFERENCES territory_plots(id) ON DELETE CASCADE,
    game_day INTEGER NOT NULL,
    resource_type VARCHAR(32) NOT NULL,
    amount_generated NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    fee_deducted NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_territory_plots_region ON territory_plots(region_id);
CREATE INDEX IF NOT EXISTS idx_territory_plots_lease_holder ON territory_plots(lease_holder_id);
CREATE INDEX IF NOT EXISTS idx_territory_plot_leases_plot ON territory_plot_leases(plot_id);
CREATE INDEX IF NOT EXISTS idx_plot_yield_logs_plot_day ON plot_yield_logs(plot_id, game_day);

-- Seed initial 6 Macro-Regions
INSERT INTO planetary_regions (id, name, biome_type, description, climate_status, base_solar_index, base_geothermal_index)
VALUES
('REG-PACIFIC-RIM', 'Pacific Rim Sprawl', 'coastal_megalopolis', 'Dense cybernetic coastal zones and high-throughput trade networks.', 'temperate', 1.15, 1.30),
('REG-SAHARAN-BASIN', 'Saharan Solar Basin', 'hyper_arid_desert', 'Massive photovoltaic and concentrated solar fields across the equator.', 'arid', 2.40, 0.85),
('REG-NORDIC-CRYO', 'Nordic Cryo Hub', 'sub_polar_tundra', 'Supercooled data clusters and geothermal power reservoirs in Scandinavian fjords.', 'frigid', 0.65, 1.80),
('REG-ATACAMA-CORRIDOR', 'Atacama Mineral Basin', 'high_altitude_plateau', 'Vast lithium salt flats and rare earth mineral extraction corridors.', 'arid', 1.85, 1.10),
('REG-EURO-ALPINE', 'Euro-Alpine Hydro Grid', 'alpine_montane', 'Hydroelectric cascade networks and high-precision quantum research labs.', 'temperate', 1.00, 1.05),
('REG-ORBITAL-RING', 'Low Orbit Tether Array', 'orbital_exosphere', 'Space elevator tether nodes and zero-gravity micro-fabrication platforms.', 'vacuum', 2.80, 0.00)
ON CONFLICT (id) DO NOTHING;

-- Seed initial Territory Plots
INSERT INTO territory_plots (id, region_id, plot_name, coord_x, coord_y, terrain_type, primary_resource, base_yield_rate, development_level, infrastructure_name, daily_lease_fee)
VALUES
('PLOT-PAC-01', 'REG-PACIFIC-RIM', 'Neo-Tokyo High-Bay Terminal', 139.69, 35.68, 'coastal', 'compute', 25.00, 2, 'Quantum Relay Server Bank', 75.00),
('PLOT-PAC-02', 'REG-PACIFIC-RIM', 'Yokohama Deepwater Dock', 139.63, 35.44, 'marine', 'energy', 30.00, 1, 'Tidal Surge Generator', 60.00),
('PLOT-PAC-03', 'REG-PACIFIC-RIM', 'Kanto Inland Fabrication Dome', 139.50, 35.90, 'urban', 'material', 20.00, 1, 'Automated Component Foundry', 50.00),
('PLOT-PAC-04', 'REG-PACIFIC-RIM', 'Fuji Geothermal Vent', 138.72, 35.36, 'volcanic', 'energy', 45.00, 3, 'Magma Tap Turbine', 120.00),

('PLOT-SAH-01', 'REG-SAHARAN-BASIN', 'Ksar Ghilane Mirror Array', 9.63, 32.98, 'dunes', 'energy', 60.00, 2, 'Concentrated Solar Tower', 90.00),
('PLOT-SAH-02', 'REG-SAHARAN-BASIN', 'Ahaggar High-Altitude Collector', 5.52, 23.28, 'rocky_desert', 'energy', 75.00, 3, 'Photovoltaic Glassfield', 140.00),
('PLOT-SAH-03', 'REG-SAHARAN-BASIN', 'Oasis Aeroponic Farm Ring', 8.12, 28.50, 'oasis', 'food', 35.00, 1, 'Deep Aquifer Biome Dome', 70.00),
('PLOT-SAH-04', 'REG-SAHARAN-BASIN', 'Reggane Silicon Quarry', 0.17, 26.71, 'gravel_desert', 'material', 30.00, 1, 'Silica Harvester Array', 65.00),

('PLOT-NOR-01', 'REG-NORDIC-CRYO', 'Svalbard Deep Glacial Vault', 15.46, 78.22, 'permafrost', 'compute', 50.00, 2, 'Sub-Zero Server Vault', 85.00),
('PLOT-NOR-02', 'REG-NORDIC-CRYO', 'Bergen Fjord Hydro Station', 5.32, 60.39, 'fjord', 'energy', 40.00, 2, 'Cascading Hydro Generator', 80.00),
('PLOT-NOR-03', 'REG-NORDIC-CRYO', 'Kiruna Sub-Crust Magnetite Mine', 20.22, 67.85, 'mountain', 'material', 55.00, 3, 'Heavy Bore Excavator', 110.00),
('PLOT-NOR-04', 'REG-NORDIC-CRYO', 'Tromsø Magnetic Observatory', 18.95, 69.64, 'arctic', 'compute', 30.00, 1, 'Aurora Sensor Cluster', 60.00),

('PLOT-ATA-01', 'REG-ATACAMA-CORRIDOR', 'Salar de Atacama Brine Fields', -68.25, -23.50, 'salt_flat', 'material', 70.00, 3, 'Lithium Evaporation Pan Array', 130.00),
('PLOT-ATA-02', 'REG-ATACAMA-CORRIDOR', 'Chajnantor High Sensor Array', -67.75, -23.02, 'high_altitude', 'compute', 40.00, 2, 'Sub-Millimeter Array Terminal', 90.00),
('PLOT-ATA-03', 'REG-ATACAMA-CORRIDOR', 'Antofagasta Coastal Smelter', -70.40, -23.65, 'coastal', 'material', 35.00, 1, 'Plasma Smelting Complex', 75.00),
('PLOT-ATA-04', 'REG-ATACAMA-CORRIDOR', 'Domeykos Solar Corridor', -69.10, -24.80, 'rocky_desert', 'energy', 50.00, 2, 'High-Irradiance PV Array', 95.00),

('PLOT-EUR-01', 'REG-EURO-ALPINE', 'Geneva Quantum Collider Hub', 6.14, 46.20, 'urban', 'compute', 45.00, 2, 'Sub-Atomic Accelerator Tap', 100.00),
('PLOT-EUR-02', 'REG-EURO-ALPINE', 'Rhone Valley Hydro Cascade', 7.36, 46.23, 'valley', 'energy', 35.00, 1, 'Alpine Reservoir Dam', 70.00),
('PLOT-EUR-03', 'REG-EURO-ALPINE', 'Bavarian Synthetic Food Silos', 11.58, 48.13, 'plains', 'food', 40.00, 2, 'Cellular Agriculture Facility', 80.00),
('PLOT-EUR-04', 'REG-EURO-ALPINE', 'Ruhr Automated Metal Foundry', 7.01, 51.45, 'industrial', 'material', 45.00, 2, 'Recycled Alloy Forge', 90.00),

('PLOT-ORB-01', 'REG-ORBITAL-RING', 'Quito Space Elevator Anchor', -78.46, -0.18, 'equatorial_peak', 'energy', 80.00, 3, 'Carbon Nanotube Power Link', 180.00),
('PLOT-ORB-02', 'REG-ORBITAL-RING', 'Kilimanjaro Sky Hook Station', 37.35, -3.06, 'equatorial_peak', 'material', 65.00, 2, 'Orbital Freight Launcher', 150.00),
('PLOT-ORB-03', 'REG-ORBITAL-RING', 'Zenith Zero-G Fabrication Ring', 0.00, 0.00, 'orbital', 'material', 90.00, 4, 'Microgravity Crucible', 220.00),
('PLOT-ORB-04', 'REG-ORBITAL-RING', 'Solar Lagrange Concentrator', 0.00, 0.00, 'orbital', 'energy', 100.00, 4, 'Orbital Microwave Emitter', 250.00)
ON CONFLICT (id) DO NOTHING;
