import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { resolveOrganizationAuthority } from './organization-authority.ts';

const TOTAL_OWNERSHIP_UNITS = 10000n;

async function currentDay(tx: PostgresRepository): Promise<number> {
  return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
}

export async function getAssetOwnership(repository: PostgresRepository, assetType: string, assetId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT id, asset_type, asset_id, holder_type, holder_id, ownership_class, units::TEXT, effective_from_game_day, effective_to_game_day, status FROM asset_ownership_positions WHERE asset_type = $1 AND asset_id = $2 AND status = 'ACTIVE' AND effective_to_game_day IS NULL ORDER BY holder_type, holder_id`, [assetType.toUpperCase(), assetId]);
  const total = result.rows.reduce((sum, row) => sum + BigInt(String(row.units)), 0n);
  if (total > TOTAL_OWNERSHIP_UNITS) throw new Error('Ownership conservation invariant failed');
  return { assetType: assetType.toUpperCase(), assetId, totalUnits: total.toString(), authorizedTotalUnits: TOTAL_OWNERSHIP_UNITS.toString(), positions: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function subscribeToAssetOwnership(repository: PostgresRepository, input: { organizationId: string; assetId: string; investorType: 'HOUSE' | 'ORGANIZATION'; investorId: string; units: string; priceUnits: string; sourceAccountId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM capitalization_events WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: 'ECONOMIC_OWNER' });
    const units = BigInt(input.units); const price = BigInt(input.priceUnits); const amount = units * price;
    if (units <= 0n || price <= 0n) throw new Error('Ownership subscription units and price must be positive');
    const building = (await tx.query<{ owner_economic_id: string }>('SELECT owner_economic_id FROM buildings WHERE id = $1 AND status = \'ACTIVE\' FOR UPDATE', [input.assetId])).rows[0];
    const legalOwner = (await tx.query<{ id: string }>('SELECT id FROM owner_registry WHERE economic_id = $1 AND id = $2 AND owner_type = \'ORGANIZATION\'', [building?.owner_economic_id ?? '', input.organizationId])).rows[0];
    if (!building || !legalOwner) throw new Error('Organization does not legally own this asset');
    const day = await currentDay(tx);
    const positions = await tx.query<{ id: string; holder_type: string; holder_id: string; units: string }>(`SELECT id, holder_type, holder_id, units::TEXT FROM asset_ownership_positions WHERE asset_type = 'BUILDING' AND asset_id = $1 AND status = 'ACTIVE' AND effective_from_game_day <= $2 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2) FOR UPDATE`, [input.assetId, day]);
    const issued = positions.rows.reduce((sum, row) => sum + BigInt(row.units), 0n);
    if (issued !== TOTAL_OWNERSHIP_UNITS) throw new Error('Ownership conservation invariant failed before subscription');
    const legalPosition = positions.rows.find((position) => position.holder_type === 'ORGANIZATION' && position.holder_id === input.organizationId);
    if (!legalPosition || BigInt(legalPosition.units) < units) throw new Error('Organization has insufficient ownership units to dilute');
    const investor = (await tx.query<{ economic_id: string }>('SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = $2', [input.investorId, input.investorType])).rows[0];
    const destination = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = \'TREASURY\' AND status = \'ACTIVE\'', [building.owner_economic_id])).rows[0];
    const source = (await tx.query<{ id: string; balance_units: string }>('SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE id = $1 AND owner_economic_id = $2 AND asset_id = 1 AND status = \'ACTIVE\' FOR UPDATE', [input.sourceAccountId, investor?.economic_id ?? ''])).rows[0];
    if (!investor || !source || !destination || BigInt(source.balance_units) < amount) throw new Error('Investor CREDIT balance or Organization destination account is unavailable');
    const posted = await tx.query<{ transaction_id: string; created: boolean }>('SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,\'CAPITAL_SUBSCRIPTION\',$3,$4,\'ownership-v1\',$5::JSONB)', [input.correlationId, day, input.investorType, input.investorId, JSON.stringify([{ account_id: source.id, asset_id: 1, delta_units: (-amount).toString() }, { account_id: destination.id, asset_id: 1, delta_units: amount.toString() }])]);
    if (!posted.rows[0]?.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    const eventId = `CAP-${input.correlationId}`;
    await tx.query(`INSERT INTO capitalization_events (id, asset_type, asset_id, organization_id, investor_type, investor_id, units, price_units, ownership_class, economic_transaction_id, game_day, correlation_id) VALUES ($1,'BUILDING',$2,$3,$4,$5,$6,$7,'COMMON',$8,$9,$10)`, [eventId, input.assetId, input.organizationId, input.investorType, input.investorId, units.toString(), price.toString(), posted.rows[0].transaction_id, day, input.correlationId]);
    await tx.query(`UPDATE asset_ownership_positions SET status = 'SUPERSEDED', effective_to_game_day = $2 WHERE id = $1`, [legalPosition.id, day]);
    const remainingOwnerUnits = BigInt(legalPosition.units) - units;
    if (remainingOwnerUnits > 0n) await tx.query(`INSERT INTO asset_ownership_positions (id, asset_type, asset_id, holder_type, holder_id, units, effective_from_game_day, correlation_id) VALUES ($1,'BUILDING',$2,'ORGANIZATION',$3,$4,$5,$6)`, [`OWN-${input.assetId}-ORGANIZATION-${input.organizationId}-${input.correlationId}`, input.assetId, input.organizationId, remainingOwnerUnits.toString(), day + 1, `${input.correlationId}:dilution`]);
    await tx.query(`INSERT INTO asset_ownership_positions (id, asset_type, asset_id, holder_type, holder_id, units, effective_from_game_day, correlation_id) VALUES ($1,'BUILDING',$2,$3,$4,$5,$6,$7)`, [`OWN-${input.assetId}-${input.investorType}-${input.investorId}-${input.correlationId}`, input.assetId, input.investorType, input.investorId, units.toString(), day + 1, `${input.correlationId}:position`]);
    await createGameEvent(tx, { id: `OWNERSHIP-${input.correlationId}`, category: 'OWNERSHIP', eventType: 'ASSET_OWNERSHIP_SUBSCRIBED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: input.assetId, title: 'Asset ownership subscribed', details: { organizationId: input.organizationId, investorType: input.investorType, investorId: input.investorId, units: units.toString(), priceUnits: price.toString() }, correlationId: input.correlationId });
    return { ok: true, assetId: input.assetId, investorType: input.investorType, investorId: input.investorId, units: units.toString(), amountUnits: amount.toString(), effectiveFromGameDay: day + 1, transactionId: posted.rows[0].transaction_id, correlationId: input.correlationId };
  });
}

export async function distributeOwnership(repository: PostgresRepository, input: { organizationId: string; assetId: string; amountUnits: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM ownership_distributions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, distributionId: prior.rows[0].id, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: 'ECONOMIC_OWNER', amountUnits: BigInt(input.amountUnits) });
    const amount = BigInt(input.amountUnits);
    if (amount <= 0n) throw new Error('Distribution amount must be positive');
    const building = (await tx.query<{ owner_economic_id: string }>('SELECT owner_economic_id FROM buildings WHERE id = $1 AND status = \'ACTIVE\' FOR UPDATE', [input.assetId])).rows[0];
    const owned = (await tx.query<{ id: string }>('SELECT id FROM owner_registry WHERE id = $1 AND economic_id = $2 AND owner_type = \'ORGANIZATION\'', [input.organizationId, building?.owner_economic_id ?? ''])).rows[0];
    if (!building || !owned) throw new Error('Organization does not legally own this asset');
    const day = await currentDay(tx);
    const positions = await tx.query<{ holder_type: 'HOUSE' | 'ORGANIZATION'; holder_id: string; units: string }>(`SELECT holder_type, holder_id, units::TEXT FROM asset_ownership_positions WHERE asset_type = 'BUILDING' AND asset_id = $1 AND status = 'ACTIVE' AND effective_from_game_day <= $2 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2) FOR UPDATE`, [input.assetId, day]);
    const total = positions.rows.reduce((sum, row) => sum + BigInt(row.units), 0n);
    if (total !== TOTAL_OWNERSHIP_UNITS) throw new Error('Ownership conservation invariant failed before distribution');
    const source = (await tx.query<{ id: string; balance_units: string }>('SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a WHERE a.owner_economic_id = $1 AND a.asset_id = 1 AND a.account_type = \'TREASURY\' AND a.status = \'ACTIVE\' FOR UPDATE', [building.owner_economic_id])).rows[0];
    if (!source || BigInt(source.balance_units) < amount) throw new Error('Organization distribution cash is insufficient');
    const payments: Array<{ holderType: string; holderId: string; units: bigint; amount: bigint; accountId: string }> = [];
    let allocated = 0n;
    for (const position of positions.rows) {
      const payment = (amount * BigInt(position.units)) / total;
      if (payment <= 0n) continue;
      const owner = (await tx.query<{ economic_id: string }>('SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = $2', [position.holder_id, position.holder_type])).rows[0];
      const accountType = position.holder_type === 'HOUSE' ? 'WALLET' : 'TREASURY';
      const destination = owner && (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = \'ACTIVE\'', [owner.economic_id, accountType])).rows[0];
      if (!destination || destination.id === source.id) continue;
      payments.push({ holderType: position.holder_type, holderId: position.holder_id, units: BigInt(position.units), amount: payment, accountId: destination.id });
      allocated += payment;
    }
    if (!payments.length || allocated <= 0n) throw new Error('No eligible ownership payment destinations');
    const distributionId = `DIST-${input.correlationId}`;
    const effects = payments.flatMap((payment) => [{ account_id: source.id, asset_id: 1, delta_units: (-payment.amount).toString() }, { account_id: payment.accountId, asset_id: 1, delta_units: payment.amount.toString() }]);
    const posted = await tx.query<{ transaction_id: string; created: boolean }>('SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,\'OWNERSHIP_DISTRIBUTION\',\'ORGANIZATION\',$3,\'ownership-distribution-v1\',$4::JSONB)', [input.correlationId, day, input.organizationId, JSON.stringify(effects)]);
    if (!posted.rows[0]?.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    await tx.query(`INSERT INTO ownership_distributions (id, asset_type, asset_id, organization_id, total_units, amount_units, status, game_day, correlation_id) VALUES ($1,'BUILDING',$2,$3,$4,$5,'PAID',$6,$7)`, [distributionId, input.assetId, input.organizationId, total.toString(), amount.toString(), day, input.correlationId]);
    for (const payment of payments) await tx.query(`INSERT INTO ownership_distribution_payments (id, distribution_id, holder_type, holder_id, ownership_units, amount_units, economic_transaction_id, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, [`${distributionId}-${payment.holderType}-${payment.holderId}`, distributionId, payment.holderType, payment.holderId, payment.units.toString(), payment.amount.toString(), posted.rows[0].transaction_id, `${input.correlationId}:payment:${payment.holderType}:${payment.holderId}`]);
    await createGameEvent(tx, { id: `OWNERSHIP-DISTRIBUTION-${input.correlationId}`, category: 'OWNERSHIP', eventType: 'ASSET_OWNERSHIP_DISTRIBUTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: input.assetId, title: 'Ownership distribution paid', details: { organizationId: input.organizationId, amountUnits: amount.toString(), allocatedUnits: allocated.toString(), retainedRemainderUnits: (amount - allocated).toString() }, correlationId: input.correlationId });
    return { ok: true, distributionId, amountUnits: amount.toString(), allocatedUnits: allocated.toString(), retainedRemainderUnits: (amount - allocated).toString(), payments: payments.length, transactionId: posted.rows[0].transaction_id, correlationId: input.correlationId };
  });
}
