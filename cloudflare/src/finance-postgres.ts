import type { PostgresRepository } from './repository.ts';
import { postEconomicCreditTransfer } from './financial-postgres.ts';
import { marketAccount, releaseReservation } from './market-escrow.ts';
import { centsToMoney, moneyToCents, taxToCents } from './money.ts';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';

export async function publicSpending(
  repository: PostgresRepository,
  input: { actorId: string; cityId: string; category: string; amount: number; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const role = await tx.query("SELECT id FROM institutions WHERE id = $1 AND administrator_human_id = $2 AND status = 'active'", [input.cityId, input.actorId]);
    if (!role.rows[0]) throw new Error('Institution administrator permission is required');
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const prior = await tx.query<{ transaction_id: string; game_day: number }>("SELECT transaction_id, game_day FROM economic_transactions WHERE correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(amount), gameDay: prior.rows[0].game_day, correlationId: input.correlationId };
    if (amountCents <= 0n) throw new Error('Public spending amount must be positive');
    const cityState = await tx.query<{ status: string }>("SELECT status FROM financial_states WHERE institution_id = $1", [input.cityId]);
    if (cityState.rows[0]?.status === 'receivership' && !input.category.startsWith('essential_service')) {
      throw new Error('City receivership permits essential-service spending only');
    }
    const budget = await tx.query<{ authorized_units: string; spent_units: string; committed_units: string }>(
      'SELECT authorized_units, spent_units, committed_units FROM institution_budgets WHERE institution_id = $1 AND game_period = $2 AND category = $3 FOR UPDATE',
      [input.cityId, day, input.category],
    );
    if (!budget.rows[0] || BigInt(budget.rows[0].authorized_units) - BigInt(budget.rows[0].spent_units) < amountCents) throw new Error('Spending exceeds the institution budget');
    const accounts = await tx.query<{ owner_id: string; account_id: string; balance: string }>(
      `SELECT o.id AS owner_id, a.id AS account_id, a.balance::TEXT AS balance
         FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE o.id = ANY($1::TEXT[]) AND a.asset_id = 1 AND a.account_type = 3
          AND a.is_default_settlement AND a.status = 'active'
        ORDER BY o.id FOR UPDATE`, [['OUC', input.cityId]],
    );
    const city = await tx.query<{ id: string }>('SELECT id FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]);
    const oucAccount = accounts.rows.find((row) => row.owner_id === 'OUC');
    const cityAccount = accounts.rows.find((row) => row.owner_id === input.cityId);
    if (!city.rows[0] || !oucAccount || !cityAccount) throw new Error('V2 OUC or city treasury account is unavailable');
    if (BigInt(oucAccount.balance) < amountCents) throw new Error('OUC treasury cannot fund this spending');
    const posting = await tx.query<{ transaction_id: string }>(
      `SELECT transaction_id FROM earth_post_transaction($1,$2,$3,$4,$5,$6,$7,$8::jsonb)`,
      [input.correlationId, day, 0, 'public_spending', 'ouc', input.cityId, 'finance-v2', JSON.stringify([
        { account_id: oucAccount.account_id, delta: (-amountCents).toString(), reason_code: 'PUBLIC_SPENDING' },
        { account_id: cityAccount.account_id, delta: amountCents.toString(), reason_code: 'PUBLIC_SPENDING' },
      ])],
    );
    await tx.query('UPDATE institution_budgets SET committed_units = committed_units + $1, spent_units = spent_units + $1, updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2 AND game_period = $3 AND category = $4', [amountCents, input.cityId, day, input.category]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'public_spending', `OUC funding reached ${input.cityId}`, toNanoMarkup({ cityId: input.cityId, category: input.category, amount, correlationId: input.correlationId, actorId: input.actorId })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.actorId, 'finance', 'Public spending recorded', `${amount} Credits were routed from the OUC treasury to ${input.cityId} for ${input.category}.`, input.correlationId]);
    const members = await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 AND human_id <> $2', [input.cityId, input.actorId]);
    for (const member of members.rows) {
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), member.human_id, 'finance', 'City funding received', `${amount} Credits were routed to ${input.cityId} for ${input.category}.`, input.correlationId]);
    }
    return { ok: true, amount: Number(amount), cityId: input.cityId, category: input.category, gameDay: day, transactionId: posting.rows[0]?.transaction_id, correlationId: input.correlationId };
  });
}

export async function settleTax(repository: PostgresRepository, humanId: string, taxableAmount: number): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const taxpayer = await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'human' AND status = 'active'", [humanId]);
    const beneficiary = await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = 'OUC' AND status = 'active'");
    if (!taxpayer.rows[0] || !beneficiary.rows[0]) throw new Error('Tax rule or V2 account owner not found');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const rule = await tx.query<{ id: string; rate_bps: number; version: number }>(
      `SELECT id, rate_bps, version FROM tax_rule_versions
        WHERE tax_rule_id = 'TAX-OUC-BASIC'
          AND effective_from_game_day <= $1
          AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
        ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [gameDay]);
    if (!rule.rows[0]) throw new Error('Tax rule version is unavailable for game day');
    const rate = String(Number(rule.rows[0].rate_bps) / 10000);
    const version = Number(rule.rows[0].version);
    const amountCents = taxToCents(taxableAmount, rate);
    const amount = centsToMoney(amountCents);
    const rateNumber = Number(rate);
    const correlationId = `TAX-${humanId}-${gameDay}-${amount}-${version}`;
    const prior = await tx.query<{ id: string; amount_units: string; status: string; game_day: number; rule_version: string }>('SELECT id, amount_units, status, game_day, rule_version FROM tax_obligations WHERE correlation_id = $1', [correlationId]);
    if (prior.rows[0]) return { ok: true, alreadySettled: prior.rows[0].status === 'PAID', amount: Number(centsToMoney(BigInt(prior.rows[0].amount_units))), gameDay: prior.rows[0].game_day, ruleVersion: prior.rows[0].rule_version, correlationId, status: prior.rows[0].status };
    if (amountCents === 0n) return { ok: true, alreadySettled: true, amount: 0, rate: rateNumber, ruleVersion: version, correlationId };
    await tx.query(`INSERT INTO tax_obligations
      (taxpayer_economic_id, beneficiary_economic_id, tax_type, tax_base_units, rate_bps, amount_units, rule_version, game_day, correlation_id)
      VALUES ($1, $2, 'personal_income', $3, $4, $5, $6, $7, $8)`,
      [taxpayer.rows[0].economic_id, beneficiary.rows[0].economic_id, moneyToCents(taxableAmount), Math.round(rateNumber * 10000), amountCents, rule.rows[0].id, gameDay, correlationId]);
    const settlement = await tx.query<{ obligations_paid: string; obligations_partial: string; obligations_arrears: string }>('SELECT * FROM earth_settle_v2_tax_obligations($1)', [gameDay]);
    const obligation = await tx.query<{ status: string }>('SELECT status FROM tax_obligations WHERE correlation_id = $1', [correlationId]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING', [`TAX-SETTLED-${correlationId}`, humanId, 'finance', 'Tax obligation recorded', `${amount} Credits were assessed at rate ${(rateNumber * 100).toFixed(2)}% (rule v${version}); status: ${obligation.rows[0]?.status ?? 'DUE'}.`, correlationId]);
    return { ok: true, amount: Number(amount), rate: rateNumber, ruleVersion: version, correlationId, status: obligation.rows[0]?.status ?? 'DUE', settlement };
  });
}

export async function declarePersonalInsolvency(repository: PostgresRepository, humanId: string, reason: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM personal_financial_states WHERE human_id = $1 AND status = \'bankrupt\'', [humanId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, state: prior.rows[0] };
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query('SELECT * FROM earth_open_personal_bankruptcy($1, $2, $3)', [humanId, day, `BANKRUPTCY-${humanId}-${day}`]);
    const proceeding = await tx.query<{ id: string; debtor_economic_id: string }>('SELECT * FROM bankruptcy_proceedings WHERE correlation_id = $1', [`BANKRUPTCY-${humanId}-${day}`]);
    const metrics = await tx.query<{ serviceable: boolean; materially_insolvent: boolean; due_units: string; liabilities_units: string; realizable_assets_units: string; liquid_units: string }>(
      'SELECT * FROM earth_personal_insolvency_metrics((SELECT economic_id FROM owner_registry WHERE id = $1), $2)', [humanId, day],
    );
    if (!metrics.rows[0]?.materially_insolvent || metrics.rows[0]?.serviceable) throw new Error('Personal insolvency criteria are not met');
    const buildings = await tx.query<{ id: string }>("SELECT id FROM buildings WHERE owner_id = $1 AND ownership_class = 'private' FOR UPDATE", [humanId]);
    if (!proceeding.rows[0]) throw new Error('Bankruptcy proceeding was not created');

    const ownerAccounts = await tx.query<{ account_id: string; asset_id: number; balance: string }>(
      `SELECT id::TEXT AS account_id, asset_id, balance::TEXT AS balance
         FROM economic_accounts
        WHERE owner_economic_id = $1 AND status = 'active' AND account_type NOT IN (7, 8)
        FOR UPDATE`, [proceeding.rows[0].debtor_economic_id],
    );
    for (const account of ownerAccounts.rows) {
      await tx.query(`INSERT INTO bankruptcy_estate_assets
        (proceeding_id, account_id, asset_id, asset_units, liquidation_value_units, source_kind, source_id)
        VALUES ($1,$2,$3,$4,$4,'economic_account',$2)
        ON CONFLICT (proceeding_id, source_kind, source_id) DO UPDATE SET asset_units = EXCLUDED.asset_units, liquidation_value_units = EXCLUDED.liquidation_value_units`,
        [proceeding.rows[0].id, account.account_id, account.asset_id, account.balance]);
    }

    const obligations = await tx.query<{ source_id: string; creditor_economic_id: string; obligation_type: string; priority_class: number; amount_units: string }>(
      `SELECT source_id, creditor_economic_id, obligation_type, priority_class,
              (principal_due_units + interest_due_units)::TEXT AS amount_units
         FROM financial_obligations WHERE debtor_economic_id = $1`, [proceeding.rows[0].debtor_economic_id]);
    for (const obligation of obligations.rows) {
      await tx.query(`INSERT INTO bankruptcy_claims
        (proceeding_id, creditor_economic_id, obligation_type, source_id, priority, amount_units)
        VALUES ($1,$2,$3,$4,$5,$6)
        ON CONFLICT (proceeding_id, obligation_type, source_id) DO NOTHING`,
        [proceeding.rows[0].id, obligation.creditor_economic_id, obligation.obligation_type, obligation.source_id, obligation.priority_class, obligation.amount_units]);
    }

    const orders = await tx.query<{ id: string; product: string; side: string; escrow_account_id: string; reserved_quote_units: string; reserved_base_units: string }>(
      `SELECT id::TEXT AS id, product, side, escrow_account_id::TEXT, reserved_quote_units::TEXT, reserved_base_units::TEXT
         FROM market_orders WHERE owner_economic_id = $1 AND status IN ('open','partial') FOR UPDATE`, [proceeding.rows[0].debtor_economic_id]);
    const assetByProduct: Record<string, number> = { material: 2, components: 3, energy: 4, compute: 5, food: 6 };
    for (const order of orders.rows) {
      const amount = BigInt(order.side === 'buy' ? order.reserved_quote_units : order.reserved_base_units);
      if (amount > 0n && order.escrow_account_id) {
        const destination = await marketAccount(tx, humanId, order.side === 'buy' ? 1 : assetByProduct[order.product]);
        if (!destination) throw new Error(`Cannot release escrow for market order ${order.id}`);
        await releaseReservation(tx, { escrowAccountId: order.escrow_account_id, destinationAccountId: destination, assetId: order.side === 'buy' ? 1 : assetByProduct[order.product], amountUnits: amount, orderId: order.id, gameDay: day, reason: 'BANKRUPTCY_ORDER_CANCEL' });
      }
      await tx.query("UPDATE market_orders SET status = 'cancelled', reserved_quote_units = 0, reserved_base_units = 0, updated_at = CURRENT_TIMESTAMP WHERE id = $1", [order.id]);
    }

    await tx.query("UPDATE buildings SET status = 'closed' WHERE owner_id = $1 AND ownership_class = 'private'", [humanId]);
    await tx.query('UPDATE bankruptcy_proceedings SET status = \'RESOLVED\', resolved_game_day = $1, estate_value_units = $2 WHERE id = $3', [day, metrics.rows[0].realizable_assets_units, proceeding.rows[0].id]);
    await tx.query('INSERT INTO personal_financial_states (human_id, status, since_game_day, protected_credits, last_reason) VALUES ($1,\'bankrupt\',$2,0,$3) ON CONFLICT(human_id) DO UPDATE SET status = EXCLUDED.status, since_game_day = EXCLUDED.since_game_day, last_reason = EXCLUDED.last_reason, updated_at = CURRENT_TIMESTAMP', [humanId, day, reason]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [`PERSONAL-BANKRUPTCY-${humanId}-${day}`, day, 'human.bankruptcy', 'A Human entered insolvency restructuring', toNanoMarkup({ humanId, estateValueUnits: metrics.rows[0].realizable_assets_units, cancelledOrders: orders.rows.length, reason })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), humanId, 'finance', 'Personal insolvency recorded', 'The insolvency proceeding froze new obligations, cancelled open market orders, and recorded the V2 estate and creditor claims.', `PERSONAL-BANKRUPTCY-${humanId}-${day}`]);
    await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [humanId]);
    return { ok: true, state: (await tx.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [humanId])).rows[0], proceedingId: proceeding.rows[0].id, liquidated: { buildings: buildings.rows.length, estimatedValueUnits: metrics.rows[0].realizable_assets_units }, cancelledOrders: orders.rows.length };
  });
}

export async function recoverInstitution(repository: PostgresRepository, input: { humanId: string; institutionId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const institution = await tx.query<{ id: string; kind: 'CITY' | 'CORPORATION' }>("SELECT id, kind FROM institutions WHERE id = $1 AND kind IN ('CITY','CORPORATION') FOR UPDATE", [input.institutionId]);
    if (!institution.rows[0]) throw new Error('Recoverable institution not found');
    const role = await tx.query("SELECT id FROM institutions WHERE id = $1 AND administrator_human_id = $2 AND status = 'active'", [input.institutionId, input.humanId]);
    if (!role.rows[0]) throw new Error('Institution administrator permission is required');
    const state = await tx.query<{ status: string }>("SELECT status FROM financial_states WHERE institution_id = $1 AND status IN ('distressed','insolvent') FOR UPDATE", [input.institutionId]);
    if (!state.rows[0]) throw new Error('Institution is not currently in a recoverable crisis state');
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    if (amountCents <= 0n) throw new Error('Recovery amount must be positive');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const bailout = await tx.query<{ id: string; economic_transaction_id: string; bailout_kind: string }>(
      'SELECT id, economic_transaction_id, bailout_kind FROM earth_post_fiscal_bailout($1, $2, $3, $4)',
      [input.institutionId, amountCents.toString(), input.correlationId, 'Player-authorized fiscal institution bailout'],
    );
    await tx.query("UPDATE financial_states SET status = 'active', recovery_game_day = $1, last_reason = 'Player-authorized crisis recovery', updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2", [gameDay, input.institutionId]);
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,$4,\'active\',$5,$6)', [crypto.randomUUID(), input.institutionId, institution.rows[0].kind, state.rows[0].status, gameDay, 'Player-authorized crisis recovery']);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'financial_recovery', `${institution.rows[0].kind} ${input.institutionId} recovered`, toNanoMarkup({ institutionId: input.institutionId, amount: input.amount, humanId: input.humanId })]);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.humanId, 'finance', 'Institution recovered', `${institution.rows[0].kind} ${input.institutionId} returned to active status after your ${amount} Credit recovery contribution.`, input.institutionId]);
    return { ok: true, institutionId: input.institutionId, amount: Number(amount), status: 'active', bailout: bailout.rows[0] ?? null, correlationId: input.correlationId };
  });
}

export async function declareCorporationInsolvency(
  repository: PostgresRepository,
  input: { institutionId: string; correlationId: string; reason?: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const result = await tx.query<Record<string, unknown>>(
      'SELECT * FROM earth_open_corporation_insolvency($1,$2,$3)',
      [input.institutionId, gameDay, input.correlationId],
    );
    if (!result.rows[0]) throw new Error('Corporate insolvency proceeding was not created');
    await tx.query(
      `INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason, correlation_id)
       VALUES ($1,$2,'CORPORATION','active','restructuring',$3,$4,$5)
       ON CONFLICT (id) DO NOTHING`,
      [`CORPORATION-INSOLVENCY-${input.correlationId}`, input.institutionId, gameDay, input.reason ?? 'V2 corporate insolvency proceeding opened', input.correlationId],
    );
    return { ok: true, gameDay, proceeding: result.rows[0], restrictions: ['no dividends', 'no new loans', 'limited capital expenditure'] };
  });
}

export async function declareCityFiscalReceivership(
  repository: PostgresRepository,
  input: { cityId: string; correlationId: string; reason?: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const result = await tx.query<Record<string, unknown>>(
      'SELECT * FROM earth_open_city_receivership($1,$2,$3)',
      [input.cityId, gameDay, input.correlationId],
    );
    if (!result.rows[0]) throw new Error('City fiscal receivership was not created');
    await tx.query(
      `INSERT INTO bankruptcy_events (id, institution_id, institution_kind, from_status, to_status, game_day, reason, correlation_id)
       VALUES ($1,$2,'CITY','active','receivership',$3,$4,$5)
       ON CONFLICT (id) DO NOTHING`,
      [`CITY-RECEIVERSHIP-${input.correlationId}`, input.cityId, gameDay, input.reason ?? 'V2 city fiscal receivership opened', input.correlationId],
    );
    return { ok: true, gameDay, proceeding: result.rows[0], restrictions: ['nonessential spending', 'dividends', 'new debt'] };
  });
}
