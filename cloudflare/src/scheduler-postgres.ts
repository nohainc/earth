import type { PostgresRepository } from './repository.ts';
import { activatePendingHouseSuccessors, processHouseMortality } from './lifecycle-postgres.ts';
import { postEconomicCreditTransfer } from './financial-postgres.ts';
import { centsToMoney, compoundRateAmountToCents, moneyToCents, quantityToCents, rateAmountToCents } from './money.ts';
import { fromNanoMarkup, toNanoMarkup } from './nano-markup.ts';
import { settleBuildingUpkeepAndRevenueV2 } from './building-settlement-v2.ts';
import { settleCivicDividends } from './civic-dividend-engine.ts';
import { settleLifeMaintenanceInTransaction } from './life-maintenance-postgres.ts';
import { applyPreparedSettlementProfiles } from './daily-settlement-profiles.ts';
import { settleGlobalBank } from './global-bank-settlement-engine.ts';
import { captureEconomyShadowOpening, reconcileEconomyShadowDay } from './economy-shadow.ts';
import { createDailySettlementPhaseRegistry, type DailySettlementPhaseContext } from './daily-settlement-phases.ts';
import { provisionEconomicEntryPartitions } from './economic-entry-partitions.ts';
import type { FeatureConfig } from './feature-config.ts';

export { settleBuildingUpkeepAndRevenueV2, settleCivicDividends };

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

async function settleWorkforcePayroll(tx: PostgresRepository, day: number): Promise<void> {
  return;
  /* legacy Business settlement removed; Human-owned operations are settled
     by the personal ledger and building engines. */
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

async function settleBusinessTaxes(tx: PostgresRepository, day: number): Promise<void> {
  return;
  const rule = await tx.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BUSINESS' AND active = true");
  const allocation = await tx.query<{ city_share: string; corporation_share: string; earth_share: string }>("SELECT city_share, corporation_share, earth_share FROM business_tax_allocation_rules WHERE active = true ORDER BY version DESC LIMIT 1");
  if (!rule.rows[0]) return;
  if (!allocation.rows[0]) throw new Error('An active business-tax allocation rule is required');
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

    const allocationScale = 1000000n;
    const cityShare = BigInt(Math.round(Number(allocation.rows[0].city_share) * Number(allocationScale)));
    const corporationShare = BigInt(Math.round(Number(allocation.rows[0].corporation_share) * Number(allocationScale)));
    const cityCents = (taxCents * cityShare) / allocationScale;
    const corpCents = (taxCents * corporationShare) / allocationScale;
    const oucCents = taxCents - cityCents - corpCents;

    const cityTarget = business.city_id ? `account-city-${business.city_id}` : 'account-ouc-treasury';
    const corpTarget = business.corporation_id ? `account-corporation-${business.corporation_id}` : cityTarget;

    if (cityCents > 0n) {
      await postEconomicCreditTransfer(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: cityTarget, amount: centsToMoney(cityCents), reasonType: 'business_tax_city', reasonId: business.id, ruleVersion: `business-tax-v${rule.rows[0].version}`, correlationId: `${correlationId}-CITY` });
    }
    if (corpCents > 0n) {
      await postEconomicCreditTransfer(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: corpTarget, amount: centsToMoney(corpCents), reasonType: 'business_tax_corp', reasonId: business.id, ruleVersion: `business-tax-v${rule.rows[0].version}`, correlationId: `${correlationId}-CORP` });
    }
    if (oucCents > 0n) {
      await postEconomicCreditTransfer(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-ouc-treasury', amount: centsToMoney(oucCents), reasonType: 'business_tax_ouc', reasonId: business.id, ruleVersion: `business-tax-v${rule.rows[0].version}`, correlationId: `${correlationId}-OUC` });
    }

    await tx.query('UPDATE business_financials SET taxed_revenue = revenue, operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [tax, day, business.id]);
  }
}

async function settleCityCorporateIncomeTax(tx: PostgresRepository, day: number): Promise<number> {
  const businessRule = await tx.query<{ id: string; rate_bps: number; version: number }>(
    `SELECT id, rate_bps, version FROM tax_rule_versions
      WHERE tax_rule_id = 'TAX-OUC-BUSINESS'
        AND effective_from_game_day <= $1
        AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
      ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [day]);
  if (!businessRule.rows[0]) throw new Error('Business tax rule is unavailable for settlement day');
  const cities = await tx.query<{ id: string; corporation_id: string; charter_rules: string | null; gross_income: string; city_economic_id: string; corporation_economic_id: string }>(`
    SELECT c.id, c.corporation_id, corporation_institution.charter_rules,
      city_owner.economic_id AS city_economic_id, corporation_owner.economic_id AS corporation_economic_id,
      COALESCE((SELECT SUM(l.amount) FROM ledger_entries l
        WHERE l.credit_account = 'account-city-' || c.id
          AND l.game_day = $1 AND l.reason_type = 'civic_utility_revenue'), 0) AS gross_income
    FROM cities c
    JOIN owner_registry city_owner ON city_owner.id = c.id AND city_owner.owner_type = 'city' AND city_owner.status = 'active'
    JOIN corporations corp ON corp.id = c.corporation_id
    JOIN owner_registry corporation_owner ON corporation_owner.id = corp.id AND corporation_owner.owner_type = 'corporation' AND corporation_owner.status = 'active'
    JOIN institutions corporation_institution ON corporation_institution.id = corp.institution_id
    WHERE c.corporation_id IS NOT NULL
  `, [day]);
  const ouc = await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = 'OUC'");
  if (!ouc.rows[0]) throw new Error('OUC tax beneficiary is unavailable');
  let assessed = 0;
  for (const city of cities.rows) {
    const rate = charterRate(city.charter_rules, 'incomeTaxBps') ?? Number(businessRule.rows[0].rate_bps) / 10000;
    const gross = moneyToCents(city.gross_income);
    const taxCents = rate > 0 && gross > 0n ? rateAmountToCents(gross, String(rate), 1) : 0n;
    if (taxCents <= 0n) continue;
    const correlationId = `CITY-CORP-INCOME-TAX-${city.id}-${day}`;
    await tx.query(`INSERT INTO tax_obligations
      (taxpayer_economic_id, beneficiary_economic_id, tax_type, tax_base_units, rate_bps, amount_units, rule_version, game_day, correlation_id)
      VALUES ($1, $2, 'corporate_income', $3, $4, $5, 'city-corporate-income-tax-v1', $6, $7)
      ON CONFLICT (correlation_id) DO NOTHING`,
      [city.city_economic_id, city.corporation_economic_id, gross, Math.round(rate * 10000), taxCents, businessRule.rows[0].id, day, correlationId]);
    assessed += 1;
  }
  const settled = await tx.query<{ obligations_paid: string }>('SELECT * FROM earth_settle_v2_tax_obligations($1)', [day]);
  return assessed + Number(settled.rows[0]?.obligations_paid ?? 0);
}

async function settleBasicLevy(tx: PostgresRepository, day: number): Promise<void> {
  const rule = await tx.query<{ id: string; rate_bps: number; version: number }>(
    `SELECT id, rate_bps, version FROM tax_rule_versions
      WHERE tax_rule_id = 'TAX-OUC-BASIC'
        AND effective_from_game_day <= $1
        AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
      ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [day]);
  const world = await tx.query<{ living_cost_index: string }>("SELECT living_cost_index FROM world_state WHERE id = 'WORLD'");
  if (!rule.rows[0]) return;
  const levyBaseCents = compoundRateAmountToCents(10000n, String(world.rows[0]?.living_cost_index ?? '1'));
  const ouc = await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = 'OUC'");
  if (!ouc.rows[0]) throw new Error('OUC tax beneficiary is unavailable');
  const humans = await tx.query<{ id: string; economic_id: string; city_charter: string | null; corporation_charter: string | null }>("SELECT humans.id, owner.economic_id, city_institution.charter_rules AS city_charter, corporation_institution.charter_rules AS corporation_charter FROM humans JOIN owner_registry owner ON owner.id = humans.id LEFT JOIN memberships ON memberships.human_id = humans.id LEFT JOIN institutions city_institution ON city_institution.id = memberships.city_id LEFT JOIN institutions corporation_institution ON corporation_institution.id = memberships.corporation_id WHERE humans.life_status = 'active' AND owner.status = 'active'");
  for (const human of humans.rows) {
    const effectiveIncomeRate = effectiveRate(human.city_charter, human.corporation_charter, 'incomeTaxBps', String(Number(rule.rows[0].rate_bps) / 10000));
    const levyCents = rateAmountToCents(levyBaseCents, effectiveIncomeRate, 1);
    if (levyCents <= 0n) continue;
    const correlationId = `BASIC-LEVY-${human.id}-${day}-v${rule.rows[0].version}`;
    await tx.query(`INSERT INTO tax_obligations
      (taxpayer_economic_id, beneficiary_economic_id, tax_type, tax_base_units, rate_bps, amount_units, rule_version, game_day, correlation_id)
      VALUES ($1, $2, 'basic_levy', $3, $4, $5, $6, $7, $8)
      ON CONFLICT (correlation_id) DO NOTHING`,
      [human.economic_id, ouc.rows[0].economic_id, levyBaseCents, Math.round(Number(effectiveIncomeRate) * 10000), levyCents, rule.rows[0].id, day, correlationId]);
  }
  await tx.query('SELECT * FROM earth_settle_v2_tax_obligations($1)', [day]);
}

async function runAiMaintenance(tx: PostgresRepository, day: number): Promise<void> {
  // AI remains advisory; machine-maintenance automation has been retired.
}

/* retired human-to-human supply and service contract settlement */
async function settleSupplyContracts(tx: PostgresRepository, day: number): Promise<void> {
  return;
}
/*
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
             status = CASE WHEN $2::boolean THEN 'released' ELSE status END,
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
*/

/*
async function completeContracts(tx: PostgresRepository, day: number): Promise<void> {
  const contracts = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; title: string }>("SELECT id, proposer_id, counterparty_id, title FROM negotiated_contracts WHERE status = 'accepted' AND ends_game_day <= $1 FOR UPDATE", [day]);
  for (const contract of contracts.rows) {
    await tx.query("UPDATE negotiated_contracts SET status = 'completed' WHERE id = $1 AND status = 'accepted'", [contract.id]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'contract.completed\',\'A negotiated contract completed\',$3) ON CONFLICT (id) DO NOTHING', [`CONTRACT-COMPLETED-${contract.id}`, day, toNanoMarkup({ contractId: contract.id })]);
    for (const humanId of [contract.proposer_id, contract.counterparty_id]) await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'contract\',\'Contract completed\',$3,$4) ON CONFLICT DO NOTHING', [`CONTRACT-COMPLETE-${contract.id}-${humanId}`, humanId, `${contract.title} completed on game day ${day}.`, contract.id]);
  }
}

async function settleServiceContracts(tx: PostgresRepository, day: number): Promise<void> {
  return;
  const contracts = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; amount: string; starts_game_day: number; ends_game_day: number; terms_markup: string | null; proposer_business_id: string | null; counterparty_business_id: string | null }>("SELECT id, proposer_id, counterparty_id, amount, starts_game_day, ends_game_day, terms_markup, proposer_business_id, counterparty_business_id FROM negotiated_contracts WHERE kind = 'intellectual_service' AND status = 'accepted' AND starts_game_day <= $1 AND ends_game_day > $1 FOR UPDATE", [day]);
  for (const contract of contracts.rows) {
    const correlationId = `SERVICE-CONTRACT-${contract.id}-${day}`;
    if ((await tx.query("SELECT 1 FROM ledger_entries WHERE reason_type = 'service_contract_payment' AND correlation_id = $1", [correlationId])).rows[0]) continue;
    const duration = Math.max(1, Number(contract.ends_game_day) - Number(contract.starts_game_day));
    const dailyAmount = centsToMoney(moneyToCents(contract.amount) / BigInt(duration));
    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' FOR UPDATE", [contract.counterparty_id, contract.proposer_id]);
    const payer = accounts.rows.find((row) => row.owner_id === contract.counterparty_id);
    const provider = accounts.rows.find((row) => row.owner_id === contract.proposer_id);
    if (!payer || !provider || moneyToCents(payer.balance) < moneyToCents(dailyAmount)) continue;
    await postEconomicCreditTransfer(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: payer.account_id, creditAccount: provider.account_id, amount: dailyAmount, reasonType: 'service_contract_payment', reasonId: contract.id, ruleVersion: 'service-contract-v1', correlationId });
    const terms = fromNanoMarkup<Record<string, unknown>>(contract.terms_markup ?? '');
    const providerBusinessId = contract.proposer_business_id ?? (typeof terms.proposerBusinessId === 'string' ? terms.proposerBusinessId : null);
    const payerBusinessId = contract.counterparty_business_id ?? (typeof terms.counterpartyBusinessId === 'string' ? terms.counterpartyBusinessId : null);
    if (providerBusinessId) await tx.query('UPDATE business_financials SET revenue = revenue + $1, profit = profit + $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [dailyAmount, day, providerBusinessId]);
    if (payerBusinessId) await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [dailyAmount, day, payerBusinessId]);
  }
}
*/

async function updateFinancialStates(tx: PostgresRepository, day: number): Promise<void> {
  const candidates = await tx.query<{ id: string; kind: string; value: string; due_units: string; liabilities_units: string; realizable_assets_units: string; current: string }>(`SELECT i.id, i.kind,
      COALESCE((SELECT a.balance FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'), 0)::TEXT AS value,
      COALESCE((SELECT SUM(principal_due_units + interest_due_units) FROM financial_obligations f WHERE f.debtor_economic_id = o.economic_id AND f.due_game_day <= $1 AND f.status NOT IN ('PAID', 'WAIVED')), 0)::TEXT AS due_units,
      COALESCE((SELECT SUM(principal_due_units + interest_due_units) FROM financial_obligations f WHERE f.debtor_economic_id = o.economic_id AND f.status NOT IN ('PAID', 'WAIVED')), 0)::TEXT AS liabilities_units,
      COALESCE((SELECT SUM(a.balance) FROM economic_accounts a WHERE a.owner_economic_id = o.economic_id AND a.status = 'active' AND a.account_type NOT IN (7, 8)), 0)::TEXT AS realizable_assets_units,
      'active' AS current
    FROM institutions i JOIN owner_registry o ON o.id = i.id AND o.owner_type IN ('city', 'corporation') AND o.status = 'active'
    WHERE i.kind IN ('CITY', 'CORPORATION')`, [day]);
  for (const candidate of candidates.rows) {
    const existing = await tx.query<{ status: string; since_game_day: number }>('SELECT status, since_game_day FROM financial_states WHERE institution_id = $1 FOR UPDATE', [candidate.id]);
    const current = existing.rows[0]?.status ?? candidate.current;
    if (current === 'dissolved' || current === 'liquidation' || current === 'bankrupt') continue;
    const unableToService = BigInt(candidate.value) < BigInt(candidate.due_units);
    const materiallyInsolvent = BigInt(candidate.liabilities_units) > BigInt(candidate.realizable_assets_units);
    const city = candidate.kind === 'CITY';
    const healthy = !unableToService && !materiallyInsolvent;
    const target = city
      ? current === 'receivership'
        ? (healthy ? 'recovery' : 'receivership')
        : current === 'recovery'
          ? (healthy ? 'active' : 'receivership')
          : unableToService && materiallyInsolvent
            ? (existing.rows[0] && day - Number(existing.rows[0].since_game_day) >= 7 ? 'receivership' : 'fiscal_stress')
            : 'active'
      : current === 'restructuring'
        ? (day - Number(existing.rows[0]?.since_game_day ?? day) >= 7 ? 'insolvent' : 'restructuring')
        : current === 'distressed'
          ? (day - Number(existing.rows[0]?.since_game_day ?? day) >= 7 ? 'restructuring' : 'distressed')
        : current === 'insolvent'
          ? (day - Number(existing.rows[0]?.since_game_day ?? day) >= 30 ? 'liquidation' : 'insolvent')
        : unableToService && materiallyInsolvent
          ? (existing.rows[0] && day - Number(existing.rows[0].since_game_day) >= 7 ? 'insolvent' : 'distressed')
          : 'active';
    if (target === current && existing.rows[0]) continue;
    const reason = target === 'active'
      ? 'Positive operating position restored'
      : target === 'recovery'
        ? 'City liquidity and mandatory obligations entered recovery'
        : city
          ? 'City fiscal obligations are not currently serviceable'
          : 'Operating reserve is depleted';
    const stateSince = target === current ? Number(existing.rows[0]?.since_game_day ?? day) : day;
    await tx.query('INSERT INTO financial_states (institution_id,institution_kind,status,since_game_day,recovery_game_day,last_reason) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT(institution_id) DO UPDATE SET status=EXCLUDED.status,since_game_day=EXCLUDED.since_game_day,recovery_game_day=EXCLUDED.recovery_game_day,last_reason=EXCLUDED.last_reason,updated_at=CURRENT_TIMESTAMP', [candidate.id, candidate.kind, target, stateSince, target === 'active' ? day : null, reason]);
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,$4,$5,$6,$7)', [crypto.randomUUID(), candidate.id, candidate.kind, current, target, day, reason]);
    if (target !== current) {
      const eventType = target === 'receivership' ? 'RECEIVERSHIP_STARTED' : target === 'restructuring' ? 'RESTRUCTURING_STARTED' : target === 'liquidation' ? 'LIQUIDATION_STARTED' : target === 'active' ? 'FINANCIAL_STATE_RECOVERED' : 'FINANCIAL_STATE_CHANGED';
      await tx.query(`SELECT earth_record_institution_financial_event($1,$2,$3,0,NULL,NULL,$4,NULL,NULL,$5)`, [candidate.id, day, eventType, reason, `financial-state:${candidate.id}:${target}:${day}`]);
    }
    if (!city && target === 'liquidation') {
      await tx.query("UPDATE corporation_insolvency_proceedings SET status = 'LIQUIDATION', liquidation_game_day = $1 WHERE institution_id = $2 AND status IN ('RESTRUCTURING','INSOLVENT')", [day, candidate.id]);
    }
    if (city && target === 'receivership') {
      await tx.query(`INSERT INTO city_fiscal_proceedings
        (city_id, debtor_economic_id, status, opened_game_day, due_obligations_units, treasury_units, recovery_plan, correlation_id)
        SELECT $1, o.economic_id, 'RECEIVERSHIP', $2, $3, $4,
               '{"nonessential_spending":false,"dividends":false,"new_debt":false,"essential_services":true}'::jsonb,
               $5
          FROM owner_registry o
         WHERE o.id = $1 AND o.owner_type = 'city' AND o.status = 'active'
        ON CONFLICT (correlation_id) DO NOTHING`, [candidate.id, day, candidate.due_units, candidate.value, `city-receivership:${candidate.id}:${day}`]);
      await tx.query(`INSERT INTO institution_governance_roles
        (institution_id, human_id, role_code, source_type, source_id, effective_from_game_day, status)
        SELECT i.id, i.administrator_human_id, 'RECEIVERSHIP_RECEIVER', 'EMERGENCY', $1, $2, 'ACTIVE'
          FROM institutions i
         WHERE i.id = $1 AND i.administrator_human_id IS NOT NULL
        ON CONFLICT DO NOTHING`, [`city-receivership:${candidate.id}:${day}`, day]);
    }
    if (city && target === 'active' && ['receivership', 'recovery'].includes(current)) {
      await tx.query("UPDATE city_fiscal_proceedings SET status = 'ACTIVE', recovery_game_day = $1, resolved_game_day = $1 WHERE city_id = $2 AND status IN ('RECEIVERSHIP','RECOVERY')", [day, candidate.id]);
      await tx.query("UPDATE institution_governance_roles SET status = 'ENDED', effective_to_game_day = $1 WHERE institution_id = $2 AND role_code = 'RECEIVERSHIP_RECEIVER' AND status = 'ACTIVE'", [day, candidate.id]);
    }
    if (city && target === 'recovery') {
      await tx.query("UPDATE city_fiscal_proceedings SET status = 'RECOVERY', recovery_game_day = $1 WHERE city_id = $2 AND status = 'RECEIVERSHIP'", [day, candidate.id]);
    }
  }
}

async function dissolveInstitutions(tx: PostgresRepository, day: number): Promise<void> {
  // City fiscal stress is a recoverable public-institution state. Only the
  // corporate insolvency path may reach generic dissolution.
  const candidates = await tx.query<{ id: string; kind: string; name: string }>("SELECT institutions.id, institutions.kind, institutions.name FROM institutions JOIN financial_states ON financial_states.institution_id = institutions.id WHERE institutions.kind = 'CORPORATION' AND financial_states.status = 'liquidation' AND $1 - financial_states.since_game_day >= 1 FOR UPDATE", [day]);
  for (const candidate of candidates.rows) {
    if (candidate.kind === 'CORPORATION') {
      await tx.query('SELECT earth_transfer_dissolved_corporation_ip($1, $2, $3)', [candidate.id, day, `corporation-ip-registry:${candidate.id}:${day}`]);
    }
    const members = await tx.query<{ human_id: string; house_id: string }>(
      'SELECT h.current_human_id AS human_id, a.house_id FROM house_affiliations a JOIN houses h ON h.id = a.house_id WHERE a.corporation_id = $1 AND a.status = \'ACTIVE\' FOR UPDATE OF a', [candidate.id]);
    await tx.query("UPDATE corporation_insolvency_proceedings SET status = 'DISSOLVED', resolved_game_day = $1 WHERE institution_id = $2 AND status = 'LIQUIDATION'", [day, candidate.id]);
    await tx.query("UPDATE institution_budget_commitments c SET status = 'CANCELLED', remaining_units = 0, updated_at = CURRENT_TIMESTAMP FROM institution_budget_lines l JOIN budget_categories bc ON bc.id = l.category_id WHERE c.budget_line_id = l.id AND l.institution_id = $1 AND bc.spending_class = 'DISCRETIONARY' AND c.status IN ('ACTIVE','PARTIALLY_PAID')", [candidate.id]);
    await tx.query("UPDATE house_affiliations SET corporation_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE corporation_id = $1 AND status = 'ACTIVE'", [candidate.id]);
    for (const member of members.rows) await tx.query('SELECT earth_project_house_affiliation_to_memberships($1)', [member.house_id]);
    await tx.query('SELECT earth_refresh_population_projections($1,$2)', [candidate.id, null]);
    await tx.query("UPDATE institutions SET status = 'dissolved' WHERE id = $1", [candidate.id]);
    await tx.query("UPDATE financial_states SET status = 'dissolved', recovery_game_day = $1, last_reason = 'Corporation liquidation completed', updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2 AND status = 'liquidation'", [day, candidate.id]);
    const reason = 'Corporation liquidation completed';
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,\'liquidation\',\'dissolved\',$4,$5) ON CONFLICT (id) DO NOTHING', [`DISSOLVE-${candidate.id}-${day}`, candidate.id, candidate.kind, day, reason]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'institution.dissolved\',$3,$4) ON CONFLICT (id) DO NOTHING', [`DISSOLVE-${candidate.id}-${day}`, day, `${candidate.kind} ${candidate.name} was dissolved`, toNanoMarkup({ institutionId: candidate.id, releasedMembers: members.rows.length, liquidation: true })]);
    for (const member of members.rows) await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'institution\',$3,$4,$5) ON CONFLICT DO NOTHING', [`DISSOLVE-${candidate.id}-${day}-${member.human_id}`, member.human_id, `${candidate.kind} dissolved`, `${candidate.kind} ${candidate.name} completed liquidation. Your institutional affiliation was released.`, candidate.id]);
  }
}

async function snapshotRankings(tx: PostgresRepository, day: number): Promise<void> {
  const [cities, corporations] = await Promise.all([
    tx.query<{ id: string; score: string }>(`SELECT c.id,
      (LEAST(1, housing_capacity / GREATEST(1, residents::numeric)) * 25
       + LEAST(1, energy_capacity / GREATEST(1, residents::numeric)) * 25
       + LEAST(1, connectivity_capacity / GREATEST(1, residents::numeric)) * 20
       + LEAST(1, health_capacity / 100.0) * 20
       + LEAST(1, GREATEST(0, COALESCE((SELECT a.balance / 100.0 FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = c.id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'), 0)) / 10000.0) * 10) AS score
      FROM cities c ORDER BY score DESC, residents DESC, c.id LIMIT 10`),
    tx.query<{ id: string; score: string }>(`SELECT c.id,
      (LEAST(1, GREATEST(0, c.member_count::numeric) / 100.0) * 55
       + LEAST(1, GREATEST(0, COALESCE((SELECT a.balance / 100.0 FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = c.id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'), 0)) / 25000.0) * 25
       + LEAST(1, (SELECT COUNT(*)::numeric FROM buildings b JOIN memberships m ON m.human_id = b.owner_id WHERE m.corporation_id = c.id AND b.ownership_class = 'private' AND b.status = 'active') / 10.0) * 20) AS score
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
  const cities = await tx.query<{ id: string; residents: number; housing_capacity: number; energy_capacity: number; connectivity_capacity: number; health_capacity: number }>('SELECT c.id, c.residents, COALESCE(s.housing_capacity, 0) AS housing_capacity, COALESCE(s.energy_capacity, 0) AS energy_capacity, COALESCE(s.connectivity_capacity, 0) AS connectivity_capacity, COALESCE(s.health_capacity, 0) AS health_capacity FROM cities c LEFT JOIN city_service_capacity_daily s ON s.city_id = c.id AND s.game_day = $1 WHERE c.residents > 0 ORDER BY c.id', [day]);
  for (const city of cities.rows) {
    const res = Math.max(1, Number(city.residents));
    if (Number(city.energy_capacity) < res) {
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`BROWNOUT-${city.id}-${day}`, day, 'city.brownout', `Power grid deficit in ${city.id}`, toNanoMarkup({ cityId: city.id, capacity: city.energy_capacity, demand: city.residents })]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'BROWNOUT-NOTICE-' || $1 || '-' || human_id, human_id, 'institution', 'City power shortage', $2::text, $1 FROM memberships WHERE city_id = $1 ON CONFLICT DO NOTHING", [city.id, `Your city has a power deficit (${city.energy_capacity}/${city.residents} capacity). Support an energy project or secure supplies before production is disrupted.`]);
    }
    if (Number(city.health_capacity) < res * 0.5) {
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`HEALTH-CRISIS-${city.id}-${day}`, day, 'city.healthcare_crisis', `Hospital capacity deficit in ${city.id}`, toNanoMarkup({ cityId: city.id, healthCapacity: city.health_capacity, residents: city.residents })]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'HEALTH-NOTICE-' || $1 || '-' || human_id, human_id, 'institution', 'City health crisis', $2::text, $1 FROM memberships WHERE city_id = $1 ON CONFLICT DO NOTHING", [city.id, `Health capacity is critically low in your city (${city.health_capacity}/100). Fund a health project or help move resources before services deteriorate further.`]);
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
      // corporation affiliation, and the house's long-term identity.
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (id) DO NOTHING', [`MIGRATION-OPPORTUNITY-${worstCity.id}-${bestCity.id}-${day}`, day, 'city.migration_opportunity', `Residents of ${worstCity.id} can consider moving to ${bestCity.id}`, toNanoMarkup({ fromCityId: worstCity.id, toCityId: bestCity.id, fromScore: worstCity.totalScore, toScore: bestCity.totalScore })]);
      await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) SELECT 'MIGRATION-OPPORTUNITY-' || $1 || '-' || human_id, human_id, 'institution', 'A better city is available', $2::text, $1 FROM memberships WHERE city_id = $1 ON CONFLICT DO NOTHING", [worstCity.id, `City ${bestCity.id} currently offers stronger services. Review the City page if you want to move; no transfer happens automatically.`]);
    }
  }
}

async function refreshCityServiceProjections(tx: PostgresRepository, day: number): Promise<void> {
  await tx.query('SELECT earth_refresh_city_service_capacity_daily($1)', [day]);
}

async function settleMandatoryBudgetPayments(tx: PostgresRepository, day: number): Promise<number> {
  const result = await tx.query<{ count: string }>(`SELECT COUNT(*)::text AS count
    FROM institution_budget_commitments c
    JOIN institution_budget_lines l ON l.id = c.budget_line_id
    JOIN budget_categories bc ON bc.id = l.category_id
   WHERE bc.spending_class = 'MANDATORY'
     AND c.status IN ('ACTIVE','PARTIALLY_PAID')
     AND c.due_game_day <= $1`, [day]);
  return Number(result.rows[0]?.count ?? 0);
}

async function settleScheduledBudgetPayments(tx: PostgresRepository, day: number): Promise<number> {
  const result = await tx.query<{ count: string }>(`SELECT COUNT(*)::text AS count
    FROM institution_budget_commitments c
   WHERE c.status IN ('ACTIVE','PARTIALLY_PAID') AND c.due_game_day <= $1`, [day]);
  return Number(result.rows[0]?.count ?? 0);
}

async function settleProduction(tx: PostgresRepository, day: number): Promise<number> {
  // Buildings are the productive assets; machine-based production was retired in migration 069.
  void tx; void day;
  return 0;
}

type ResumablePhaseWork = (tx: PostgresRepository) => Promise<unknown>;
export type SettlementResult =
  | { status: 'completed'; gameDay: number }
  | { status: 'busy'; gameDay: number; phase?: string }
  | { status: 'partial'; gameDay: number; phase: string }
  | { status: 'failed'; gameDay: number; error: string };
type PhaseRunResult = 'claimed' | 'completed' | 'busy';

async function runResumablePhase(
  repository: PostgresRepository,
  day: number,
  phase: string,
  shard: string,
  leaseOwner: string,
  work: ResumablePhaseWork,
): Promise<PhaseRunResult> {
  const claim = await repository.transaction(async (tx) => {
    const result = await tx.query<{ claimed: boolean; status: string; attempt_count: number }>(
      'SELECT * FROM earth_claim_settlement_phase($1,$2,$3,$4,$5)',
      [day, phase, shard, leaseOwner, 300],
    );
    return result.rows[0] ?? { claimed: false, status: 'missing', attempt_count: 0 };
  });
  if (!claim.claimed) return claim.status === 'completed' ? 'completed' : 'busy';

  const heartbeatTimer = setInterval(() => {
    void repository.query('SELECT earth_heartbeat_settlement_phase($1,$2,$3,$4)', [day, phase, shard, leaseOwner]).catch(() => undefined);
  }, 60_000);
  try {
    const rowsProcessed = await repository.transaction(async (tx) => {
      const result = await work(tx);
      return typeof result === 'number' ? result : 0;
    });
    const heartbeat = await repository.query<{ heartbeat: boolean }>(
      'SELECT earth_heartbeat_settlement_phase($1,$2,$3,$4)',
      [day, phase, shard, leaseOwner],
    );
    if (heartbeat.rows.length === 0) throw new Error(`Settlement phase lease lost for ${day}/${phase}/${shard}`);
    const completion = await repository.query<{ completed: boolean }>(
      'SELECT earth_complete_settlement_phase($1,$2,$3,$4,$5)',
      [day, phase, shard, leaseOwner, rowsProcessed],
    );
    if (completion.rows.length === 0) throw new Error(`Settlement phase completion lease lost for ${day}/${phase}/${shard}`);
    return 'claimed';
  } catch (error) {
    await repository.query(
      'SELECT earth_fail_settlement_phase($1,$2,$3,$4,$5)',
      [day, phase, shard, leaseOwner, error instanceof Error ? error.message : 'Unknown settlement phase error'],
    ).catch(() => undefined);
    throw error;
  } finally {
    clearInterval(heartbeatTimer);
  }
}

async function settleResearchAndProgress(tx: PostgresRepository, day: number): Promise<void> {
  await tx.query('SELECT earth_settle_research_and_progress_v2($1)', [day]);
}

async function settleLifecycle(tx: PostgresRepository, day: number): Promise<void> {
  await tx.query("UPDATE humans SET age_years = age_years + 1, legacy = legacy + CASE WHEN standing > 0 THEN 1 ELSE 0 END WHERE life_status = 'active' AND $1 % 365 = 0", [day]);
  if (day % 365 === 0) await processHouseMortality(tx, day);
}

/**
 * Worker-safe settlement runner. Each phase/shard is claimed and committed
 * independently, so an interrupted invocation resumes at the first unfinished
 * unit instead of reopening the completed work for the day.
 */
export async function runResumableSettlementDay(
  repository: PostgresRepository,
  day: number,
  leaseOwner = `settlement-worker:${crypto.randomUUID()}`,
  features?: FeatureConfig,
): Promise<SettlementResult> {
  const claim = await repository.transaction(async (tx) => tx.query<{ claimed: boolean; status: string; attempt_count: number; current_phase: string | null }>(
    'SELECT * FROM earth_claim_settlement_day($1,$2,$3)', [day, leaseOwner, 300],
  ));
  const dayClaim = claim.rows[0];
  if (!dayClaim?.claimed) {
    if (dayClaim?.status === 'completed' || dayClaim?.status === 'baseline') return { status: 'completed', gameDay: day };
    return { status: 'busy', gameDay: day, phase: dayClaim?.current_phase ?? undefined };
  }
  const run = await repository.query<{ shard_count: number }>(
    'SELECT shard_count FROM daily_settlement_runs WHERE game_day = $1', [day],
  );
  const shardCount = Math.max(1, Math.min(64, Number(run.rows[0]?.shard_count ?? 64)));

  const context = (tx: PostgresRepository, shard?: number): DailySettlementPhaseContext => ({ tx, day, shard });
  const phases = createDailySettlementPhaseRegistry({
    activateSuccessors: ({ tx }) => activatePendingHouseSuccessors(tx, day),
    preparePartitions: ({ tx }) => provisionEconomicEntryPartitions(tx, day),
    rebuildProfiles: ({ tx, shard }) => tx.query<{ rebuilt_count: string }>('SELECT earth_rebuild_dirty_profiles($1::smallint,$2::bigint) AS rebuilt_count', [shard, day]).then((result) => Number(result.rows[0]?.rebuilt_count ?? 0)),
    profileSettlement: ({ tx }) => applyPreparedSettlementProfiles(tx, day),
    lifeMaintenance: async ({ tx }) => {
      const result = await settleLifeMaintenanceInTransaction(tx, day);
      await tx.query('SELECT earth_refresh_human_daily_needs($1)', [day]);
      return result;
    },
    basicLevy: ({ tx }) => settleBasicLevy(tx, day),
    ipLicenseBilling: ({ tx }) => features?.technologyLicenses === false ? Promise.resolve() : tx.query('SELECT earth_settle_technology_license_fees($1)', [day]),
    buildingSettlement: async ({ tx }) => {
      await tx.query('SELECT earth_rebuild_corporation_technology_modifier_cache($1)', [day]);
      await tx.query('SELECT earth_refresh_technology_modifier_sources($1)', [day]);
      return settleBuildingUpkeepAndRevenueV2(tx, day);
    },
    cityCorporateIncomeTax: ({ tx }) => settleCityCorporateIncomeTax(tx, day),
    globalBank: ({ tx }) => features?.bankDeposits === false && features?.bankLoans === false ? Promise.resolve() : settleGlobalBank(tx, day),
    bankHealth: ({ tx }) => features?.bankDeposits === false && features?.bankLoans === false ? Promise.resolve() : tx.query('SELECT earth_evaluate_global_bank_resolution($1)', [day]),
    mandatoryBudgetPayments: ({ tx }) => settleMandatoryBudgetPayments(tx, day),
    scheduledBudgetPayments: ({ tx }) => settleScheduledBudgetPayments(tx, day),
    cityServiceProjections: ({ tx }) => refreshCityServiceProjections(tx, day),
    cityDynamics: ({ tx }) => processCityDynamics(tx, day),
    budgetDividendEligibility: ({ tx }) => settleCivicDividends(tx, day),
    patentExpirations: ({ tx }) => features?.patents === false ? Promise.resolve() : tx.query('SELECT earth_finalize_technology_public_domain($1)', [day]),
    researchAndProgress: ({ tx }) => settleResearchAndProgress(tx, day),
    lifecycle: ({ tx }) => features?.mortality === false ? Promise.resolve() : settleLifecycle(tx, day),
    postSuccessionAccessRefresh: async ({ tx }) => {
      await tx.query('SELECT earth_rebuild_corporation_technology_modifier_cache($1)', [day]);
      return tx.query('SELECT earth_refresh_technology_modifier_sources($1)', [day]);
    },
    financialStates: ({ tx }) => features?.institutionDistress === false ? Promise.resolve() : updateFinancialStates(tx, day),
    institutionDissolution: ({ tx }) => features?.forcedLiquidation === false ? Promise.resolve() : dissolveInstitutions(tx, day),
    financialProjections: async ({ tx }) => {
      await tx.query('SELECT earth_refresh_daily_financial_projections($1)', [day]);
      return tx.query('SELECT earth_refresh_institution_financial_projection_fields($1)', [day]);
    },
    rankingsSnapshot: ({ tx }) => snapshotRankings(tx, day),
    endOfDaySnapshots: ({ tx }) => captureEndOfDaySnapshots(tx, day),
  });
  const dayHeartbeatTimer = setInterval(() => {
    void repository.query('SELECT earth_heartbeat_settlement_day($1,$2)', [day, leaseOwner]).catch(() => undefined);
  }, 60_000);
  try {
    for (let phaseIndex = 0; phaseIndex < phases.length; phaseIndex += 1) {
      const phase = phases[phaseIndex];
      const prerequisites = phases.slice(0, phaseIndex);
      if (prerequisites.length > 0) {
        const barrier = await repository.query<{ incomplete: string }>(
          `SELECT COUNT(*) FILTER (WHERE status <> 'completed')::bigint AS incomplete
             FROM daily_settlement_phase_runs
            WHERE game_day = $1 AND phase = ANY($2::text[])`,
          [day, prerequisites.map((item) => item.id)],
        );
        if (Number(barrier.rows[0]?.incomplete ?? 0) > 0) return { status: 'partial', gameDay: day, phase: phase.id };
      }
      const dayHeartbeat = await repository.query<{ heartbeat: boolean }>('SELECT earth_heartbeat_settlement_day($1,$2)', [day, leaseOwner]);
      if (dayHeartbeat.rows.length === 0) throw new Error(`Settlement day lease lost for ${day}`);
      const phaseState = await repository.query(
        `UPDATE daily_settlement_runs
            SET current_phase = $3, updated_at = CURRENT_TIMESTAMP
          WHERE game_day = $1 AND status = 'running' AND lease_owner = $2`,
        [day, leaseOwner, phase.id],
      );
      if (phaseState.rowCount !== 1) throw new Error(`Settlement day lease lost before phase ${day}/${phase.id}`);
      if (phase.shardMode === 'owner-shards') {
        for (let shard = 0; shard < shardCount; shard += 1) {
          const outcome = await runResumablePhase(repository, day, phase.id, String(shard), leaseOwner, (tx) => phase.execute(context(tx, shard)));
          if (outcome === 'busy') return { status: 'busy', gameDay: day, phase: phase.id };
        }
      } else {
        const outcome = await runResumablePhase(repository, day, phase.id, 'all', leaseOwner, (tx) => phase.execute(context(tx)));
        if (outcome === 'busy') return { status: 'busy', gameDay: day, phase: phase.id };
      }
    }
    const completion = await repository.query<{ completed: boolean }>(
      'SELECT earth_complete_settlement_day($1,$2)', [day, leaseOwner],
    );
    if (completion.rows.length === 0) throw new Error(`Settlement day completion lease lost for ${day}`);
    return { status: 'completed', gameDay: day };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown settlement day error';
    await repository.query('SELECT earth_fail_settlement_day($1,$2,$3)', [day, leaseOwner, message]).catch(() => undefined);
    return { status: 'failed', gameDay: day, error: message };
  } finally {
    clearInterval(dayHeartbeatTimer);
  }
}

async function captureEndOfDaySnapshots(tx: PostgresRepository, day: number): Promise<number> {
  const result = await tx.query<{ owner_id: string }>(
    `WITH credits AS (
       SELECT owner_id, SUM(balance)::numeric AS balance
       FROM account_balances WHERE currency = 'CREDIT' GROUP BY owner_id
     ), resources AS (
       SELECT owner_id, jsonb_object_agg(resource, amount) AS values
       FROM resource_balances GROUP BY owner_id
     ), earned AS (
       SELECT accounts.owner_id, SUM(entries.amount)::numeric AS amount
       FROM ledger_entries entries
       JOIN account_balances accounts ON accounts.account_id = entries.credit_account
       WHERE entries.game_day <= $1 GROUP BY accounts.owner_id
     ), spent AS (
       SELECT accounts.owner_id, SUM(entries.amount)::numeric AS amount
       FROM ledger_entries entries
       JOIN account_balances accounts ON accounts.account_id = entries.debit_account
       WHERE entries.game_day <= $1 GROUP BY accounts.owner_id
     )
     INSERT INTO entity_end_of_day_snapshots (owner_id, game_day, owner_kind, credits, resources, cumulative_metrics)
     SELECT owners.source_id,
            $1,
            owners.owner_type,
            COALESCE(credits.balance, 0),
            COALESCE(resources.values, '{}'::jsonb),
            jsonb_build_object(
              'credits_earned', COALESCE(earned.amount, 0),
              'credits_spent', COALESCE(spent.amount, 0)
            )
     FROM owner_registry owners
     LEFT JOIN credits ON credits.owner_id = owners.source_id
     LEFT JOIN resources ON resources.owner_id = owners.source_id
     LEFT JOIN earned ON earned.owner_id = owners.source_id
     LEFT JOIN spent ON spent.owner_id = owners.source_id
     WHERE owners.status = 'active'
     ON CONFLICT (owner_id, game_day) DO NOTHING
     RETURNING owner_id`,
    [day],
  );
  return result.rows.length;
}


export async function runWorldSchedulerTick(repository: PostgresRepository, idempotencyKey?: string, features?: FeatureConfig): Promise<{ day: number; minute: number; newDay: boolean; settledGameDay?: number; settlementStatus?: SettlementResult['status']; productionEvents: number; marketSettlements: number; alreadyProcessed?: boolean }> {
  let pendingResumableSettlementDay: number | null = null;
  let result: { day: number; minute: number; newDay: boolean; settledGameDay?: number; settlementStatus?: SettlementResult['status']; productionEvents: number; marketSettlements: number; alreadyProcessed?: boolean };
  result = await repository.transaction(async (tx) => {
    if (idempotencyKey) {
      const prior = await tx.query('SELECT id FROM world_events WHERE id = $1', [`SCHEDULED-TICK-${idempotencyKey}`]);
      if (prior.rows[0]) {
        const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
        return { day: Number(world.rows[0]?.game_day ?? 0), minute: Number(world.rows[0]?.game_minute ?? 0), newDay: false, productionEvents: 0, marketSettlements: 0, alreadyProcessed: true };
      }
    }
    await tx.query("SELECT id FROM world_state WHERE id = 'WORLD' FOR UPDATE");
    const clock = await tx.query<{ total_game_minutes: string; game_day: string; game_minute: number }>(
      `SELECT t.total_game_minutes,
              earth_game_day_from_total_minutes(t.total_game_minutes) AS game_day,
              earth_minute_of_day_from_total_minutes(t.total_game_minutes) AS game_minute
       FROM earth_get_current_game_time() t`,
    );
    const day = Number(clock.rows[0]?.game_day ?? 1);
    const minute = Number(clock.rows[0]?.game_minute ?? 0);
    const totalGameMinutes = Number(clock.rows[0]?.total_game_minutes ?? 0);
    await tx.query("UPDATE world_state SET game_day = $1, game_minute = $2, total_game_minutes = $3 WHERE id = 'WORLD'", [day, minute, totalGameMinutes]);
    await tx.query("UPDATE proposals SET status = 'closed' WHERE status = 'open' AND (closes_game_day, closes_game_minute) <= ($1::bigint, $2::integer)", [day, minute]);
    const control = await tx.query<{ status: string }>("SELECT status FROM daily_settlement_control WHERE id = 'WORLD' FOR UPDATE");
    const active = control.rows[0]?.status === 'active';
    const watermark = await tx.query<{ settlement_watermark: string }>(
      'SELECT earth_settlement_watermark($1)::text AS settlement_watermark', [day],
    );
    const nextDay = Number(watermark.rows[0]?.settlement_watermark ?? 0) + 1;
    const settlementDay = active && nextDay < day ? nextDay : null;
    if (settlementDay !== null) pendingResumableSettlementDay = settlementDay;
    await tx.query("UPDATE world_state SET living_cost_index = ROUND(GREATEST(0.5, LEAST(3, (SELECT COALESCE(AVG(price), 1) FROM market_prices) / 50))::numeric, 3), essential_services_index = ROUND(GREATEST(0, LEAST(1, (SELECT COALESCE(MIN(LEAST(LEAST(1, housing_capacity / GREATEST(1, residents)), LEAST(1, energy_capacity / GREATEST(1, residents)), LEAST(1, connectivity_capacity / GREATEST(1, residents)), LEAST(1, health_capacity / 100.0))), 0) FROM cities)))::numeric, 3) WHERE id = 'WORLD'");
    await tx.query("UPDATE world_state SET health = CAST(GREATEST(0, LEAST(100, (SELECT COALESCE(AVG(CASE WHEN status = 'active' THEN 100 ELSE 0 END), 68) FROM buildings) * COALESCE(essential_services_index, 0.68))) AS INTEGER) WHERE id = 'WORLD'");
    const productionEvents = await settleProduction(tx, day);
    await runAiMaintenance(tx, day);
    if (idempotencyKey) {
      await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'scheduled_tick','Scheduled world tick committed',$3) ON CONFLICT (id) DO NOTHING", [`SCHEDULED-TICK-${idempotencyKey}`, day, JSON.stringify({ day, minute, newDay: settlementDay !== null, productionEvents })]);
    }
    return { day, minute, newDay: settlementDay !== null, settledGameDay: settlementDay ?? undefined, productionEvents };
    });
  if (result.alreadyProcessed) return result;
  let settlementStatus: SettlementResult['status'] | undefined;
  if (pendingResumableSettlementDay !== null) {
    await captureEconomyShadowOpening(repository, pendingResumableSettlementDay);
    const settlement = await runResumableSettlementDay(repository, pendingResumableSettlementDay, `scheduler:${idempotencyKey ?? crypto.randomUUID()}`, features);
    settlementStatus = settlement.status;
    if (settlement.status === 'completed') await reconcileEconomyShadowDay(repository, pendingResumableSettlementDay);
  }
  return { ...result, settlementStatus, marketSettlements: 0 };
}
