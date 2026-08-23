import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import { toNanoMarkup } from './nano-markup.ts';

export async function advanceBuildingConstruction(tx: PostgresRepository, day: number): Promise<void> {
  const constructionQuery = await tx.query<{
    id: string;
    name: string;
    city_id: string;
    owner_id: string;
    construction_started_game_day: number;
    construction_complete_game_day: number;
  }>("SELECT id, name, city_id, owner_id, construction_started_game_day, construction_complete_game_day FROM buildings WHERE status = 'under_construction'");

  for (const bld of constructionQuery.rows) {
    const startDay = Number(bld.construction_started_game_day ?? 1);
    const completeDay = Number(bld.construction_complete_game_day ?? (startDay + 1));
    const totalDays = Math.max(1, completeDay - startDay);
    const elapsedDays = Math.max(0, day - startDay);
    const progress = Math.min(100.0, Math.round((elapsedDays / totalDays) * 10000) / 100);

    if (day >= completeDay) {
      await tx.query(
        "UPDATE buildings SET status = 'active', construction_progress = 100.0, updated_at = CURRENT_TIMESTAMP WHERE id = $1",
        [bld.id],
      );
      await tx.query(
        'INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING',
        [
          `BLD-CONSTRUCTED-${bld.id}-${day}`,
          day,
          'building.constructed',
          `Facility ${bld.name} construction completed`,
          toNanoMarkup({ buildingId: bld.id, cityId: bld.city_id, ownerId: bld.owner_id }),
        ],
      );
    } else {
      await tx.query(
        'UPDATE buildings SET construction_progress = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [progress, bld.id],
      );
    }
  }
}

export async function settleBuildingUpkeepAndRevenue(tx: PostgresRepository, day: number): Promise<void> {
  // 1. Advance active construction pipelines first
  await advanceBuildingConstruction(tx, day);

  // 2. Ensure clearing account exists
  await tx.query(
    "INSERT INTO account_balances (account_id, owner_id, currency, balance) VALUES ('account-market-clearing', 'SYSTEM', 'CREDIT', 0.00) ON CONFLICT (account_id) DO NOTHING",
  );

  // 3. Fetch all active buildings
  const bldQuery = await tx.query<{
    id: string;
    owner_id: string;
    city_id: string;
    ownership_class: string | null;
    business_id: string | null;
    operating_policy: string | null;
    upkeep_energy: string;
    upkeep_food: string;
    upkeep_materials: string;
    upkeep_components: string;
    upkeep_compute: string;
    daily_operating_credits: string;
    resource_output_type: string | null;
    resource_output_amount: string | null;
    tier: number;
    condition: string;
    auto_repair_enabled: boolean | null;
  }>("SELECT * FROM buildings WHERE status = 'active'");

  for (const bld of bldQuery.rows) {
    const oClass = (bld.ownership_class || 'private').toLowerCase();
    const policy = (bld.operating_policy || 'balanced').toLowerCase();
    const initialCondition = Number(bld.condition || 100);
    let condition = initialCondition;
    let autoRepaired = false;
    let actualGrossRevenueCrd = 0;
    let actualOperatingCostsCrd = 0;

    // Ensure dedicated city operations account exists for this city
    const opsAccount = `account-city-operations-${bld.city_id}`;
    await tx.query(
      'INSERT INTO account_balances (account_id, owner_id, currency, balance) VALUES ($1, $2, $3, 0.00) ON CONFLICT (account_id) DO NOTHING',
      [opsAccount, bld.city_id, 'CREDIT'],
    );

    // Automatic Building Repair check (restores condition before daily run)
    if (bld.auto_repair_enabled && condition < 80) {
      const repairResource = oClass === 'civic' ? 'materials' : 'components';
      const repairAccountOwner = oClass === 'civic' ? bld.city_id : bld.owner_id;
      const resCheck = await tx.query<{ amount: string }>(
        'SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE',
        [repairAccountOwner, repairResource],
      );
      if (Number(resCheck.rows[0]?.amount ?? 0) >= 1) {
        await tx.query(
          'UPDATE resource_balances SET amount = amount - 1 WHERE owner_id = $1 AND resource = $2',
          [repairAccountOwner, repairResource],
        );
        condition = 100.0;
        autoRepaired = true;
        await tx.query(
          'UPDATE buildings SET condition = 100.0, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
          [bld.id],
        );
      }
    }

    // Condition Efficiency Curve
    let efficiency = 1.0;
    let costMult = 1.0;
    if (condition >= 80) {
      efficiency = 1.0;
      costMult = 1.0;
    } else if (condition >= 50) {
      efficiency = 0.75;
      costMult = 1.15;
    } else if (condition >= 20) {
      efficiency = 0.40;
      costMult = 1.40;
    } else {
      efficiency = 0.10;
      costMult = 2.00;
    }

    // Policy Modifiers
    let policyYield = 1.0;
    let policyCost = 1.0;
    let policyDecay = 1.0;
    if (policy === 'frugal') {
      policyYield = 0.75;
      policyCost = 0.70;
      policyDecay = 0.50;
    } else if (policy === 'high_output') {
      policyYield = 1.30;
      policyCost = 1.40;
      policyDecay = 1.75;
    }

    const effectiveYield = efficiency * policyYield;

    // Settle Daily Operating Credits -> Credited to City Operations
    const opCostCrd = Number(bld.daily_operating_credits || 0) * policyCost * costMult;
    let operatingPaid = true;

    if (opCostCrd > 0) {
      const opCostCents = BigInt(Math.round(opCostCrd * 100));
      if (oClass === 'civic') {
        const cityAccount = await tx.query<{ account_id: string; balance: string }>(
          "SELECT account_id, balance FROM account_balances WHERE account_id = $1 FOR UPDATE",
          [`account-city-${bld.city_id}`],
        );
        if (!cityAccount.rows[0] || moneyToCents(cityAccount.rows[0].balance) < opCostCents) {
          operatingPaid = false;
        } else {
          await transferCredits(tx, {
            ledgerId: crypto.randomUUID(),
            gameDay: day,
            debitAccount: cityAccount.rows[0].account_id,
            creditAccount: opsAccount,
            amount: centsToMoney(opCostCents),
            reasonType: 'building_operating_cost',
            reasonId: bld.id,
            ruleVersion: 'real-estate-v2',
            correlationId: `BLD-OP-${bld.id}-${day}`,
          });
          actualOperatingCostsCrd = opCostCrd;
        }
      } else {
        const ownerAccount = await tx.query<{ account_id: string; balance: string }>(
          "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
          [bld.owner_id],
        );
        if (!ownerAccount.rows[0] || moneyToCents(ownerAccount.rows[0].balance) < opCostCents) {
          operatingPaid = false;
        } else {
          await transferCredits(tx, {
            ledgerId: crypto.randomUUID(),
            gameDay: day,
            debitAccount: ownerAccount.rows[0].account_id,
            creditAccount: opsAccount,
            amount: centsToMoney(opCostCents),
            reasonType: 'building_operating_cost',
            reasonId: bld.id,
            ruleVersion: 'real-estate-v2',
            correlationId: `BLD-OP-${bld.id}-${day}`,
          });
          actualOperatingCostsCrd = opCostCrd;
          if (bld.business_id) {
            await tx.query(
              'UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2 WHERE business_id = $3',
              [opCostCrd, day, bld.business_id],
            );
          }
        }
      }
    }

    if (!operatingPaid) {
      // Operating funds shortage: heavy wear and zero output
      const finalCond = Math.max(0, condition - 6);
      await tx.query(
        'UPDATE buildings SET condition = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [finalCond, bld.id],
      );
      await tx.query(
        `INSERT INTO building_settlement_journals (
          id, building_id, city_id, day, ownership_class,
          gross_revenue_crd, operating_costs_crd, net_surplus_crd,
          condition_start, condition_end, auto_repaired
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        ON CONFLICT (building_id, day) DO UPDATE SET
          gross_revenue_crd = EXCLUDED.gross_revenue_crd,
          operating_costs_crd = EXCLUDED.operating_costs_crd,
          net_surplus_crd = EXCLUDED.net_surplus_crd,
          condition_end = EXCLUDED.condition_end`,
        [
          `JOURNAL-${bld.id}-${day}`,
          bld.id,
          bld.city_id,
          day,
          oClass,
          0,
          0,
          0,
          initialCondition,
          finalCond,
          autoRepaired,
        ],
      );
      continue;
    }

    // Upkeep Requirements Check
    const upkeeps = [
      { resource: 'energy', amount: Number(bld.upkeep_energy || 0) * policyCost * costMult },
      { resource: 'food', amount: Number(bld.upkeep_food || 0) * policyCost * costMult },
      { resource: 'materials', amount: Number(bld.upkeep_materials || 0) * policyCost * costMult },
      { resource: 'components', amount: Number(bld.upkeep_components || 0) * policyCost * costMult },
      { resource: 'compute', amount: Number(bld.upkeep_compute || 0) * policyCost * costMult },
    ];

    let hasAllUpkeep = true;
    for (const u of upkeeps) {
      if (u.amount <= 0) continue;
      const resCheck = await tx.query<{ amount: string }>(
        'SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE',
        [bld.owner_id, u.resource],
      );
      if (Number(resCheck.rows[0]?.amount ?? 0) < u.amount) {
        hasAllUpkeep = false;
        break;
      }
    }

    let endCondition = condition;

    if (oClass === 'private' || oClass === 'civic') {
      if (hasAllUpkeep) {
        for (const u of upkeeps) {
          if (u.amount <= 0) continue;
          await tx.query(
            'UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3',
            [u.amount, bld.owner_id, u.resource],
          );
        }

        // Produce Output (Credits or Physical Commodity)
        const isCreditOutput = bld.resource_output_type === 'credits';
        const outAmt = Number(bld.resource_output_amount || 0) * effectiveYield;

        if (isCreditOutput && outAmt > 0) {
          const revCents = BigInt(Math.round(outAmt * 100));
          actualGrossRevenueCrd = outAmt;

          // 1. Economic Clearing: Fund the clearing account from consumer/market demand
          await tx.query(
            'UPDATE account_balances SET balance = balance + $1 WHERE account_id = $2',
            [centsToMoney(revCents), 'account-market-clearing'],
          );

          // 2. Clear funds to the recipient
          if (oClass === 'private') {
            const ownerAccount = await tx.query<{ account_id: string }>(
              "SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'",
              [bld.owner_id],
            );
            if (ownerAccount.rows[0]) {
              await transferCredits(tx, {
                ledgerId: crypto.randomUUID(),
                gameDay: day,
                debitAccount: 'account-market-clearing',
                creditAccount: ownerAccount.rows[0].account_id,
                amount: centsToMoney(revCents),
                reasonType: 'building_commercial_revenue',
                reasonId: bld.id,
                ruleVersion: 'real-estate-v2',
                correlationId: `BLD-REV-${bld.id}-${day}`,
              });
            }
            if (bld.business_id) {
              await tx.query(
                'UPDATE business_financials SET revenue = revenue + $1, profit = profit + $1, last_game_day = $2 WHERE business_id = $3',
                [outAmt, day, bld.business_id],
              );
            }
          } else if (oClass === 'civic') {
            // Civic municipal facility generates utility revenue deposited into city treasury
            const cityAccount = await tx.query<{ account_id: string }>(
              "SELECT account_id FROM account_balances WHERE account_id = $1",
              [`account-city-${bld.city_id}`],
            );
            if (cityAccount.rows[0]) {
              await transferCredits(tx, {
                ledgerId: crypto.randomUUID(),
                gameDay: day,
                debitAccount: 'account-market-clearing',
                creditAccount: `account-city-${bld.city_id}`,
                amount: centsToMoney(revCents),
                reasonType: 'civic_utility_revenue',
                reasonId: bld.id,
                ruleVersion: 'real-estate-v2',
                correlationId: `CIVIC-REV-${bld.id}-${day}`,
              });
            }
          }
        } else if (!isCreditOutput && outAmt > 0 && bld.resource_output_type) {
          await tx.query(
            'INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1, $2, $3) ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount',
            [bld.owner_id, bld.resource_output_type, outAmt],
          );
        }

        // Daily operational wear
        const wear = 1.0 * policyDecay;
        endCondition = Math.max(0, condition - wear);
        await tx.query(
          'UPDATE buildings SET condition = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
          [endCondition, bld.id],
        );
      } else {
        // Upkeep shortage: heavy decay
        endCondition = Math.max(0, condition - 8);
        await tx.query(
          'UPDATE buildings SET condition = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
          [endCondition, bld.id],
        );
      }
    } else if (oClass === 'public_investment') {
      // Distribute public investment shares pro-rata from market clearing
      const isCreditOutput = bld.resource_output_type === 'credits';
      const rev = (isCreditOutput ? Number(bld.resource_output_amount || 0) : 0) * effectiveYield;
      if (rev > 0) {
        actualGrossRevenueCrd = rev;
        const revCents = BigInt(Math.round(rev * 100));

        // Fund clearing account from market commerce
        await tx.query(
          'UPDATE account_balances SET balance = balance + $1 WHERE account_id = $2',
          [centsToMoney(revCents), 'account-market-clearing'],
        );

        const sharesQuery = await tx.query<{
          investor_id: string;
          shares_owned: number;
          total_shares_issued: number;
        }>(
          'SELECT investor_id, shares_owned, total_shares_issued FROM building_investment_shares WHERE building_id = $1',
          [bld.id],
        );

        for (const s of sharesQuery.rows) {
          const payout = (rev * s.shares_owned) / Math.max(1, s.total_shares_issued);
          if (payout > 0) {
            const payoutCents = BigInt(Math.round(payout * 100));
            const invAccount = await tx.query<{ account_id: string }>(
              "SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'",
              [s.investor_id],
            );
            if (invAccount.rows[0]) {
              await transferCredits(tx, {
                ledgerId: crypto.randomUUID(),
                gameDay: day,
                debitAccount: 'account-market-clearing',
                creditAccount: invAccount.rows[0].account_id,
                amount: centsToMoney(payoutCents),
                reasonType: 'public_share_dividend',
                reasonId: bld.id,
                ruleVersion: 'real-estate-v2',
                correlationId: `PUB-DIV-${bld.id}-${s.investor_id}-${day}`,
              });

              await tx.query(
                'UPDATE building_investment_shares SET accumulated_dividends_crd = accumulated_dividends_crd + $1, updated_at = CURRENT_TIMESTAMP WHERE building_id = $2 AND investor_id = $3',
                [payout, bld.id, s.investor_id],
              );
            }
          }
        }
      }
      endCondition = Math.max(0, condition - 1.0);
      await tx.query(
        'UPDATE buildings SET condition = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [endCondition, bld.id],
      );
    }

    const netSurplus = Math.max(0, actualGrossRevenueCrd - actualOperatingCostsCrd);
    await tx.query(
      `INSERT INTO building_settlement_journals (
        id, building_id, city_id, day, ownership_class,
        gross_revenue_crd, operating_costs_crd, net_surplus_crd,
        condition_start, condition_end, auto_repaired
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (building_id, day) DO UPDATE SET
        gross_revenue_crd = EXCLUDED.gross_revenue_crd,
        operating_costs_crd = EXCLUDED.operating_costs_crd,
        net_surplus_crd = EXCLUDED.net_surplus_crd,
        condition_end = EXCLUDED.condition_end`,
      [
        `JOURNAL-${bld.id}-${day}`,
        bld.id,
        bld.city_id,
        day,
        oClass,
        actualGrossRevenueCrd,
        actualOperatingCostsCrd,
        netSurplus,
        initialCondition,
        endCondition,
        autoRepaired,
      ],
    );
  }
}
