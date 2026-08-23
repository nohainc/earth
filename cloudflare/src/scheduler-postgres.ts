import type { PostgresRepository } from './repository.ts';
import { settleMarket } from './market-postgres.ts';
import { processMortality } from './lifecycle-postgres.ts';
import { transferCredits } from './financial-postgres.ts';
import { classifyBusinessFinancialStatus } from './business-finance.ts';
import { centsToMoney, compoundRateAmountToCents, moneyToCents, quantityToCents, rateAmountToCents } from './money.ts';
import { validateWorldAdvanceMinutes } from './scheduler-rules.ts';
import { fromNanoMarkup, toNanoMarkup } from './nano-markup.ts';
import { expireSocialInitiatives } from './social-gameplay-postgres.ts';

const products = ['food', 'material', 'components', 'energy', 'compute'];

function charterRate(raw: unknown, key: string): number | null {
  if (!raw) return null;
  const charter = fromNanoMarkup<Record<string, unknown>>(raw);
  const value = Number(charter?.[key]);
  return Number.isFinite(value) ? value / 10000 : null;
}

function effectiveRate(cityRules: unknown, corporationRules: unknown, key: string, earthRate: string): string {
  const city = charterRate(cityRules, key);
  if (city !== null) return String(city);
  const corporation = charterRate(corporationRules, key);
  if (corporation !== null) return String(corporation);
  return earthRate;
}

async function settleBusinessDepreciation(tx: PostgresRepository, day: number): Promise<void> {
  const assets = await tx.query<{ business_id: string; machine_id: string; book_value: string }>('SELECT business_assets.business_id, business_assets.machine_id, COALESCE(machine_acquisitions.credit_cost, 0) AS book_value FROM business_assets LEFT JOIN machine_acquisitions ON machine_acquisitions.machine_id = business_assets.machine_id');
  for (const asset of assets.rows) {
    const amountCents = rateAmountToCents(moneyToCents(asset.book_value), '0.01', 1);
    if (amountCents <= 0n) continue;
    const amount = centsToMoney(amountCents);
    const correlationId = `DEPRECIATION-${asset.business_id}-${asset.machine_id}-${day}`;
    const prior = await tx.query('SELECT 1 FROM ledger_entries WHERE reason_type = \'business_depreciation\' AND correlation_id = $1', [correlationId]);
    if (prior.rows[0]) continue;
    await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [amount, day, asset.business_id]);
    await tx.query('INSERT INTO ledger_entries (id,game_day,debit_account,credit_account,amount,currency,reason_type,reason_id,rule_version,correlation_id) VALUES ($1,$2,$3,$4,$5,\'CREDIT\',\'business_depreciation\',$6,\'business-finance-v1\',$7)', [crypto.randomUUID(), day, `business-${asset.business_id}`, 'account-depreciation-expense', amount, asset.machine_id, correlationId]);
  }
}

async function settleWorkforcePayroll(tx: PostgresRepository, day: number): Promise<void> {
  const payroll = await tx.query<{ business_id: string; total: string }>(
    "SELECT business_id, COALESCE(SUM(wage), 0) AS total FROM business_employees WHERE status = 'active' GROUP BY business_id",
  );
  for (const row of payroll.rows) {
    const total = Number(row.total ?? 0);
    if (total <= 0) continue;
    await tx.query(
      'UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3',
      [total, day, row.business_id],
    );
    await tx.query(
      "UPDATE business_employees SET morale = GREATEST(0, morale - 0.01), updated_at = CURRENT_TIMESTAMP WHERE business_id = $1 AND status = 'active'",
      [row.business_id],
    );
  }
}

async function settleServiceBusinessRevenue(tx: PostgresRepository, day: number): Promise<void> {
  const serviceBusinesses = await tx.query<{ business_id: string; revenue: string }>(
    "SELECT b.id AS business_id, COALESCE(SUM(e.skill * e.morale * 160 * CASE WHEN b.sector = 'it-services' AND lower(e.role) ~ '(engineer|developer|architect)' THEN 1.25 WHEN b.sector = 'consulting' AND lower(e.role) ~ '(consultant|advisor|analyst)' THEN 1.25 WHEN b.sector = 'logistics' AND lower(e.role) ~ '(dispatcher|coordinator|planner)' THEN 1.25 WHEN b.sector = 'healthcare' AND lower(e.role) ~ '(caregiver|nurse|doctor)' THEN 1.25 WHEN b.sector = 'education' AND lower(e.role) ~ '(teacher|mentor|instructor)' THEN 1.25 ELSE 1 END), 0) * CASE WHEN EXISTS (SELECT 1 FROM negotiated_contracts c WHERE c.kind = 'intellectual_service' AND c.status = 'accepted' AND c.ends_game_day > $1 AND c.terms_json->>'proposerBusinessId' = b.id) THEN 1 ELSE 0.35 END * CASE WHEN b.sector IN ('it-services', 'consulting') AND COALESCE(c.connectivity_capacity / NULLIF(c.residents, 0), 0) >= 1 THEN 1.15 WHEN b.sector = 'healthcare' AND COALESCE(c.health_capacity / 100.0, 0) >= 0.8 THEN 1.15 WHEN b.sector = 'education' AND COALESCE(c.housing_capacity / NULLIF(c.residents, 0), 0) >= 1 THEN 1.10 ELSE 1 END AS revenue FROM businesses b JOIN business_employees e ON e.business_id = b.id AND e.status = 'active' LEFT JOIN memberships m ON m.human_id = b.owner_id LEFT JOIN cities c ON c.id = m.city_id WHERE b.status = 'active' AND b.sector IN ('it-services', 'consulting', 'logistics', 'healthcare', 'education') GROUP BY b.id, c.connectivity_capacity, c.health_capacity, c.housing_capacity, c.residents",
    [day],
  );
  for (const row of serviceBusinesses.rows) {
    const revenue = Number(row.revenue ?? 0);
    if (revenue <= 0) continue;
    await tx.query(
      'UPDATE business_financials SET revenue = revenue + $1, profit = profit + $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3',
      [revenue, day, row.business_id],
    );
  }
}

async function settleInstitutionBusinessEffects(tx: PostgresRepository, day: number): Promise<void> {
  const businesses = await tx.query<{ business_id: string; sector: string; city_id: string | null; corporation_id: string | null; housing_capacity: string | null; energy_capacity: string | null; connectivity_capacity: string | null; health_capacity: string | null; residents: string | null }>(
    "SELECT b.id AS business_id, b.sector, m.city_id, m.corporation_id, c.housing_capacity, c.energy_capacity, c.connectivity_capacity, c.health_capacity, c.residents FROM businesses b LEFT JOIN memberships m ON m.human_id = b.owner_id LEFT JOIN cities c ON c.id = m.city_id WHERE b.status = 'active'",
  );
  for (const business of businesses.rows) {
    const residents = Math.max(1, Number(business.residents ?? 1));
    const ratios = [
      Number(business.housing_capacity ?? residents) / residents,
      Number(business.energy_capacity ?? residents) / residents,
      Number(business.connectivity_capacity ?? residents) / residents,
      Number(business.health_capacity ?? 100) / 100,
    ];
    const servicePressure = Math.max(0, Math.min(...ratios));
    if (business.city_id && servicePressure < 0.75) {
      const disruptionCost = Math.round((0.75 - servicePressure) * 100 * 100) / 100;
      await tx.query(
        'UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3',
        [disruptionCost, day, business.business_id],
      );
    }
    if (business.corporation_id && ['it-services', 'consulting', 'logistics', 'healthcare', 'education'].includes(business.sector)) {
      const networkRevenue = 20;
      await tx.query(
        'UPDATE business_financials SET revenue = revenue + $1, profit = profit + $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3',
        [networkRevenue, day, business.business_id],
      );
    }
  }
}

async function settleBusinessTaxes(tx: PostgresRepository, day: number): Promise<void> {
  const rule = await tx.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BUSINESS' AND active = true");
  if (!rule.rows[0]) return;
  const businesses = await tx.query<{ id: string; owner_id: string; revenue: string; taxed_revenue: string; city_id: string | null; corporation_id: string | null; city_charter: string | null; corporation_charter: string | null }>("SELECT businesses.id, businesses.owner_id, business_financials.revenue, business_financials.taxed_revenue, memberships.city_id, memberships.corporation_id, city_institution.charter_rules AS city_charter, corporation_institution.charter_rules AS corporation_charter FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id LEFT JOIN memberships ON memberships.human_id = businesses.owner_id LEFT JOIN institutions city_institution ON city_institution.id = memberships.city_id LEFT JOIN institutions corporation_institution ON corporation_institution.id = memberships.corporation_id WHERE businesses.status = 'active'");
  for (const business of businesses.rows) {
    const taxableCents = moneyToCents(business.revenue) - moneyToCents(business.taxed_revenue);
    const effectiveCorporateRate = effectiveRate(business.city_charter, business.corporation_charter, 'corporateTaxBps', rule.rows[0].rate);
    const taxCents = taxableCents > 0n ? rateAmountToCents(taxableCents, effectiveCorporateRate, 1) : 0n;
    if (taxCents <= 0n) { await tx.query('UPDATE business_financials SET taxed_revenue = GREATEST(taxed_revenue, revenue), last_game_day = $1 WHERE business_id = $2', [day, business.id]); continue; }
    const tax = centsToMoney(taxCents);
    const correlationId = `BUSINESS-TAX-${business.id}-${day}`;
    const prior = await tx.query('SELECT 1 FROM ledger_entries WHERE reason_type = \'business_tax\' AND correlation_id = $1', [correlationId]);
    if (prior.rows[0]) continue;
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [business.owner_id]);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < taxCents) continue;

    // 3-Way Pro-Rata Tax Distribution: 60% City, 25% Corp, 15% Planetary
    const cityCents = (taxCents * 60n) / 100n;
    const corpCents = (taxCents * 25n) / 100n;
    const oucCents = taxCents - cityCents - corpCents;

    const cityTarget = business.city_id ? `account-city-${business.city_id}` : 'account-ouc-treasury';
    const corpTarget = business.corporation_id ? `account-corporation-${business.corporation_id}` : cityTarget;

    if (cityCents > 0n) {
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: cityTarget, amount: centsToMoney(cityCents), reasonType: 'business_tax_city', reasonId: business.id, ruleVersion: `business-tax-v${rule.rows[0].version}`, correlationId: `${correlationId}-CITY` });
    }
    if (corpCents > 0n) {
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: corpTarget, amount: centsToMoney(corpCents), reasonType: 'business_tax_corp', reasonId: business.id, ruleVersion: `business-tax-v${rule.rows[0].version}`, correlationId: `${correlationId}-CORP` });
    }
    if (oucCents > 0n) {
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-ouc-treasury', amount: centsToMoney(oucCents), reasonType: 'business_tax_ouc', reasonId: business.id, ruleVersion: `business-tax-v${rule.rows[0].version}`, correlationId: `${correlationId}-OUC` });
    }

    await tx.query('UPDATE business_financials SET taxed_revenue = revenue, operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [tax, day, business.id]);
  }
}

async function settleBuildingUpkeepAndRevenue(tx: PostgresRepository, day: number): Promise<void> {
  const bldQuery = await tx.query<{
    id: string;
    owner_id: string;
    city_id: string;
    ownership_type: string;
    ownership_class: string | null;
    business_id: string | null;
    operating_policy: string | null;
    upkeep_energy: string;
    upkeep_food: string;
    upkeep_materials: string;
    upkeep_components: string;
    upkeep_compute: string;
    daily_operating_credits: string;
    base_revenue_crd: string;
    resource_output_type: string | null;
    resource_output_amount: string | null;
    tier: number;
    condition: string;
    auto_repair_enabled: boolean | null;
  }>("SELECT * FROM buildings WHERE status NOT IN ('closed', 'foreclosed')");

  for (const bld of bldQuery.rows) {
    const oClass = (bld.ownership_class || 'private').toLowerCase();
    const policy = (bld.operating_policy || 'balanced').toLowerCase();
    const condition = Number(bld.condition || 100);

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
      costMult = 1.50;
    } else {
      efficiency = 0.0; // Operations suspended
      costMult = 0.50;
    }

    // Policy Multipliers
    let policyYield = 1.0;
    let policyCost = 1.0;
    let policyDecay = 1.0;
    if (policy === 'high_output') {
      policyYield = 1.25;
      policyCost = 1.40;
      policyDecay = 1.50;
    } else if (policy === 'eco_reserve') {
      policyYield = 0.75;
      policyCost = 0.60;
      policyDecay = 0.50;
    } else if (policy === 'overclock') {
      policyYield = 1.50;
      policyCost = 2.00;
      policyDecay = 3.00;
    }

    const effectiveYield = efficiency * policyYield;
    const effectiveCostMult = costMult * policyCost;

    if (oClass === 'private') {
      const uEnergy = Number(bld.upkeep_energy) * effectiveCostMult;
      const uFood = Number(bld.upkeep_food) * effectiveCostMult;
      const uMat = Number(bld.upkeep_materials) * effectiveCostMult;
      const uComp = Number(bld.upkeep_components) * effectiveCostMult;
      const uDat = Number(bld.upkeep_compute) * effectiveCostMult;

      let upkeepMet = true;
      if (uEnergy > 0) {
        const bal = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'energy' FOR UPDATE", [bld.owner_id]);
        if (Number(bal.rows[0]?.amount ?? 0) >= uEnergy) {
          await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'energy'", [uEnergy, bld.owner_id]);
        } else upkeepMet = false;
      }
      if (uFood > 0 && upkeepMet) {
        const bal = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'food' FOR UPDATE", [bld.owner_id]);
        if (Number(bal.rows[0]?.amount ?? 0) >= uFood) {
          await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'food'", [uFood, bld.owner_id]);
        } else upkeepMet = false;
      }
      if (uMat > 0 && upkeepMet) {
        const bal = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'material' FOR UPDATE", [bld.owner_id]);
        if (Number(bal.rows[0]?.amount ?? 0) >= uMat) {
          await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'material'", [uMat, bld.owner_id]);
        } else upkeepMet = false;
      }
      if (uComp > 0 && upkeepMet) {
        const bal = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE", [bld.owner_id]);
        if (Number(bal.rows[0]?.amount ?? 0) >= uComp) {
          await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components'", [uComp, bld.owner_id]);
        } else upkeepMet = false;
      }
      if (uDat > 0 && upkeepMet) {
        const bal = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'compute' FOR UPDATE", [bld.owner_id]);
        if (Number(bal.rows[0]?.amount ?? 0) >= uDat) {
          await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'compute'", [uDat, bld.owner_id]);
        } else upkeepMet = false;
      }

      if (upkeepMet && effectiveYield > 0) {
        // Produce Commodity Output if applicable
        const outType = bld.resource_output_type;
        const outAmount = Number(bld.resource_output_amount || 0) * effectiveYield;
        if (outType && outType !== 'credits' && outAmount > 0) {
          await tx.query(
            "UPDATE resource_balances SET amount = amount + $1 WHERE owner_id = $2 AND resource = $3",
            [outAmount, bld.owner_id, outType],
          );
        }

        // Produce Credit Revenue if applicable
        const rev = Number(bld.base_revenue_crd) * effectiveYield;
        if (rev > 0) {
          const revCents = BigInt(Math.round(rev * 100));
          const ownerAccount = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [bld.owner_id]);
          if (ownerAccount.rows[0]) {
            await transferCredits(tx, {
              ledgerId: crypto.randomUUID(),
              gameDay: day,
              debitAccount: `account-city-${bld.city_id}`,
              creditAccount: ownerAccount.rows[0].account_id,
              amount: centsToMoney(revCents),
              reasonType: 'building_commercial_revenue',
              reasonId: bld.id,
              ruleVersion: 'real-estate-v2',
              correlationId: `BLD-REV-${bld.id}-${day}`,
            }).catch(() => undefined);
          }
          if (bld.business_id) {
            await tx.query("UPDATE business_financials SET revenue = revenue + $1, profit = profit + $1, last_game_day = $2 WHERE business_id = $3", [rev, day, bld.business_id]);
          }
        }

        // Apply slight daily wear
        const wear = 1.0 * policyDecay;
        await tx.query("UPDATE buildings SET condition = GREATEST(0, condition - $1), updated_at = CURRENT_TIMESTAMP WHERE id = $2", [wear, bld.id]);
      } else {
        // Upkeep shortage: heavy decay
        await tx.query("UPDATE buildings SET condition = GREATEST(0, condition - 8), updated_at = CURRENT_TIMESTAMP WHERE id = $1", [bld.id]);
      }
    } else if (oClass === 'public_investment') {
      // Distribute public investment shares pro-rata
      const rev = Number(bld.base_revenue_crd) * effectiveYield;
      if (rev > 0) {
        const sharesQuery = await tx.query<{
          investor_id: string;
          shares_owned: number;
          total_shares_issued: number;
        }>('SELECT investor_id, shares_owned, total_shares_issued FROM building_investment_shares WHERE building_id = $1', [bld.id]);

        for (const s of sharesQuery.rows) {
          const payout = (rev * s.shares_owned) / Math.max(1, s.total_shares_issued);
          if (payout > 0) {
            const payoutCents = BigInt(Math.round(payout * 100));
            const invAccount = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [s.investor_id]);
            if (invAccount.rows[0]) {
              await transferCredits(tx, {
                ledgerId: crypto.randomUUID(),
                gameDay: day,
                debitAccount: `account-city-${bld.city_id}`,
                creditAccount: invAccount.rows[0].account_id,
                amount: centsToMoney(payoutCents),
                reasonType: 'public_share_dividend',
                reasonId: bld.id,
                ruleVersion: 'real-estate-v2',
                correlationId: `PUB-DIV-${bld.id}-${s.investor_id}-${day}`,
              }).catch(() => undefined);

              await tx.query(
                'UPDATE building_investment_shares SET accumulated_dividends_crd = accumulated_dividends_crd + $1, updated_at = CURRENT_TIMESTAMP WHERE building_id = $2 AND investor_id = $3',
                [payout, bld.id, s.investor_id],
              );
            }
          }
        }
      }
    }
  }
}

async function settleCivicDividends(tx: PostgresRepository, day: number): Promise<void> {
  const cities = await tx.query<{ id: string }>("SELECT id FROM cities");
  for (const c of cities.rows) {
    const cityId = c.id;

    // Calculate total civic surplus from municipal buildings
    const civicBldQuery = await tx.query<{ total_rev: string }>(
      "SELECT COALESCE(SUM(COALESCE(resource_output_amount, base_revenue_crd)), 0) AS total_rev FROM buildings WHERE city_id = $1 AND ownership_class = 'civic' AND status = 'active'",
      [cityId],
    );
    const totalCivicSurplus = Number(civicBldQuery.rows[0]?.total_rev ?? 0);
    if (totalCivicSurplus <= 0) continue;

    // Find eligible residents (registered in city)
    const residents = await tx.query<{ human_id: string }>(
      "SELECT human_id FROM memberships WHERE city_id = $1 AND status = 'active'",
      [cityId],
    );
    if (residents.rows.length === 0) continue;

    const residentCount = residents.rows.length;
    // 70/30 Hybrid Formula: 70% Base Equal UBI + 30% Participation
    const baseDividendPool = totalCivicSurplus * 0.70;
    const baseDividendPerResident = baseDividendPool / residentCount;
    const participationPool = totalCivicSurplus * 0.30;
    const participationPerResident = participationPool / residentCount;

    const totalPerResident = baseDividendPerResident + participationPerResident;
    const payoutCents = BigInt(Math.round(totalPerResident * 100));

    const cityAccount = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE account_id = $1 FOR UPDATE",
      [`account-city-${cityId}`],
    );
    if (!cityAccount.rows[0]) continue;

    // Distribute to residents
    for (const res of residents.rows) {
      if (moneyToCents(cityAccount.rows[0].balance) < payoutCents) break;

      const humanAccount = await tx.query<{ account_id: string }>(
        "SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'",
        [res.human_id],
      );
      if (!humanAccount.rows[0]) continue;

      const correlationId = `CIVIC-DIV-${cityId}-${res.human_id}-${day}`;
      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(),
        gameDay: day,
        debitAccount: cityAccount.rows[0].account_id,
        creditAccount: humanAccount.rows[0].account_id,
        amount: centsToMoney(payoutCents),
        reasonType: 'civic_resident_dividend',
        reasonId: cityId,
        ruleVersion: 'civic-dividend-v2',
        correlationId,
      }).catch(() => undefined);
    }

    // Log in civic_dividend_payouts
    const payoutLogId = `CDIV-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.query(
      `INSERT INTO civic_dividend_payouts (id, city_id, day, total_civic_surplus, base_dividend_per_resident, participation_dividend_pool, eligible_residents_count)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [payoutLogId, cityId, day, totalCivicSurplus, baseDividendPerResident, participationPool, residentCount],
    );
  }
}

async function settleBasicLevy(tx: PostgresRepository, day: number): Promise<void> {
  const rule = await tx.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BASIC' AND active = true");
  const world = await tx.query<{ living_cost_index: string }>("SELECT living_cost_index FROM world_state WHERE id = 'WORLD'");
  if (!rule.rows[0]) return;
  const levyBaseCents = compoundRateAmountToCents(10000n, String(world.rows[0]?.living_cost_index ?? '1'));
  const humans = await tx.query<{ id: string; account_id: string; balance: string; city_charter: string | null; corporation_charter: string | null }>("SELECT humans.id, account_balances.account_id, account_balances.balance, city_institution.charter_rules AS city_charter, corporation_institution.charter_rules AS corporation_charter FROM humans JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' LEFT JOIN memberships ON memberships.human_id = humans.id LEFT JOIN institutions city_institution ON city_institution.id = memberships.city_id LEFT JOIN institutions corporation_institution ON corporation_institution.id = memberships.corporation_id WHERE humans.life_status = 'active'");
  for (const human of humans.rows) {
    const effectiveIncomeRate = effectiveRate(human.city_charter, human.corporation_charter, 'incomeTaxBps', rule.rows[0].rate);
    const levyCents = rateAmountToCents(levyBaseCents, effectiveIncomeRate, 1);
    const levy = centsToMoney(levyCents);
    const correlationId = `BASIC-LEVY-${human.id}-${day}-v${rule.rows[0].version}`;
    if (levyCents <= 0n || moneyToCents(human.balance) < levyCents || (await tx.query('SELECT 1 FROM ledger_entries WHERE reason_type = \'basic_levy\' AND correlation_id = $1', [correlationId])).rows[0]) continue;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: human.account_id, creditAccount: 'account-ouc-treasury', amount: levy, reasonType: 'basic_levy', reasonId: human.id, ruleVersion: `tax-v${rule.rows[0].version}`, correlationId });
  }
}

async function runAiMaintenance(tx: PostgresRepository, day: number): Promise<void> {
  const assistants = await tx.query<{ owner_id: string; machine_id: string }>("SELECT ai_assistants.owner_id, machines.id AS machine_id FROM ai_assistants JOIN machines ON machines.owner_id = ai_assistants.owner_id WHERE ai_assistants.enabled = true AND ai_assistants.policy = 'maintenance' AND machines.maintenance_due > 0 AND machines.condition < 100");
  for (const assistant of assistants.rows) {
    const components = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE", [assistant.owner_id]);
    const amount = Math.min(5, Number(components.rows[0]?.amount ?? 0));
    if (amount <= 0) continue;
    await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components' AND amount >= $1", [amount, assistant.owner_id]);
    await tx.query('UPDATE machines SET condition = LEAST(100, condition + $1 * 0.8), maintenance_due = GREATEST(0, maintenance_due - $1) WHERE id = $2 AND owner_id = $3', [amount, assistant.machine_id, assistant.owner_id]);
    await tx.query("INSERT INTO maintenance_events (id,machine_id,owner_id,resource,amount,condition_before,condition_after,game_day) SELECT $1,id,owner_id,'components',$2,condition,LEAST(100,condition + $2 * 0.8),$3 FROM machines WHERE id = $4", [crypto.randomUUID(), amount, day, assistant.machine_id]);
  }
}

async function settleSupplyContracts(tx: PostgresRepository, day: number): Promise<void> {
  const active = await tx.query<{
    contract_id: string;
    resource_type: string;
    daily_quantity: string;
    unit_price: string;
    total_days: number;
    delivered_days: number;
    default_days: number;
    consecutive_defaults: number;
    max_consecutive_defaults: number;
    escrow_remaining: string;
    penalty_per_default: string;
    buyer_id: string;
    seller_id: string;
    vault_id: string;
    title: string;
  }>(
    `SELECT sc.contract_id, sc.resource_type, sc.daily_quantity, sc.unit_price,
            sc.total_days, sc.delivered_days, sc.default_days, sc.consecutive_defaults,
            sc.max_consecutive_defaults, sc.escrow_remaining, sc.penalty_per_default,
            ev.id AS vault_id, ev.buyer_id, ev.seller_id, nc.title
     FROM supply_contracts sc
     JOIN negotiated_contracts nc ON nc.id = sc.contract_id
     JOIN contract_escrow_vaults ev ON ev.contract_id = sc.contract_id
     WHERE nc.status = 'accepted' AND (sc.last_settled_game_day IS NULL OR sc.last_settled_game_day < $1)
     FOR UPDATE`,
    [day],
  );

  for (const contract of active.rows) {
    const qty = Number(contract.daily_quantity);
    const dailyPriceCents = BigInt(Math.round(qty * 100)) * BigInt(Math.round(Number(contract.unit_price) * 100)) / 100n;
    const dailyPrice = centsToMoney(dailyPriceCents);
    const penaltyCents = moneyToCents(contract.penalty_per_default);

    const sellerRes = await tx.query<{ amount: string }>(
      'SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE',
      [contract.seller_id, contract.resource_type],
    );
    const sellerHas = Number(sellerRes.rows[0]?.amount ?? 0);

    if (sellerHas >= qty) {
      await tx.query(
        'UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3',
        [qty, contract.seller_id, contract.resource_type],
      );
      await tx.query(
        `INSERT INTO resource_balances (owner_id, resource, amount)
         VALUES ($1, $2, $3)
         ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + $3`,
        [contract.buyer_id, contract.resource_type, qty],
      );

      const sellerAcc = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
        [contract.seller_id],
      );
      if (sellerAcc.rows[0]) {
        const newBal = centsToMoney(moneyToCents(sellerAcc.rows[0].balance) + dailyPriceCents);
        await tx.query('UPDATE account_balances SET balance = $1 WHERE account_id = $2', [
          newBal,
          sellerAcc.rows[0].account_id,
        ]);
      }

      const newRemaining = centsToMoney(moneyToCents(contract.escrow_remaining) - dailyPriceCents);
      const isComplete = (contract.delivered_days + 1) >= contract.total_days;

      await tx.query(
        `UPDATE supply_contracts 
         SET delivered_days = delivered_days + 1,
             consecutive_defaults = 0,
             escrow_remaining = $1,
             last_settled_game_day = $2
         WHERE contract_id = $3`,
        [newRemaining, day, contract.contract_id],
      );

      await tx.query(
        `UPDATE contract_escrow_vaults 
         SET released_amount = released_amount + $1,
             status = CASE WHEN $2 THEN 'released' ELSE status END,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $3`,
        [dailyPrice, isComplete, contract.vault_id],
      );

      if (isComplete) {
        await tx.query("UPDATE negotiated_contracts SET status = 'completed' WHERE id = $1", [contract.contract_id]);
      }

      await tx.query(
        `INSERT INTO contract_delivery_ticks (id, contract_id, game_day, status, quantity_delivered, credits_transferred)
         VALUES ($1, $2, $3, 'delivered', $4, $5)`,
        [crypto.randomUUID(), contract.contract_id, day, qty, dailyPrice],
      );
    } else {
      const newConsecutive = contract.consecutive_defaults + 1;
      let penaltyPaid = '0.00';

      if (penaltyCents > 0n) {
        const sellerAcc = await tx.query<{ account_id: string; balance: string }>(
          "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
          [contract.seller_id],
        );
        const buyerAcc = await tx.query<{ account_id: string; balance: string }>(
          "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
          [contract.buyer_id],
        );
        if (sellerAcc.rows[0] && buyerAcc.rows[0] && moneyToCents(sellerAcc.rows[0].balance) >= penaltyCents) {
          const newSellerBal = centsToMoney(moneyToCents(sellerAcc.rows[0].balance) - penaltyCents);
          const newBuyerBal = centsToMoney(moneyToCents(buyerAcc.rows[0].balance) + penaltyCents);
          await tx.query('UPDATE account_balances SET balance = $1 WHERE account_id = $2', [newSellerBal, sellerAcc.rows[0].account_id]);
          await tx.query('UPDATE account_balances SET balance = $1 WHERE account_id = $2', [newBuyerBal, buyerAcc.rows[0].account_id]);
          penaltyPaid = centsToMoney(penaltyCents);
        }
      }

      const isBreached = newConsecutive >= contract.max_consecutive_defaults;

      await tx.query(
        `UPDATE supply_contracts 
         SET default_days = default_days + 1,
             consecutive_defaults = $1,
             last_settled_game_day = $2
         WHERE contract_id = $3`,
        [newConsecutive, day, contract.contract_id],
      );

      await tx.query(
        `INSERT INTO contract_delivery_ticks (id, contract_id, game_day, status, quantity_delivered, credits_transferred, penalty_charged, notes)
         VALUES ($1, $2, $3, 'defaulted', 0, 0, $4, 'Insufficient inventory for scheduled delivery')`,
        [crypto.randomUUID(), contract.contract_id, day, penaltyPaid],
      );

      if (isBreached) {
        const remainingCents = moneyToCents(contract.escrow_remaining);
        if (remainingCents > 0n) {
          const buyerAcc = await tx.query<{ account_id: string; balance: string }>(
            "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
            [contract.buyer_id],
          );
          if (buyerAcc.rows[0]) {
            const newBal = centsToMoney(moneyToCents(buyerAcc.rows[0].balance) + remainingCents);
            await tx.query('UPDATE account_balances SET balance = $1 WHERE account_id = $2', [newBal, buyerAcc.rows[0].account_id]);
          }
        }
        await tx.query(
          "UPDATE contract_escrow_vaults SET refunded_amount = refunded_amount + $1, status = 'refunded', updated_at = CURRENT_TIMESTAMP WHERE id = $2",
          [contract.escrow_remaining, contract.vault_id],
        );
        await tx.query("UPDATE supply_contracts SET escrow_remaining = '0.00' WHERE contract_id = $1", [contract.contract_id]);
        await tx.query("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = $1", [contract.contract_id]);
        await tx.query(
          `INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id)
           VALUES ($1, $2, 'contract', 'Supply Contract Terminated', 'Agreement was terminated due to consecutive delivery defaults. Remaining escrow refunded.', $3),
                  ($4, $5, 'contract', 'Supply Contract Terminated', 'Agreement was terminated due to consecutive delivery defaults.', $3)`,
          [crypto.randomUUID(), contract.buyer_id, contract.contract_id, crypto.randomUUID(), contract.seller_id, contract.contract_id],
        );
      }
    }
  }
}

async function completeContracts(tx: PostgresRepository, day: number): Promise<void> {
  const contracts = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; title: string }>("SELECT id, proposer_id, counterparty_id, title FROM negotiated_contracts WHERE status = 'accepted' AND ends_game_day <= $1 FOR UPDATE", [day]);
  for (const contract of contracts.rows) {
    await tx.query("UPDATE negotiated_contracts SET status = 'completed' WHERE id = $1 AND status = 'accepted'", [contract.id]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'contract.completed\',\'A negotiated contract completed\',$3) ON CONFLICT (id) DO NOTHING', [`CONTRACT-COMPLETED-${contract.id}`, day, toNanoMarkup({ contractId: contract.id })]);
    for (const humanId of [contract.proposer_id, contract.counterparty_id]) await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'contract\',\'Contract completed\',$3,$4) ON CONFLICT DO NOTHING', [`CONTRACT-COMPLETE-${contract.id}-${humanId}`, humanId, `${contract.title} completed on game day ${day}.`, contract.id]);
  }
}

async function settleServiceContracts(tx: PostgresRepository, day: number): Promise<void> {
  const contracts = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; amount: string; starts_game_day: number; ends_game_day: number; terms_json: Record<string, unknown> | null }>("SELECT id, proposer_id, counterparty_id, amount, starts_game_day, ends_game_day, terms_json FROM negotiated_contracts WHERE kind = 'intellectual_service' AND status = 'accepted' AND starts_game_day <= $1 AND ends_game_day > $1 FOR UPDATE", [day]);
  for (const contract of contracts.rows) {
    const correlationId = `SERVICE-CONTRACT-${contract.id}-${day}`;
    if ((await tx.query("SELECT 1 FROM ledger_entries WHERE reason_type = 'service_contract_payment' AND correlation_id = $1", [correlationId])).rows[0]) continue;
    const duration = Math.max(1, Number(contract.ends_game_day) - Number(contract.starts_game_day));
    const dailyAmount = centsToMoney(moneyToCents(contract.amount) / BigInt(duration));
    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' FOR UPDATE", [contract.counterparty_id, contract.proposer_id]);
    const payer = accounts.rows.find((row) => row.owner_id === contract.counterparty_id);
    const provider = accounts.rows.find((row) => row.owner_id === contract.proposer_id);
    if (!payer || !provider || moneyToCents(payer.balance) < moneyToCents(dailyAmount)) continue;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: payer.account_id, creditAccount: provider.account_id, amount: dailyAmount, reasonType: 'service_contract_payment', reasonId: contract.id, ruleVersion: 'service-contract-v1', correlationId });
    const terms = contract.terms_json ?? {};
    const providerBusinessId = typeof terms.proposerBusinessId === 'string' ? terms.proposerBusinessId : null;
    const payerBusinessId = typeof terms.counterpartyBusinessId === 'string' ? terms.counterpartyBusinessId : null;
    if (providerBusinessId) await tx.query('UPDATE business_financials SET revenue = revenue + $1, profit = profit + $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [dailyAmount, day, providerBusinessId]);
    if (payerBusinessId) await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [dailyAmount, day, payerBusinessId]);
  }
}

async function settleTechnologyRoyalties(tx: PostgresRepository, day: number): Promise<void> {
  const licenses = await tx.query<{ id: string; licensor_id: string; licensee_id: string; licensee_business_id: string | null; royalty_rate: string }>("SELECT technology_licenses.id, licensor_id, licensee_id, licensee_business_id, royalty_rate FROM technology_licenses JOIN patents ON patents.id = technology_licenses.patent_id WHERE technology_licenses.status = 'active' AND patents.status = 'active' AND licensor_id <> licensee_id");
  for (const license of licenses.rows) {
    const usage = await tx.query<{ amount: string }>('SELECT COALESCE(SUM(amount), 0) AS amount FROM production_events WHERE owner_id = $1 AND game_day = $2', [license.licensee_id, day]);
    const royaltyCents = compoundRateAmountToCents(quantityToCents(usage.rows[0]?.amount ?? '0'), String(license.royalty_rate), '0.1');
    const royalty = centsToMoney(royaltyCents);
    if (royaltyCents <= 0n) continue;
    const correlationId = `ROYALTY-${license.id}-${day}`;
    if ((await tx.query("SELECT 1 FROM ledger_entries WHERE correlation_id = $1 AND reason_type = 'technology_royalty'", [correlationId])).rows[0]) continue;
    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' ORDER BY owner_id FOR UPDATE", [license.licensee_id, license.licensor_id]);
    const buyer = accounts.rows.find((row) => row.owner_id === license.licensee_id);
    const owner = accounts.rows.find((row) => row.owner_id === license.licensor_id);
    if (!buyer || !owner || moneyToCents(buyer.balance) < royaltyCents) {
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,\'technology\',\'Royalty payment pending\',$3,$4) ON CONFLICT DO NOTHING', [`ROYALTY-PENDING-${license.id}-${day}`, license.licensee_id, `The ${royalty} Credit royalty for license ${license.id} is pending until your balance is sufficient.`, license.id]);
      continue;
    }
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: buyer.account_id, creditAccount: owner.account_id, amount: royalty, reasonType: 'technology_royalty', reasonId: license.id, ruleVersion: 'technology-v3', correlationId });
    await tx.query("UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $2, last_game_day = $3, updated_at = CURRENT_TIMESTAMP WHERE business_id = COALESCE($4, (SELECT id FROM businesses WHERE owner_id = $5 AND status = 'active' ORDER BY id LIMIT 1))", [royalty, royalty, day, license.licensee_business_id, license.licensee_id]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,\'technology\',\'Technology royalty paid\',$3,$4), ($5,$6,\'technology\',\'Technology royalty received\',$7,$4)', [crypto.randomUUID(), license.licensee_id, `${royalty} Credits paid for licensed technology usage.`, license.id, crypto.randomUUID(), license.licensor_id, `${royalty} Credits received from licensed technology usage.`]);
  }
}

async function settleBuildingPatentLicenses(tx: PostgresRepository, day: number): Promise<void> {
  const licenses = await tx.query<{
    id: string;
    patent_id: string;
    patent_name: string;
    license_type: string;
    licensee_id: string;
    licensor_corporation_id: string;
    building_id: string | null;
    city_id: string | null;
    is_permanent: boolean;
    expiry_game_day: string;
    royalty_per_day_crd: string;
    status: string;
  }>("SELECT * FROM building_patent_licenses WHERE status NOT IN ('expired', 'suspended')");

  for (const lic of licenses.rows) {
    const expiry = Number(lic.expiry_game_day);
    const royalty = Number(lic.royalty_per_day_crd || 0);

    // Check expiry transitions
    if (!lic.is_permanent && expiry <= day) {
      await tx.query(
        "UPDATE building_patent_licenses SET status = 'expired', updated_at = CURRENT_TIMESTAMP WHERE id = $1",
        [lic.id],
      );
      if (lic.building_id) {
        await tx.query(
          "UPDATE buildings SET patent_license_status = 'expired', updated_at = CURRENT_TIMESTAMP WHERE id = $1",
          [lic.building_id],
        );
      }
      await tx.query(
        `INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id)
         VALUES ($1, $2, 'technology', 'Patent License Expired', $3, $4)
         ON CONFLICT DO NOTHING`,
        [
          crypto.randomUUID(),
          lic.licensee_id,
          `Your license for ${lic.patent_name} has expired. Facility operates at reduced baseline efficiency (-30% output) until renewed.`,
          lic.id,
        ],
      );
      continue;
    } else if (!lic.is_permanent && expiry - day <= 3 && lic.status !== 'renewal_window') {
      await tx.query(
        "UPDATE building_patent_licenses SET status = 'renewal_window', updated_at = CURRENT_TIMESTAMP WHERE id = $1",
        [lic.id],
      );
      if (lic.building_id) {
        await tx.query(
          "UPDATE buildings SET patent_license_status = 'renewal_window', updated_at = CURRENT_TIMESTAMP WHERE id = $1",
          [lic.building_id],
        );
      }
      await tx.query(
        `INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id)
         VALUES ($1, $2, 'technology', 'Patent License Renewal Window Open', $3, $4)
         ON CONFLICT DO NOTHING`,
        [
          crypto.randomUUID(),
          lic.licensee_id,
          `Your patent license for ${lic.patent_name} expires in ${expiry - day} game days. Renew now to maintain peak technological yields.`,
          lic.id,
        ],
      );
    }

    // Settle daily royalties
    if (royalty > 0) {
      const royaltyCents = BigInt(Math.round(royalty * 100));
      const correlationId = `BLD-PAT-ROYALTY-${lic.id}-${day}`;
      const prior = await tx.query("SELECT 1 FROM ledger_entries WHERE correlation_id = $1", [correlationId]);
      if (prior.rows.length === 0) {
        const isCivic = lic.license_type === 'city_civic' && lic.city_id;
        const payerAccount = isCivic
          ? `account-city-${lic.city_id}`
          : (await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [lic.licensee_id])).rows[0]?.account_id;

        if (payerAccount) {
          await transferCredits(tx, {
            ledgerId: crypto.randomUUID(),
            gameDay: day,
            debitAccount: payerAccount,
            creditAccount: `account-corporation-${lic.licensor_corporation_id}`,
            amount: centsToMoney(royaltyCents),
            reasonType: 'building_patent_royalty',
            reasonId: lic.id,
            ruleVersion: 'patent-licensing-v1',
            correlationId,
          }).catch(() => undefined);
        }
      }
    }
  }
}

async function updateFinancialStates(tx: PostgresRepository, day: number): Promise<void> {
  const candidates = await tx.query<{ id: string; kind: string; value: string; profit: string | null; condition: string | null; current: string }>("SELECT businesses.id, 'BUSINESS' AS kind, business_financials.profit AS value, business_financials.profit, businesses.condition, businesses.status AS current FROM businesses JOIN business_financials ON business_financials.business_id = businesses.id UNION ALL SELECT id, 'CITY', treasury, NULL, NULL, 'active' FROM cities UNION ALL SELECT id, 'CORPORATION', treasury, NULL, NULL, 'active' FROM corporations");
  for (const candidate of candidates.rows) {
    const existing = await tx.query<{ status: string; since_game_day: number }>('SELECT status, since_game_day FROM financial_states WHERE institution_id = $1 FOR UPDATE', [candidate.id]);
    const current = existing.rows[0]?.status ?? candidate.current;
    if (current === 'dissolved') continue;
    const numeric = Number(candidate.value);
    const target = candidate.kind === 'BUSINESS'
      ? classifyBusinessFinancialStatus({ profit: candidate.profit, condition: candidate.condition, currentStatus: current, sinceGameDay: existing.rows[0] ? Number(existing.rows[0].since_game_day) : null, gameDay: day })
      : numeric <= 0 ? (existing.rows[0] && day - Number(existing.rows[0].since_game_day) >= 7 ? 'insolvent' : 'distressed') : 'active';
    if (target === current && existing.rows[0]) continue;
    const reason = target === 'active' ? 'Positive operating position restored' : 'Operating reserve is depleted';
    await tx.query('INSERT INTO financial_states (institution_id,institution_kind,status,since_game_day,recovery_game_day,last_reason) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT(institution_id) DO UPDATE SET status=EXCLUDED.status,recovery_game_day=EXCLUDED.recovery_game_day,last_reason=EXCLUDED.last_reason,updated_at=CURRENT_TIMESTAMP', [candidate.id, candidate.kind, target, existing.rows[0]?.since_game_day ?? day, target === 'active' ? day : null, reason]);
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,$4,$5,$6,$7)', [crypto.randomUUID(), candidate.id, candidate.kind, current, target, day, reason]);
    if (candidate.kind === 'BUSINESS') await tx.query('UPDATE businesses SET status = $1 WHERE id = $2', [target === 'active' ? 'active' : 'distressed', candidate.id]);
  }
}

async function dissolveInstitutions(tx: PostgresRepository, day: number): Promise<void> {
  const candidates = await tx.query<{ id: string; kind: string; name: string }>("SELECT institutions.id, institutions.kind, institutions.name FROM institutions JOIN financial_states ON financial_states.institution_id = institutions.id WHERE financial_states.status = 'insolvent' AND $1 - financial_states.since_game_day >= 30 FOR UPDATE", [day]);
  for (const candidate of candidates.rows) {
    const members = candidate.kind === 'CITY'
      ? await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 FOR UPDATE', [candidate.id])
      : candidate.kind === 'CORPORATION'
        ? await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE corporation_id = $1 FOR UPDATE', [candidate.id])
        : { rows: [] } as { rows: Array<{ human_id: string }> };
    if (candidate.kind === 'CITY') {
      await tx.query('UPDATE memberships SET city_id = NULL WHERE city_id = $1', [candidate.id]);
      await tx.query('UPDATE cities SET residents = 0 WHERE id = $1', [candidate.id]);
    } else if (candidate.kind === 'CORPORATION') {
      await tx.query('UPDATE memberships SET corporation_id = NULL WHERE corporation_id = $1', [candidate.id]);
      await tx.query('UPDATE corporations SET member_count = 0 WHERE id = $1', [candidate.id]);
    } else if (candidate.kind === 'BUSINESS') {
      await tx.query("UPDATE businesses SET status = 'bankrupt' WHERE id = $1", [candidate.id]);
    }
    await tx.query("UPDATE institutions SET status = 'dissolved' WHERE id = $1", [candidate.id]);
    await tx.query("UPDATE financial_states SET status = 'dissolved', recovery_game_day = $1, last_reason = 'Institution remained insolvent beyond the engine resolution window', updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2 AND status = 'insolvent'", [day, candidate.id]);
    const reason = 'Institution remained insolvent beyond the engine resolution window';
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,\'insolvent\',\'dissolved\',$4,$5) ON CONFLICT (id) DO NOTHING', [`DISSOLVE-${candidate.id}-${day}`, candidate.id, candidate.kind, day, reason]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'institution.dissolved\',$3,$4) ON CONFLICT (id) DO NOTHING', [`DISSOLVE-${candidate.id}-${day}`, day, `${candidate.kind} ${candidate.name} was dissolved`, toNanoMarkup({ institutionId: candidate.id, releasedMembers: members.rows.length })]);
    for (const member of members.rows) await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'institution\',$3,$4,$5) ON CONFLICT DO NOTHING', [`DISSOLVE-${candidate.id}-${day}-${member.human_id}`, member.human_id, `${candidate.kind} dissolved`, `${candidate.kind} ${candidate.name} was dissolved after prolonged insolvency. Your institutional membership was released.`, candidate.id]);
  }
}

async function snapshotRankings(tx: PostgresRepository, day: number): Promise<void> {
  const [cities, corporations] = await Promise.all([
    tx.query<{ id: string; score: string }>(`SELECT id,
      (LEAST(1, housing_capacity / GREATEST(1, residents::numeric)) * 25
       + LEAST(1, energy_capacity / GREATEST(1, residents::numeric)) * 25
       + LEAST(1, connectivity_capacity / GREATEST(1, residents::numeric)) * 20
       + LEAST(1, health_capacity / 100.0) * 20
       + LEAST(1, GREATEST(0, treasury::numeric) / 10000.0) * 10) AS score
      FROM cities ORDER BY score DESC, residents DESC, id LIMIT 10`),
    tx.query<{ id: string; score: string }>(`SELECT c.id,
      (LEAST(1, GREATEST(0, c.member_count::numeric) / 100.0) * 55
       + LEAST(1, GREATEST(0, c.treasury::numeric) / 25000.0) * 25
       + LEAST(1, (SELECT COUNT(*)::numeric FROM businesses b WHERE b.owner_id IN (SELECT human_id FROM memberships m WHERE m.corporation_id = c.id) AND b.status = 'active') / 10.0) * 20) AS score
      FROM corporations c ORDER BY score DESC, member_count DESC, id LIMIT 10`),
  ]);
  for (const [index, row] of cities.rows.entries()) await tx.query('INSERT INTO rankings_snapshots (id,game_day,ranking_type,entity_id,rank,score) VALUES ($1,$2,\'city_development\',$3,$4,$5) ON CONFLICT (id) DO UPDATE SET score=EXCLUDED.score', [`CITY-${day}-${row.id}`, day, row.id, index + 1, Number(row.score)]);
  for (const [index, row] of corporations.rows.entries()) await tx.query('INSERT INTO rankings_snapshots (id,game_day,ranking_type,entity_id,rank,score) VALUES ($1,$2,\'corporation_strength\',$3,$4,$5) ON CONFLICT (id) DO UPDATE SET score=EXCLUDED.score', [`CORP-${day}-${row.id}`, day, row.id, index + 1, Number(row.score)]);
  const prices = await tx.query<{ product: string; price: string }>('SELECT product, price FROM market_prices');
  for (const p of prices.rows) {
    await tx.query('INSERT INTO rankings_snapshots (id,game_day,ranking_type,entity_id,rank,score) VALUES ($1,$2,$3,$4,1,$5) ON CONFLICT (id) DO UPDATE SET score=EXCLUDED.score', [`PRICE-${day}-${p.product}`, day, `market_price_${p.product}`, p.product, Number(p.price)]);
  }
}

async function processCityDynamics(tx: PostgresRepository, day: number): Promise<void> {
  const cities = await tx.query<{ id: string; residents: number; housing_capacity: number; energy_capacity: number; connectivity_capacity: number; health_capacity: number; treasury: string }>('SELECT * FROM cities WHERE residents > 0 ORDER BY id');
  for (const city of cities.rows) {
    const res = Math.max(1, Number(city.residents));
    if (Number(city.energy_capacity) < res) {
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`BROWNOUT-${city.id}-${day}`, day, 'city.brownout', `Power grid deficit in ${city.id}`, toNanoMarkup({ cityId: city.id, capacity: city.energy_capacity, demand: city.residents })]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'BROWNOUT-NOTICE-' || $1 || '-' || human_id, human_id, 'institution', 'City power shortage', $2, $1 FROM memberships WHERE city_id = $1 ON CONFLICT DO NOTHING", [city.id, `Your city has a power deficit (${city.energy_capacity}/${city.residents} capacity). Support an energy project or secure supplies before production is disrupted.`]);
    }
    if (Number(city.health_capacity) < res * 0.5) {
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`HEALTH-CRISIS-${city.id}-${day}`, day, 'city.healthcare_crisis', `Hospital capacity deficit in ${city.id}`, toNanoMarkup({ cityId: city.id, healthCapacity: city.health_capacity, residents: city.residents })]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'HEALTH-NOTICE-' || $1 || '-' || human_id, human_id, 'institution', 'City health crisis', $2, $1 FROM memberships WHERE city_id = $1 ON CONFLICT DO NOTHING", [city.id, `Health capacity is critically low in your city (${city.health_capacity}/100). Fund a health project or help move resources before services deteriorate further.`]);
    }
  }
  if (cities.rows.length >= 2) {
    const scoredCities = cities.rows.map((c) => {
      const res = Math.max(1, Number(c.residents));
      const housingScore = Math.min(1.2, Number(c.housing_capacity) / res);
      const energyScore = Math.min(1.2, Number(c.energy_capacity) / res);
      const healthScore = Math.min(1.0, Number(c.health_capacity) / 100);
      const connectivityScore = Math.min(1.0, Number(c.connectivity_capacity) / res);
      const totalScore = (housingScore + energyScore + healthScore + connectivityScore) / 4;
      return { ...c, totalScore };
    });
    const bestCity = scoredCities.reduce((prev, curr) => (curr.totalScore > prev.totalScore ? curr : prev), scoredCities[0]);
    const worstCity = scoredCities.reduce((prev, curr) => (curr.totalScore < prev.totalScore ? curr : prev), scoredCities[0]);
    if (bestCity.id !== worstCity.id && bestCity.totalScore >= 0.8 && worstCity.totalScore < 0.6 && Number(worstCity.residents) > 5) {
      // A better city creates an opportunity, not an automatic transfer.
      // Residence is a core player choice: moving changes services, rules,
      // corporation affiliation, and the dynasty's long-term identity.
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`MIGRATION-OPPORTUNITY-${worstCity.id}-${bestCity.id}-${day}`, day, 'city.migration_opportunity', `Residents of ${worstCity.id} can consider moving to ${bestCity.id}`, toNanoMarkup({ fromCityId: worstCity.id, toCityId: bestCity.id, fromScore: worstCity.totalScore, toScore: bestCity.totalScore })]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'MIGRATION-OPPORTUNITY-' || $1 || '-' || human_id, human_id, 'institution', 'A better city is available', $2, $1 FROM memberships WHERE city_id = $1 ON CONFLICT DO NOTHING", [worstCity.id, `City ${bestCity.id} currently offers stronger services. Review the City page if you want to move; no transfer happens automatically.`]);
    }
  }
}

async function processPatentExpirations(tx: PostgresRepository, day: number): Promise<void> {
  const expiredPatents = await tx.query<{ id: string; technology_id: string }>("SELECT id, technology_id FROM patents WHERE expiry_game_day <= $1 AND status = 'active'", [day]);
  if (expiredPatents.rows.length > 0) {
    await tx.query("UPDATE patents SET status = 'expired' WHERE expiry_game_day <= $1 AND status = 'active'", [day]);
    await tx.query("UPDATE technology_licenses SET status = 'expired' WHERE patent_id = ANY($1::text[]) AND status = 'active'", [expiredPatents.rows.map((p) => p.id)]);
    for (const patent of expiredPatents.rows) {
      await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'patent.expired','Patent entered public domain',$3) ON CONFLICT (id) DO NOTHING", [`PATENT-EXPIRED-${patent.id}`, day, toNanoMarkup({ patentId: patent.id, technologyId: patent.technology_id })]);
    }
  }
}

async function ensureMarketLiquidity(tx: PostgresRepository, day: number): Promise<void> {
  await tx.query("UPDATE market_prices SET supply = GREATEST(supply, 10), demand = GREATEST(demand, 10), game_day = $1 WHERE supply <= 1 OR demand <= 1", [day]);
}

async function settleProduction(tx: PostgresRepository, day: number): Promise<number> {
  const machines = await tx.query<{ id: string; owner_id: string; business_id: string | null; productive_capacity: string; utilization: string; condition: string; output_resource: string; input_resource: string; input_per_output: string; focus: string; has_assembly: boolean; has_food_synthesis: boolean }>("SELECT machines.id, machines.owner_id, business_assets.business_id, machines.productive_capacity, machines.utilization, machines.condition, machines.output_resource, machines.input_resource, machines.input_per_output, COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC, started_game_day DESC LIMIT 1), 'efficiency') AS focus, (EXISTS (SELECT 1 FROM technologies WHERE technologies.owner_id = machines.owner_id AND technologies.name = 'Automated Assembly' AND technologies.progress >= 100 AND (business_assets.business_id IS NULL OR EXISTS (SELECT 1 FROM business_technology_adoptions bta WHERE bta.business_id = business_assets.business_id AND bta.technology_id = technologies.id AND bta.status = 'active'))) OR EXISTS (SELECT 1 FROM memberships m JOIN corporation_technology_shares cts ON cts.corporation_id = m.corporation_id AND cts.status = 'active' JOIN patents p ON p.id = cts.patent_id JOIN technologies shared_tech ON shared_tech.id = p.technology_id WHERE m.human_id = machines.owner_id AND shared_tech.name = 'Automated Assembly' AND shared_tech.progress >= 100 AND (business_assets.business_id IS NULL OR EXISTS (SELECT 1 FROM business_technology_adoptions bta WHERE bta.business_id = business_assets.business_id AND bta.technology_id = shared_tech.id AND bta.status = 'active')))) AS has_assembly, (EXISTS (SELECT 1 FROM technologies WHERE technologies.owner_id = machines.owner_id AND technologies.name = 'Food Synthesis' AND technologies.progress >= 100 AND (business_assets.business_id IS NULL OR EXISTS (SELECT 1 FROM business_technology_adoptions bta WHERE bta.business_id = business_assets.business_id AND bta.technology_id = technologies.id AND bta.status = 'active'))) OR EXISTS (SELECT 1 FROM memberships m JOIN corporation_technology_shares cts ON cts.corporation_id = m.corporation_id AND cts.status = 'active' JOIN patents p ON p.id = cts.patent_id JOIN technologies shared_tech ON shared_tech.id = p.technology_id WHERE m.human_id = machines.owner_id AND shared_tech.name = 'Food Synthesis' AND shared_tech.progress >= 100 AND (business_assets.business_id IS NULL OR EXISTS (SELECT 1 FROM business_technology_adoptions bta WHERE bta.business_id = business_assets.business_id AND bta.technology_id = shared_tech.id AND bta.status = 'active')))) AS has_food_synthesis FROM machines LEFT JOIN business_assets ON business_assets.machine_id = machines.id WHERE machines.condition > 0 AND machines.utilization > 0");
  const dynastyPerks = await tx.query<{ human_id: string; perk_key: string }>("SELECT ac.human_id, dp.perk_key FROM auth_credentials ac JOIN dynasties d ON d.email = ac.email JOIN dynasty_perks dp ON dp.dynasty_id = d.id WHERE dp.perk_key = 'planetary_agronomists'");
  const agronomistOwners = new Set(dynastyPerks.rows.map((row) => row.human_id));
  const equippedSeals = await tx.query<{ human_id: string }>("SELECT equipped_by_human_id AS human_id FROM dynasty_heirlooms WHERE heirloom_type = 'founder_seal' AND equipped_by_human_id IS NOT NULL");
  const sealOwners = new Set(equippedSeals.rows.map((row) => row.human_id));
  let events = 0;
  for (const machine of machines.rows) {
    const dynastyOutputFactor = agronomistOwners.has(machine.owner_id) && machine.output_resource === 'food' ? 1.2 : 1;
    const heirloomOutputFactor = sealOwners.has(machine.owner_id) ? 1.1 : 1;
    const technologyOutputFactor = machine.has_food_synthesis && machine.output_resource === 'food' ? 1.2 : machine.has_assembly ? 1.15 : 1;
    const outputFactor = (machine.focus === 'efficiency' ? 1.1 : machine.focus === 'cost' ? 1 : 0.9) * technologyOutputFactor * dynastyOutputFactor * heirloomOutputFactor;
    const inputFactor = machine.focus === 'cost' ? 0.85 : 1;
    const theoretical = Math.max(0, Number(machine.productive_capacity) * Number(machine.utilization) / 100 * Math.min(1, Number(machine.condition) / 100) * 2 * outputFactor);
    const input = await tx.query<{ amount: string }>('SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE', [machine.owner_id, machine.input_resource]);
    const available = Number(input.rows[0]?.amount ?? 0);
    const perOutput = Number(machine.input_per_output) * inputFactor;
    const output = Math.round(Math.min(theoretical, perOutput > 0 ? available / perOutput : theoretical) * 100) / 100;
    const consumed = Math.round(output * perOutput * 100) / 100;
    if (output <= 0 || consumed <= 0) continue;
    const price = await tx.query<{ price: string }>('SELECT price FROM market_prices WHERE product = $1', [machine.input_resource]);
    const inputCost = Math.round(consumed * Number(price.rows[0]?.price ?? 0) * 100) / 100;
    await tx.query('UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3 AND amount >= $1', [consumed, machine.owner_id, machine.input_resource]);
    await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [machine.owner_id, machine.output_resource, output]);
    const eventId = crypto.randomUUID();
    await tx.query('INSERT INTO production_events (id, machine_id, owner_id, resource, amount, game_day) VALUES ($1,$2,$3,$4,$5,$6)', [eventId, machine.id, machine.owner_id, machine.output_resource, output, day]);
    if (machine.business_id) await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [inputCost, day, machine.business_id]);
    events += 1;
  }
  return events;
}

export async function advanceWorld(repository: PostgresRepository, minutesPerTick = 5, idempotencyKey?: string): Promise<{ day: number; minute: number; newDay: boolean; productionEvents: number; marketSettlements: number; alreadyProcessed?: boolean }> {
  validateWorldAdvanceMinutes(minutesPerTick);
  const result = await repository.transaction(async (tx) => {
    if (idempotencyKey) {
      const prior = await tx.query('SELECT id FROM world_events WHERE id = $1', [`SCHEDULED-TICK-${idempotencyKey}`]);
      if (prior.rows[0]) {
        const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
        return { day: Number(world.rows[0]?.game_day ?? 0), minute: Number(world.rows[0]?.game_minute ?? 0), newDay: false, productionEvents: 0, marketSettlements: 0, alreadyProcessed: true };
      }
    }
    const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD' FOR UPDATE");
    const currentDay = Number(world.rows[0]?.game_day ?? 0);
    const currentMinute = Number(world.rows[0]?.game_minute ?? 0);
    const nextMinute = currentMinute + minutesPerTick;
    const newDay = nextMinute >= 1440;
    const offsetInc = newDay ? 1 : 0;
    await tx.query("UPDATE world_state SET game_day = $1, game_minute = $2, simulated_day_offset = COALESCE(simulated_day_offset, 0) + $3 WHERE id = 'WORLD'", [day, minute, offsetInc]);
    const expiringRoles = await tx.query<{ id: string; human_id: string; institution_id: string; role_id: string }>("SELECT id, human_id, institution_id, role_id FROM role_assignments WHERE status = 'active' AND ends_game_day <= $1 FOR UPDATE", [day]);
    await tx.query("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
    for (const role of expiringRoles.rows) {
      await tx.query("INSERT INTO authority_events (id,human_id,institution_id,role_id,action,game_day,reason) VALUES ($1,$2,$3,$4,'expired',$5,'term_completed') ON CONFLICT (human_id,role_id,action,game_day) DO NOTHING", [`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${day}`, role.human_id, role.institution_id, role.role_id, day]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,'governance','Role term completed',$3,$4) ON CONFLICT DO NOTHING", [`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${day}`, role.human_id, `Your term for role ${role.role_id} has ended. You may claim an eligible role again when available.`, role.role_id]);
    }
    await tx.query("UPDATE authority_delegations SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
    await tx.query("UPDATE proposals SET status = 'closed' WHERE status = 'open' AND (closes_game_day, closes_game_minute) <= ($1, $2)", [day, minute]);
    await tx.query("UPDATE machines SET condition = GREATEST(0, condition - GREATEST(0.05, utilization * 0.005 * CASE WHEN ((EXISTS (SELECT 1 FROM technologies WHERE technologies.owner_id = machines.owner_id AND technologies.name = 'Predictive Maintenance' AND technologies.progress >= 100 AND (NOT EXISTS (SELECT 1 FROM business_assets WHERE business_assets.machine_id = machines.id) OR EXISTS (SELECT 1 FROM business_technology_adoptions bta JOIN business_assets adopted_asset ON adopted_asset.business_id = bta.business_id AND adopted_asset.machine_id = machines.id WHERE bta.technology_id = technologies.id AND bta.status = 'active'))) OR EXISTS (SELECT 1 FROM memberships m JOIN corporation_technology_shares cts ON cts.corporation_id = m.corporation_id AND cts.status = 'active' JOIN patents p ON p.id = cts.patent_id JOIN technologies shared_tech ON shared_tech.id = p.technology_id WHERE m.human_id = machines.owner_id AND shared_tech.name = 'Predictive Maintenance' AND shared_tech.progress >= 100 AND (NOT EXISTS (SELECT 1 FROM business_assets WHERE business_assets.machine_id = machines.id) OR EXISTS (SELECT 1 FROM business_technology_adoptions bta JOIN business_assets adopted_asset ON adopted_asset.business_id = bta.business_id AND adopted_asset.machine_id = machines.id WHERE bta.technology_id = shared_tech.id AND bta.status = 'active')))) THEN 0.65 ELSE 1 END * CASE COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC LIMIT 1), 'efficiency') WHEN 'durability' THEN 0.7 WHEN 'safety' THEN 0.8 ELSE 1 END)), maintenance_due = maintenance_due + GREATEST(1, utilization * 0.25)");
    await tx.query("UPDATE machines SET condition = LEAST(100, condition + utilization * 0.001) WHERE owner_id IN (SELECT equipped_by_human_id FROM dynasty_heirlooms WHERE heirloom_type = 'pioneer_chronometer' AND equipped_by_human_id IS NOT NULL)");
    await tx.query("UPDATE market_prices SET price = GREATEST(1, ROUND(price * (1 + LEAST(0.05, GREATEST(-0.05, (demand - supply) / GREATEST(1, supply + demand))))::numeric, 2)), game_day = $1", [day]);
    if (newDay) {
      await expireSocialInitiatives(tx, day);
      await tx.query("UPDATE research_projects SET progress = LEAST(100, progress + CASE WHEN budget > 0 THEN 1 ELSE 0 END) WHERE status = 'active'");
      await tx.query("UPDATE technologies SET progress = LEAST(100, progress + CASE WHEN EXISTS (SELECT 1 FROM research_projects WHERE technology_id = technologies.id AND budget > 0 AND status = 'active') THEN 1 ELSE 0 END)");
      await tx.query("UPDATE cities SET housing_capacity = housing_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'housing' ORDER BY game_day DESC LIMIT 1), 0) / 1000), energy_capacity = energy_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'energy' ORDER BY game_day DESC LIMIT 1), 0) / 1000), connectivity_capacity = connectivity_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'connectivity' ORDER BY game_day DESC LIMIT 1), 0) / 1000), health_capacity = health_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category IN ('health','public-services','maintenance') ORDER BY game_day DESC LIMIT 1), 0) / 1000)");
      await tx.query('UPDATE budgets SET amount = GREATEST(0, amount - 100), game_day = $1 WHERE amount > 0', [day]);
      await tx.query("UPDATE humans SET age_years = age_years + 1, legacy = legacy + CASE WHEN standing > 0 THEN 1 ELSE 0 END WHERE life_status = 'active' AND $1 % 365 = 0", [day]);
      if (day % 365 === 0) await processMortality(tx, day);
      await settleBusinessDepreciation(tx, day);
      await settleWorkforcePayroll(tx, day);
      await settleServiceBusinessRevenue(tx, day);
      await settleInstitutionBusinessEffects(tx, day);
      await settleBusinessTaxes(tx, day);
      await settleBasicLevy(tx, day);
      await settleBuildingUpkeepAndRevenue(tx, day);
      await settleBuildingPatentLicenses(tx, day);
      await settleCivicDividends(tx, day);
      await processCityDynamics(tx, day);
      await processPatentExpirations(tx, day);
      await updateFinancialStates(tx, day);
      await dissolveInstitutions(tx, day);
      await snapshotRankings(tx, day);
    }
    await ensureMarketLiquidity(tx, day);
    await tx.query("UPDATE world_state SET living_cost_index = ROUND(GREATEST(0.5, LEAST(3, (SELECT COALESCE(AVG(price), 1) FROM market_prices) / 50))::numeric, 3), essential_services_index = ROUND(GREATEST(0, LEAST(1, (SELECT COALESCE(MIN(LEAST(LEAST(1, housing_capacity / GREATEST(1, residents)), LEAST(1, energy_capacity / GREATEST(1, residents)), LEAST(1, connectivity_capacity / GREATEST(1, residents)), LEAST(1, health_capacity / 100.0))), 0) FROM cities)))::numeric, 3) WHERE id = 'WORLD'");
    await tx.query("UPDATE world_state SET health = CAST(GREATEST(0, LEAST(100, (SELECT COALESCE(AVG(condition), 68) FROM machines) * COALESCE(essential_services_index, 0.68))) AS INTEGER) WHERE id = 'WORLD'");
    await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'world_clock','A new game tick begins',$3) ON CONFLICT (id) DO NOTHING", [`CLOCK-${day}-${minute}`, day, toNanoMarkup({ newDay })]);
    const productionEvents = await settleProduction(tx, day);
    await settleTechnologyRoyalties(tx, day);
    await runAiMaintenance(tx, day);
    await settleSupplyContracts(tx, day);
    await settleServiceContracts(tx, day);
    await completeContracts(tx, day);
    if (idempotencyKey) {
      await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'scheduled_tick','Scheduled world tick committed',$3) ON CONFLICT (id) DO NOTHING", [`SCHEDULED-TICK-${idempotencyKey}`, day, toNanoMarkup({ day, minute, newDay, productionEvents })]);
    }
    return { day, minute, newDay, productionEvents };
  });
  if (result.alreadyProcessed) return result;
  let marketSettlements = 0;
  for (const product of products) {
    const settled = await settleMarket(repository, product);
    if (settled.filled) marketSettlements += 1;
  }
  return { ...result, marketSettlements };
}
