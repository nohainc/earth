import pg from 'pg';

const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const client = new pg.Client({ connectionString });

await client.connect();
try {
  const users = ['H-80ACE56E', 'H-D84A2C4D', 'H-0F879F1B'];
  for (const humanId of users) {
    const cityId = (await client.query('SELECT city_id FROM memberships WHERE human_id = $1 LIMIT 1', [humanId])).rows[0]?.city_id || 'CITY-0084';

    // 1. Add/ensure Solar Power Array (+50 energy/day)
    await client.query(`
      INSERT INTO buildings (
        id, name, building_type, owner_id, city_id, ownership_class,
        tier, status, condition, construction_progress,
        resource_output_type, resource_output_amount,
        upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
        daily_operating_credits, operating_policy, created_game_day
      ) VALUES (
        $1, 'Helios Solar Photovoltaic Farm', 'solar_power_plant', $2, $3, 'private',
        1, 'active', 100.0, 100.0,
        'energy', 50.0,
        0.0, 0.0, 0.5, 0.5, 0.1,
        10.0, 'balanced', 1
      ) ON CONFLICT (id) DO UPDATE SET status = 'active', condition = 100.0, resource_output_amount = 50.0;
    `, [`BLD-SOLAR-${humanId}`, humanId, cityId]);

    // 2. Add/ensure Automated Hydroponics (+40 food/day)
    await client.query(`
      INSERT INTO buildings (
        id, name, building_type, owner_id, city_id, ownership_class,
        tier, status, condition, construction_progress,
        resource_output_type, resource_output_amount,
        upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
        daily_operating_credits, operating_policy, created_game_day
      ) VALUES (
        $1, 'Vertical Hydroponic Dome', 'hydroponic_farm', $2, $3, 'private',
        1, 'active', 100.0, 100.0,
        'food', 40.0,
        2.0, 0.0, 0.5, 0.2, 0.1,
        15.0, 'balanced', 1
      ) ON CONFLICT (id) DO UPDATE SET status = 'active', condition = 100.0, resource_output_amount = 40.0;
    `, [`BLD-FARM-${humanId}`, humanId, cityId]);

    // Rebuild profile immediately
    const reb = await client.query('SELECT * FROM earth_rebuild_settlement_profile($1)', [humanId]);
    console.log(`Rebuilt profile for ${humanId}:`, reb.rows[0]);
  }
  console.log('Successfully seeded active production facilities for user accounts.');
} finally {
  await client.end();
}
