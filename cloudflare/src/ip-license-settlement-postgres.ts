import type { PostgresRepository } from './repository.ts';
import { resolveEconomicAccount } from './economic-account-resolver.ts';

type LicenseContract = {
  id: string;
  licensee_economic_id: string;
  licensor_economic_id: string;
  licensee_type: string;
  licensor_type: string;
  daily_fee_units: string;
  paid_through_game_day: number;
  effective_from_game_day: number;
  effective_to_game_day: number | null;
};

async function billContract(repository: PostgresRepository, contractId: string, gameDay: number): Promise<'paid' | 'suspended' | 'skipped'> {
  const contract = (await repository.query<LicenseContract>(
      `SELECT c.id, c.licensee_economic_id, c.licensor_economic_id,
              licensee.owner_type AS licensee_type, licensor.owner_type AS licensor_type,
              c.daily_fee_units::TEXT, c.paid_through_game_day,
              c.effective_from_game_day, c.effective_to_game_day
         FROM technology_license_contracts c
         JOIN owner_registry licensee ON licensee.economic_id = c.licensee_economic_id
         JOIN owner_registry licensor ON licensor.economic_id = c.licensor_economic_id
        WHERE c.id = $1 AND c.status = 'ACTIVE'
        FOR UPDATE`, [contractId])).rows[0];
  if (!contract || contract.effective_from_game_day > gameDay || contract.effective_to_game_day !== null && contract.effective_to_game_day < gameDay || contract.paid_through_game_day >= gameDay) return 'skipped';

  const amount = BigInt(contract.daily_fee_units);
  if (amount <= 0n) {
    await repository.query('UPDATE technology_license_contracts SET paid_through_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1', [contract.id, gameDay]);
    return 'paid';
  }
  const payerPurpose = contract.licensee_type === 'HOUSE' ? 'WALLET' : 'OPERATIONS';
  const recipientPurpose = contract.licensor_type === 'HOUSE' ? 'WALLET' : 'OPERATIONS';
  const payerAccountId = await resolveEconomicAccount(repository, contract.licensee_economic_id, payerPurpose);
  const recipientAccountId = await resolveEconomicAccount(repository, contract.licensor_economic_id, recipientPurpose);
  const payer = (await repository.query<{ balance_units: string }>('SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1 FOR UPDATE', [payerAccountId])).rows[0];
  if (!payer || BigInt(payer.balance_units) < amount) {
    await repository.query("UPDATE technology_license_contracts SET status = 'SUSPENDED', updated_at = CURRENT_TIMESTAMP WHERE id = $1", [contract.id]);
    return 'suspended';
  }
  const posting = await repository.query<{ transaction_id: string; created: boolean }>(
      `SELECT transaction_id, created FROM earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','SYSTEM_SETTLEMENT',$3,'technology-license-v1',$4::JSONB)`,
      [`license:${contract.id}:${gameDay}`, gameDay, contract.id, JSON.stringify([
        { account_id: payerAccountId, asset_id: 1, delta_units: (-amount).toString(), reason_code: 'technology_license_fee' },
        { account_id: recipientAccountId, asset_id: 1, delta_units: amount.toString(), reason_code: 'technology_license_fee' },
      ])],
  );
  const transaction = posting.rows[0];
  if (!transaction) throw new Error('Technology license posting returned no transaction');
  await repository.query(
      `INSERT INTO technology_license_payments (id, contract_id, payer_economic_id, recipient_economic_id, game_day, amount_units, economic_transaction_id, correlation_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT (correlation_id) DO NOTHING`,
      [`LICENSE-PAYMENT-${contract.id}-${gameDay}`, contract.id, contract.licensee_economic_id, contract.licensor_economic_id, gameDay, amount.toString(), transaction.transaction_id, `license-payment:${contract.id}:${gameDay}`],
  );
  await repository.query('UPDATE technology_license_contracts SET paid_through_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1', [contract.id, gameDay]);
  return 'paid';
}

// @mutation-boundary deterministic-settlement: license billing is one daily, replay-safe payment per contract.
// @mutation-boundary caller-owned-transaction: contract termination is scoped to the phase transaction.
export async function settleTechnologyLicenseFees(
  repository: PostgresRepository,
  gameDay: number,
): Promise<{ gameDay: number; contractsScanned: number; paid: number; suspended: number; terminated: number }> {
  const terminated = await repository.query<{ id: string }>(
    `UPDATE technology_license_contracts c
        SET status = 'EXPIRED', effective_to_game_day = LEAST(COALESCE(c.effective_to_game_day, $1), $1), updated_at = CURRENT_TIMESTAMP
       FROM technology_patents p
      WHERE c.patent_id = p.id AND c.status = 'ACTIVE' AND p.status <> 'ACTIVE'
      RETURNING c.id`, [gameDay]);
  const contracts = await repository.query<{ id: string }>(
    `SELECT id FROM technology_license_contracts
      WHERE status = 'ACTIVE' AND effective_from_game_day <= $1
        AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
        AND paid_through_game_day < $1
      ORDER BY id LIMIT 1000`, [gameDay]);
  let paid = 0;
  let suspended = 0;
  for (const contract of contracts.rows) {
    const result = await billContract(repository, contract.id, gameDay);
    if (result === 'paid') paid += 1;
    if (result === 'suspended') suspended += 1;
  }
  return { gameDay, contractsScanned: contracts.rows.length, paid, suspended, terminated: terminated.rows.length };
}
