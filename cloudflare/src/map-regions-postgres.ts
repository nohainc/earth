import { PostgresRepository } from './repository.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import { toNanoMarkup } from './nano-markup.ts';

export interface ClaimPlotLeaseInput {
  humanId: string;
  plotId: string;
  durationDays: number;
  correlationId?: string;
}

export interface UpgradePlotInfrastructureInput {
  humanId: string;
  plotId: string;
  correlationId?: string;
}

export interface HarvestPlotYieldInput {
  humanId: string;
  plotId: string;
  correlationId?: string;
}

export async function listPlanetaryRegionsAndPlots(
  repository: PostgresRepository,
  viewerId?: string,
): Promise<{ ok: boolean; regions: any[]; plots: any[] }> {
  const regionsRes = await repository.query(
    'SELECT * FROM planetary_regions ORDER BY id ASC',
  );

  const plotsRes = await repository.query(
    `SELECT tp.*, pr.name AS region_name, pr.biome_type, pr.climate_status,
            h.display_name AS lease_holder_name
     FROM territory_plots tp
     JOIN planetary_regions pr ON pr.id = tp.region_id
     LEFT JOIN humans h ON h.id = tp.lease_holder_id
     ORDER BY tp.region_id ASC, tp.id ASC`,
  );

  return {
    ok: true,
    regions: regionsRes.rows,
    plots: plotsRes.rows,
  };
}

export async function claimPlotLease(
  repository: PostgresRepository,
  input: ClaimPlotLeaseInput,
): Promise<{ ok: boolean; plot: any; totalPaid: string; expiresGameDay: number; alreadyProcessed?: boolean }> {
  return repository.transaction(async (tx) => {
    if (input.correlationId) {
      const existing = await tx.query<{
        id: string;
        plot_id: string;
        expires_game_day: number;
        total_paid: string;
      }>(
        'SELECT id, plot_id, expires_game_day, total_paid FROM territory_plot_leases WHERE id = $1',
        [`LEASE-${input.correlationId}`],
      );
      if (existing.rows[0]) {
        const plot = await tx.query('SELECT * FROM territory_plots WHERE id = $1', [existing.rows[0].plot_id]);
        return {
          ok: true,
          plot: plot.rows[0],
          totalPaid: existing.rows[0].total_paid,
          expiresGameDay: existing.rows[0].expires_game_day,
          alreadyProcessed: true,
        };
      }
    }

    const human = await tx.query<{ id: string; life_status: string }>(
      "SELECT id, life_status FROM humans WHERE id = $1 AND life_status = 'active'",
      [input.humanId],
    );
    if (!human.rows[0]) {
      throw new Error('Active Human identity is required');
    }

    const plot = await tx.query<{
      id: string;
      region_id: string;
      plot_name: string;
      daily_lease_fee: string;
      lease_holder_id: string | null;
      lease_expires_game_day: number | null;
    }>('SELECT * FROM territory_plots WHERE id = $1 FOR UPDATE', [input.plotId]);
    if (!plot.rows[0]) {
      throw new Error('Territory plot not found');
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const currentDay = Number(world.rows[0]?.game_day ?? 184);

    const isLeased = plot.rows[0].lease_holder_id &&
      plot.rows[0].lease_expires_game_day &&
      plot.rows[0].lease_expires_game_day > currentDay;

    if (isLeased && plot.rows[0].lease_holder_id !== input.humanId) {
      throw new Error('Plot is currently leased by another citizen');
    }

    const durationDays = Math.max(7, Math.min(180, Math.floor(input.durationDays || 30)));
    const dailyFeeCents = moneyToCents(plot.rows[0].daily_lease_fee);
    const totalCostCents = dailyFeeCents * BigInt(durationDays);
    const totalPaid = centsToMoney(totalCostCents);

    const buyerAcc = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.humanId],
    );
    if (!buyerAcc.rows[0] || moneyToCents(buyerAcc.rows[0].balance) < totalCostCents) {
      throw new Error('Insufficient credit balance to pay concession lease fee');
    }

    const newBalance = centsToMoney(moneyToCents(buyerAcc.rows[0].balance) - totalCostCents);
    await tx.query('UPDATE account_balances SET balance = $1 WHERE account_id = $2', [
      newBalance,
      buyerAcc.rows[0].account_id,
    ]);

    const currentExpiry = isLeased ? Number(plot.rows[0].lease_expires_game_day) : currentDay;
    const expiresGameDay = currentExpiry + durationDays;
    const leaseId = input.correlationId ? `LEASE-${input.correlationId}` : crypto.randomUUID();

    await tx.query(
      `UPDATE territory_plots 
       SET lease_holder_id = $1,
           lease_expires_game_day = $2,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $3`,
      [input.humanId, expiresGameDay, input.plotId],
    );

    await tx.query(
      `INSERT INTO territory_plot_leases (id, plot_id, human_id, starts_game_day, expires_game_day, total_paid, status)
       VALUES ($1, $2, $3, $4, $5, $6, 'active')`,
      [leaseId, input.plotId, input.humanId, currentDay, expiresGameDay, totalPaid],
    );

    await tx.query(
      `INSERT INTO world_events (id, game_day, event_type, title, details)
       VALUES ($1, $2, 'plot.leased', 'Territory Concession Leased', $3)
       ON CONFLICT (id) DO NOTHING`,
      [
        `EVT-LEASE-${leaseId}`,
        currentDay,
        toNanoMarkup({
          humanId: input.humanId,
          plotId: input.plotId,
          durationDays,
          totalPaid,
          expiresGameDay,
        }),
      ],
    );

    await tx.query(
      `INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id)
       VALUES ($1, $2, 'concession', 'Territory Concession Secured', $3, $4)`,
      [
        crypto.randomUUID(),
        input.humanId,
        `You have secured the concession rights to ${plot.rows[0].plot_name} until Game Day ${expiresGameDay}.`,
        input.plotId,
      ],
    );

    const updatedPlot = await tx.query('SELECT * FROM territory_plots WHERE id = $1', [input.plotId]);

    return {
      ok: true,
      plot: updatedPlot.rows[0],
      totalPaid,
      expiresGameDay,
    };
  });
}

export async function upgradePlotInfrastructure(
  repository: PostgresRepository,
  input: UpgradePlotInfrastructureInput,
): Promise<{ ok: boolean; plot: any; newLevel: number; alreadyProcessed?: boolean }> {
  return repository.transaction(async (tx) => {
    const plot = await tx.query<{
      id: string;
      plot_name: string;
      development_level: number;
      max_level: number;
      lease_holder_id: string | null;
      primary_resource: string;
      base_yield_rate: string;
      infrastructure_name: string;
    }>('SELECT * FROM territory_plots WHERE id = $1 FOR UPDATE', [input.plotId]);

    if (!plot.rows[0]) {
      throw new Error('Territory plot not found');
    }

    if (plot.rows[0].lease_holder_id !== input.humanId) {
      throw new Error('Only the current concession leaseholder may upgrade this plot');
    }

    if (plot.rows[0].development_level >= plot.rows[0].max_level) {
      throw new Error('Infrastructure is already at maximum development level');
    }

    const nextLevel = plot.rows[0].development_level + 1;
    const creditCostCents = BigInt(nextLevel * 50000); // 500.00 CR per level
    const materialCost = nextLevel * 25; // 25 units per level

    const buyerAcc = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.humanId],
    );
    if (!buyerAcc.rows[0] || moneyToCents(buyerAcc.rows[0].balance) < creditCostCents) {
      throw new Error(`Insufficient credits for upgrade (requires ${centsToMoney(creditCostCents)} CR)`);
    }

    const matRes = await tx.query<{ amount: string }>(
      "SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'material' FOR UPDATE",
      [input.humanId],
    );
    const matAmount = Number(matRes.rows[0]?.amount ?? 0);
    if (matAmount < materialCost) {
      throw new Error(`Insufficient material reserves for upgrade (requires ${materialCost} material units)`);
    }

    // Deduct credit & material
    const newBal = centsToMoney(moneyToCents(buyerAcc.rows[0].balance) - creditCostCents);
    await tx.query('UPDATE account_balances SET balance = $1 WHERE account_id = $2', [
      newBal,
      buyerAcc.rows[0].account_id,
    ]);

    await tx.query(
      "UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'material'",
      [materialCost, input.humanId],
    );

    const newYieldRate = (Number(plot.rows[0].base_yield_rate) * 1.35).toFixed(2);
    const upgradedInfraName = `${plot.rows[0].infrastructure_name} [Mark ${nextLevel}]`;

    await tx.query(
      `UPDATE territory_plots
       SET development_level = $1,
           base_yield_rate = $2,
           infrastructure_name = $3,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4`,
      [nextLevel, newYieldRate, upgradedInfraName, input.plotId],
    );

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const currentDay = Number(world.rows[0]?.game_day ?? 184);

    await tx.query(
      `INSERT INTO world_events (id, game_day, event_type, title, details)
       VALUES ($1, $2, 'plot.upgraded', 'Concession Infrastructure Upgraded', $3)
       ON CONFLICT (id) DO NOTHING`,
      [
        `EVT-UPG-${input.plotId}-${nextLevel}`,
        currentDay,
        toNanoMarkup({
          humanId: input.humanId,
          plotId: input.plotId,
          newLevel: nextLevel,
          infrastructureName: upgradedInfraName,
          baseYieldRate: newYieldRate,
        }),
      ],
    );

    const updatedPlot = await tx.query('SELECT * FROM territory_plots WHERE id = $1', [input.plotId]);

    return {
      ok: true,
      plot: updatedPlot.rows[0],
      newLevel: nextLevel,
    };
  });
}

export async function harvestPlotYield(
  repository: PostgresRepository,
  input: HarvestPlotYieldInput,
): Promise<{ ok: boolean; plot: any; harvestedAmount: number; resourceType: string }> {
  return repository.transaction(async (tx) => {
    const plot = await tx.query<{
      id: string;
      plot_name: string;
      lease_holder_id: string | null;
      primary_resource: string;
      accumulated_yield: string;
    }>('SELECT * FROM territory_plots WHERE id = $1 FOR UPDATE', [input.plotId]);

    if (!plot.rows[0]) {
      throw new Error('Territory plot not found');
    }

    if (plot.rows[0].lease_holder_id !== input.humanId) {
      throw new Error('Only the concession leaseholder may harvest accumulated yields');
    }

    const harvestQty = Number(plot.rows[0].accumulated_yield);
    if (harvestQty <= 0) {
      throw new Error('No accumulated resources available to harvest at this time');
    }

    const resourceType = plot.rows[0].primary_resource;

    await tx.query(
      `INSERT INTO resource_balances (owner_id, resource, amount)
       VALUES ($1, $2, $3)
       ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + $3`,
      [input.humanId, resourceType, harvestQty],
    );

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const currentDay = Number(world.rows[0]?.game_day ?? 184);

    await tx.query(
      `UPDATE territory_plots 
       SET accumulated_yield = 0.00,
           last_harvested_game_day = $1,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $2`,
      [currentDay, input.plotId],
    );

    await tx.query(
      `INSERT INTO world_events (id, game_day, event_type, title, details)
       VALUES ($1, $2, 'plot.harvested', 'Concession Yield Harvested', $3)
       ON CONFLICT (id) DO NOTHING`,
      [
        crypto.randomUUID(),
        currentDay,
        toNanoMarkup({
          humanId: input.humanId,
          plotId: input.plotId,
          resourceType,
          amount: harvestQty,
        }),
      ],
    );

    const updatedPlot = await tx.query('SELECT * FROM territory_plots WHERE id = $1', [input.plotId]);

    return {
      ok: true,
      plot: updatedPlot.rows[0],
      harvestedAmount: harvestQty,
      resourceType,
    };
  });
}
