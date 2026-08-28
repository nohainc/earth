import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
const confirm = process.argv.includes('--confirm-permanent-delete');
const emails = process.argv.filter((value) => value !== '--confirm-permanent-delete').slice(2).map((value) => value.trim().toLowerCase()).filter(Boolean);

if (!connectionString) throw new Error('DATABASE_URL is required; refusing to target an implicit database');
if (!confirm) throw new Error('Refusing permanent deletion without --confirm-permanent-delete');
if (!emails.length || new Set(emails).size !== emails.length) throw new Error('Provide one or more unique email addresses after the script name');

const parsed = new URL(connectionString);
const usesSystemRoot = parsed.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsed.searchParams.delete('sslrootcert');
  parsed.searchParams.delete('sslmode');
}

const client = new Client({
  connectionString: parsed.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  application_name: 'earth-permanent-account-deletion',
  connectionTimeoutMillis: 5000,
  query_timeout: 30000,
  statement_timeout: 30000,
});

const deleteStatements = [
  ['contract_disputes', "DELETE FROM contract_disputes WHERE contract_id IN (SELECT id FROM earth_delete_contracts) OR claimant_id = ANY($1::text[]) OR respondent_id = ANY($1::text[]) OR resolved_by = ANY($1::text[])", 'humans'],
  ['negotiated_contracts', "DELETE FROM negotiated_contracts WHERE id IN (SELECT id FROM earth_delete_contracts) OR proposer_id = ANY($1::text[]) OR counterparty_id = ANY($1::text[])", 'humans'],
  ['research_projects', "DELETE FROM research_projects WHERE id IN (SELECT id FROM earth_delete_projects) OR owner_id = ANY($1::text[]) OR technology_id IN (SELECT id FROM earth_delete_technologies)", 'humans'],
  ['business_shares', "DELETE FROM business_shares WHERE business_id IN (SELECT id FROM earth_delete_businesses) OR holder_id = ANY($1::text[])", 'humans'],
  ['business_constitutions', "DELETE FROM business_constitutions WHERE business_id IN (SELECT id FROM earth_delete_businesses) OR updated_by = ANY($1::text[])", 'humans'],
  ['business_management', "DELETE FROM business_management WHERE business_id IN (SELECT id FROM earth_delete_businesses) OR manager_id = ANY($1::text[]) OR appointed_by = ANY($1::text[])", 'humans'],
  ['business_financials', "DELETE FROM business_financials WHERE business_id IN (SELECT id FROM earth_delete_businesses)", 'none'],
  ['businesses', "DELETE FROM businesses WHERE id IN (SELECT id FROM earth_delete_businesses) OR owner_id = ANY($1::text[])", 'humans'],
  ['market_trades', "DELETE FROM market_trades WHERE order_id IN (SELECT id FROM earth_delete_orders)", 'none'],
  ['market_orders', "DELETE FROM market_orders WHERE id IN (SELECT id FROM earth_delete_orders) OR human_id = ANY($1::text[])", 'humans'],
  ['ballots', "DELETE FROM ballots WHERE human_id = ANY($1::text[])", 'humans'],
  ['auth_action_tokens', "DELETE FROM auth_action_tokens WHERE human_id = ANY($1::text[])", 'humans'],
  ['auth_sessions', "DELETE FROM auth_sessions WHERE human_id = ANY($1::text[])", 'humans'],
  ['auth_credentials', "DELETE FROM auth_credentials WHERE human_id = ANY($1::text[])", 'humans'],
  ['auth_login_attempts', 'DELETE FROM auth_login_attempts WHERE email = ANY($1::text[])', 'emails'],
  ['succession_plans', "DELETE FROM succession_plans WHERE human_id = ANY($1::text[]) OR successor_human_id = ANY($1::text[])", 'humans'],
  ['community_members', "DELETE FROM community_members WHERE human_id = ANY($1::text[])", 'humans'],
  ['communities', "DELETE FROM communities WHERE founder_id = ANY($1::text[])", 'humans'],
  ['memberships', "DELETE FROM memberships WHERE human_id = ANY($1::text[])", 'humans'],
  ['life_events', "DELETE FROM life_events WHERE human_id = ANY($1::text[])", 'humans'],
  ['role_assignments', "DELETE FROM role_assignments WHERE human_id = ANY($1::text[])", 'humans'],
  ['authority_delegations', "DELETE FROM authority_delegations WHERE delegator_id = ANY($1::text[]) OR delegate_id = ANY($1::text[])", 'humans'],
  ['membership_events', "DELETE FROM membership_events WHERE human_id = ANY($1::text[])", 'humans'],
  ['authority_events', "DELETE FROM authority_events WHERE human_id = ANY($1::text[])", 'humans'],
  ['notifications', "DELETE FROM notifications WHERE human_id = ANY($1::text[])", 'humans'],
  ['personal_financial_states', "DELETE FROM personal_financial_states WHERE human_id = ANY($1::text[])", 'humans'],
  ['deceased_profiles', "DELETE FROM deceased_profiles WHERE human_id = ANY($1::text[])", 'humans'],
  ['ai_assistants', "DELETE FROM ai_assistants WHERE owner_id = ANY($1::text[])", 'humans'],
  ['governance_rules', "DELETE FROM governance_rules WHERE created_by = ANY($1::text[])", 'humans'],
  ['ownership_events', "DELETE FROM ownership_events WHERE from_owner_id = ANY($1::text[]) OR to_owner_id = ANY($1::text[])", 'humans'],
  ['asset_ownership_events', "DELETE FROM asset_ownership_events WHERE from_owner_id = ANY($1::text[]) OR to_owner_id = ANY($1::text[])", 'humans'],
  ['asset_ownership_events_for_assets', "DELETE FROM asset_ownership_events WHERE asset_id IN (SELECT id FROM earth_delete_assets)", 'none'],
  ['assets', "DELETE FROM assets WHERE current_owner_id = ANY($1::text[])", 'humans'],
  ['resource_balances', "DELETE FROM resource_balances WHERE owner_id = ANY($1::text[])", 'humans'],
  ['account_balances', "DELETE FROM account_balances WHERE owner_id = ANY($1::text[]) OR account_id = ANY($2::text[])", 'accounts'],
  ['ledger_entries', "DELETE FROM ledger_entries WHERE debit_account = ANY($1::text[]) OR credit_account = ANY($1::text[]) OR debit_account = ANY($2::text[]) OR credit_account = ANY($2::text[])", 'accounts'],
  ['event_outbox', "DELETE FROM event_outbox WHERE aggregate_id = ANY($1::text[])", 'humans'],
  ['humans', 'DELETE FROM humans WHERE id = ANY($1::text[])', 'humans'],
];

await client.connect();
try {
  await client.query('BEGIN');
  const target = await client.query('SELECT h.id, h.account_id, ac.email FROM humans h JOIN auth_credentials ac ON ac.human_id = h.id WHERE ac.email = ANY($1::text[]) FOR UPDATE', [emails]);
  if (target.rows.length !== emails.length) throw new Error(`Expected ${emails.length} matching accounts, found ${target.rows.length}`);
  const humans = target.rows.map((row) => row.id);
  const accounts = target.rows.map((row) => row.account_id);

  await client.query('CREATE TEMP TABLE earth_delete_humans AS SELECT id FROM humans WHERE id = ANY($1::text[])', [humans]);
  await client.query('CREATE TEMP TABLE earth_delete_businesses AS SELECT id FROM businesses WHERE owner_id = ANY($1::text[])', [humans]);
  await client.query('CREATE TEMP TABLE earth_delete_projects AS SELECT id, technology_id FROM research_projects WHERE owner_id = ANY($1::text[])', [humans]);
  await client.query('CREATE TEMP TABLE earth_delete_technologies AS SELECT id FROM technologies WHERE owner_id = ANY($1::text[]) OR id IN (SELECT technology_id FROM earth_delete_projects)', [humans]);
  await client.query('CREATE TEMP TABLE earth_delete_orders AS SELECT id FROM market_orders WHERE human_id = ANY($1::text[])', [humans]);
  await client.query('CREATE TEMP TABLE earth_delete_contracts AS SELECT id FROM negotiated_contracts WHERE proposer_id = ANY($1::text[]) OR counterparty_id = ANY($1::text[])', [humans]);
  await client.query('CREATE TEMP TABLE earth_delete_assets AS SELECT id FROM assets WHERE current_owner_id = ANY($1::text[])', [humans]);

  const deleted = {};
  for (const [table, sql, parameterKind] of deleteStatements) {
    const values = parameterKind === 'none' ? [] : parameterKind === 'emails' ? [emails] : parameterKind === 'accounts' ? [humans, accounts] : [humans];
    const result = await client.query(sql, values);
    deleted[table] = (deleted[table] ?? 0) + result.rowCount;
  }

  const remaining = await client.query('SELECT COUNT(*)::int AS count FROM humans WHERE id = ANY($1::text[])', [humans]);
  if (Number(remaining.rows[0]?.count ?? 0) !== 0) throw new Error('Deletion verification failed: target humans remain');
  await client.query('COMMIT');
  console.log(JSON.stringify({ ok: true, deletedAccounts: target.rows.map(({ email }) => email), deletedRows: deleted }, null, 2));
} catch (error) {
  await client.query('ROLLBACK').catch(() => undefined);
  throw error;
} finally {
  await client.end();
}
