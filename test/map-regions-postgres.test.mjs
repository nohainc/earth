import test from 'node:test';
import assert from 'node:assert/strict';
import {
  listPlanetaryRegionsAndPlots,
  claimPlotLease,
  upgradePlotInfrastructure,
  harvestPlotYield,
} from '../cloudflare/src/map-regions-postgres.ts';

class FakePostgresRepository {
  constructor(initialData = {}) {
    this.data = {
      regions: [
        { id: 'REG-PACIFIC-RIM', name: 'Pacific Rim Sprawl', biome_type: 'coastal', climate_status: 'temperate', base_solar_index: '1.15', base_geothermal_index: '1.30' },
        { id: 'REG-SAHARAN-BASIN', name: 'Saharan Solar Basin', biome_type: 'desert', climate_status: 'arid', base_solar_index: '2.40', base_geothermal_index: '0.85' },
      ],
      plots: [
        {
          id: 'PLOT-PAC-01',
          region_id: 'REG-PACIFIC-RIM',
          plot_name: 'Neo-Tokyo High-Bay Terminal',
          coord_x: '139.69',
          coord_y: '35.68',
          terrain_type: 'coastal',
          primary_resource: 'compute',
          base_yield_rate: '25.00',
          development_level: 2,
          max_level: 5,
          infrastructure_name: 'Quantum Relay Server Bank',
          lease_holder_id: null,
          daily_lease_fee: '75.00',
          lease_expires_game_day: null,
          accumulated_yield: '0.00',
          last_harvested_game_day: null,
        },
        {
          id: 'PLOT-PAC-02',
          region_id: 'REG-PACIFIC-RIM',
          plot_name: 'Yokohama Deepwater Dock',
          coord_x: '139.63',
          coord_y: '35.44',
          terrain_type: 'marine',
          primary_resource: 'energy',
          base_yield_rate: '30.00',
          development_level: 1,
          max_level: 5,
          infrastructure_name: 'Tidal Surge Generator',
          lease_holder_id: 'H-0044',
          daily_lease_fee: '60.00',
          lease_expires_game_day: 214,
          accumulated_yield: '90.00',
          last_harvested_game_day: 180,
        },
      ],
      humans: [
        { id: 'H-0044', display_name: 'Amara Vance', life_status: 'active' },
        { id: 'H-0045', display_name: 'Dmitri Rostov', life_status: 'active' },
      ],
      account_balances: [
        { account_id: 'ACC-0044', owner_id: 'H-0044', currency: 'CREDIT', balance: '10000.00' },
        { account_id: 'ACC-0045', owner_id: 'H-0045', currency: 'CREDIT', balance: '5000.00' },
      ],
      resource_balances: [
        { owner_id: 'H-0044', resource: 'material', amount: '200.00' },
        { owner_id: 'H-0044', resource: 'compute', amount: '10.00' },
        { owner_id: 'H-0044', resource: 'energy', amount: '50.00' },
      ],
      leases: [],
      world_events: [],
      notifications: [],
      world_state: [{ id: 'WORLD', game_day: 184 }],
      ...initialData,
    };
  }

  async transaction(fn) {
    return fn(this);
  }

  async query(sql, params = []) {
    const trimmed = sql.trim();

    if (trimmed.startsWith('SELECT * FROM planetary_regions')) {
      return { rows: [...this.data.regions] };
    }

    if (trimmed.startsWith('SELECT tp.*, pr.name AS region_name')) {
      return {
        rows: this.data.plots.map((p) => {
          const r = this.data.regions.find((reg) => reg.id === p.region_id) || {};
          const h = this.data.humans.find((hum) => hum.id === p.lease_holder_id);
          return {
            ...p,
            region_name: r.name,
            biome_type: r.biome_type,
            climate_status: r.climate_status,
            lease_holder_name: h ? h.display_name : null,
          };
        }),
      };
    }

    if (trimmed.startsWith('SELECT id, life_status FROM humans')) {
      const h = this.data.humans.find((hum) => hum.id === params[0] && hum.life_status === 'active');
      return { rows: h ? [h] : [] };
    }

    if (trimmed.startsWith('SELECT * FROM territory_plots WHERE id = $1')) {
      const p = this.data.plots.find((plot) => plot.id === params[0]);
      return { rows: p ? [{ ...p }] : [] };
    }

    if (trimmed.startsWith("SELECT game_day FROM world_state WHERE id = 'WORLD'")) {
      return { rows: [...this.data.world_state] };
    }

    if (trimmed.includes('FROM account_balances WHERE owner_id = $1')) {
      const acc = this.data.account_balances.find((a) => a.owner_id === params[0] && a.currency === 'CREDIT');
      return { rows: acc ? [{ ...acc }] : [] };
    }

    if (trimmed.includes('FROM resource_balances WHERE owner_id = $1')) {
      const rb = this.data.resource_balances.find((r) => r.owner_id === params[0] && r.resource === 'material');
      return { rows: rb ? [{ ...rb }] : [] };
    }

    if (trimmed.startsWith('SELECT id, plot_id, expires_game_day, total_paid FROM territory_plot_leases')) {
      const l = this.data.leases.find((lease) => lease.id === params[0]);
      return { rows: l ? [l] : [] };
    }

    if (trimmed.startsWith('UPDATE account_balances SET balance = $1 WHERE account_id = $2')) {
      const acc = this.data.account_balances.find((a) => a.account_id === params[1]);
      if (acc) acc.balance = params[0];
      return { rowCount: 1 };
    }

    if (trimmed.startsWith('UPDATE territory_plots')) {
      const plotId = params[params.length - 1];
      const p = this.data.plots.find((plot) => plot.id === plotId);
      if (p) {
        if (trimmed.includes('lease_holder_id = $1')) {
          p.lease_holder_id = params[0];
          p.lease_expires_game_day = params[1];
        } else if (trimmed.includes('development_level = $1')) {
          p.development_level = params[0];
          p.base_yield_rate = params[1];
          p.infrastructure_name = params[2];
        } else if (trimmed.includes('accumulated_yield = 0.00')) {
          p.accumulated_yield = '0.00';
          p.last_harvested_game_day = params[0];
        }
      }
      return { rowCount: 1 };
    }

    if (trimmed.startsWith('INSERT INTO territory_plot_leases')) {
      this.data.leases.push({
        id: params[0],
        plot_id: params[1],
        human_id: params[2],
        starts_game_day: params[3],
        expires_game_day: params[4],
        total_paid: params[5],
        status: 'active',
      });
      return { rowCount: 1 };
    }

    if (trimmed.startsWith('INSERT INTO world_events')) {
      this.data.world_events.push({ id: params[0], game_day: params[1], details: params[2] });
      return { rowCount: 1 };
    }

    if (trimmed.startsWith('INSERT INTO notifications')) {
      this.data.notifications.push({ id: params[0], human_id: params[1], title: params[2], body: params[3] });
      return { rowCount: 1 };
    }

    if (trimmed.startsWith('UPDATE resource_balances SET amount = amount - $1')) {
      const rb = this.data.resource_balances.find((r) => r.owner_id === params[1] && r.resource === 'material');
      if (rb) rb.amount = String(Number(rb.amount) - Number(params[0]));
      return { rowCount: 1 };
    }

    if (trimmed.startsWith('INSERT INTO resource_balances')) {
      const ownerId = params[0];
      const resource = params[1];
      const amt = Number(params[2]);
      let rb = this.data.resource_balances.find((r) => r.owner_id === ownerId && r.resource === resource);
      if (rb) {
        rb.amount = String(Number(rb.amount) + amt);
      } else {
        this.data.resource_balances.push({ owner_id: ownerId, resource, amount: String(amt) });
      }
      return { rowCount: 1 };
    }

    return { rows: [] };
  }
}

test('listPlanetaryRegionsAndPlots returns all regions and territory plots', async () => {
  const repo = new FakePostgresRepository();
  const res = await listPlanetaryRegionsAndPlots(repo, 'H-0044');

  assert.equal(res.ok, true);
  assert.equal(res.regions.length, 2);
  assert.equal(res.plots.length, 2);
  assert.equal(res.plots[0].plot_name, 'Neo-Tokyo High-Bay Terminal');
  assert.equal(res.plots[1].lease_holder_name, 'Amara Vance');
});

test('claimPlotLease secures concession and updates balance and expiry', async () => {
  const repo = new FakePostgresRepository();
  const res = await claimPlotLease(repo, {
    humanId: 'H-0044',
    plotId: 'PLOT-PAC-01',
    durationDays: 30,
    correlationId: 'test-lease-01',
  });

  assert.equal(res.ok, true);
  assert.equal(res.expiresGameDay, 214);
  assert.equal(res.totalPaid, '2250.00'); // 75.00 * 30

  const acc = repo.data.account_balances.find((a) => a.owner_id === 'H-0044');
  assert.equal(acc.balance, '7750.00'); // 10000 - 2250

  const plot = repo.data.plots.find((p) => p.id === 'PLOT-PAC-01');
  assert.equal(plot.lease_holder_id, 'H-0044');
  assert.equal(plot.lease_expires_game_day, 214);
});

test('upgradePlotInfrastructure increases development level and yield rate', async () => {
  const repo = new FakePostgresRepository();
  const res = await upgradePlotInfrastructure(repo, {
    humanId: 'H-0044',
    plotId: 'PLOT-PAC-02',
    correlationId: 'test-upg-01',
  });

  assert.equal(res.ok, true);
  assert.equal(res.newLevel, 2);

  const plot = repo.data.plots.find((p) => p.id === 'PLOT-PAC-02');
  assert.equal(plot.development_level, 2);
  assert.equal(plot.base_yield_rate, '40.50'); // 30 * 1.35
  assert.match(plot.infrastructure_name, /Mark 2/);
});

test('harvestPlotYield credits accumulated commodity to player resource balances', async () => {
  const repo = new FakePostgresRepository();
  const res = await harvestPlotYield(repo, {
    humanId: 'H-0044',
    plotId: 'PLOT-PAC-02',
    correlationId: 'test-harvest-01',
  });

  assert.equal(res.ok, true);
  assert.equal(res.harvestedAmount, 90);
  assert.equal(res.resourceType, 'energy');

  const energyBal = repo.data.resource_balances.find((r) => r.owner_id === 'H-0044' && r.resource === 'energy');
  assert.equal(energyBal.amount, '140'); // 50 + 90

  const plot = repo.data.plots.find((p) => p.id === 'PLOT-PAC-02');
  assert.equal(plot.accumulated_yield, '0.00');
});
