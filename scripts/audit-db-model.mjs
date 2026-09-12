import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);
const schema = fs.readFileSync(path.join(root, 'db/schema.sql'), 'utf8');
const functions = fs.existsSync(path.join(root, 'db/functions.sql'))
  ? fs.readFileSync(path.join(root, 'db/functions.sql'), 'utf8') : '';

const legacy = /(?:^|_)(?:account_balances|resource_balances|ledger_entries|resource_ledger_entries|global_bank_deposits|global_bank_loans|tax_rules|budgets|succession_plans|human_technology_adoptions|human_technology_subscriptions|corporation_technology_shares|businesses|business_|derivative_obligations|future_|ai_|assistant|llm)(?:$|_)/i;
const redesign = /^(?:daily_settlement_profiles|daily_settlement_profile_runs|economic_account_migrations|economy_shadow_|memberships|financial_states)/i;
const removedColumn = /(?:^|_)(?:condition|durability|damage|wear|repair|output_credits|monthly|annual|legacy_balance)(?:$|_)/i;

function decision(name) {
  if (legacy.test(name)) return 'DELETE';
  if (redesign.test(name)) return 'REDESIGN';
  return 'KEEP';
}

function unique(values) { return [...new Set(values)].sort(); }

const tables = unique([...schema.matchAll(/CREATE TABLE IF NOT EXISTS\s+([a-zA-Z_][\w]*)/gi)].map((m) => m[1]));
const views = unique([
  ...schema.matchAll(/CREATE (?:OR REPLACE )?(?:MATERIALIZED )?VIEW\s+([a-zA-Z_][\w]*)/gi),
].map((m) => m[1]));
const triggers = unique([...schema.matchAll(/CREATE TRIGGER\s+([a-zA-Z_][\w]*)/gi)].map((m) => m[1]));
const functionsFound = unique([
  ...schema.matchAll(/CREATE (?:OR REPLACE )?FUNCTION\s+([a-zA-Z_][\w]*)/gi),
  ...functions.matchAll(/CREATE (?:OR REPLACE )?FUNCTION\s+([a-zA-Z_][\w]*)/gi),
].map((m) => m[1]));

const columns = [];
for (const match of schema.matchAll(/CREATE TABLE IF NOT EXISTS\s+([a-zA-Z_][\w]*)\s*\(([^;]*?)\n\);/gis)) {
  const [, table, body] = match;
  for (const line of body.split('\n')) {
    const column = line.trim().match(/^([a-zA-Z_][\w]*)\s+/);
    if (column && !/^(CONSTRAINT|PRIMARY|UNIQUE|CHECK|FOREIGN) ?/i.test(column[1])) {
      const name = column[1];
      const tableDecision = decision(table);
      const columnDecision = tableDecision !== 'KEEP'
        ? tableDecision
        : removedColumn.test(name) ? 'DELETE' : 'KEEP';
      columns.push({ table, name, decision: columnDecision });
    }
  }
}

const inventory = { tables, columns, views, functions: functionsFound, triggers };
const classified = {
  tables: Object.fromEntries(tables.map((name) => [name, decision(name)])),
  columns: Object.fromEntries(columns.map(({ table, name, decision: value }) => [`${table}.${name}`, value])),
  views: Object.fromEntries(views.map((name) => [name, decision(name)])),
  functions: Object.fromEntries(functionsFound.map((name) => [name, decision(name)])),
  triggers: Object.fromEntries(triggers.map((name) => [name, decision(name)])),
};

if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ inventory, classified }, null, 2));
} else {
  for (const [kind, values] of Object.entries(classified)) {
    const counts = Object.values(values).reduce((result, value) => ({ ...result, [value]: (result[value] ?? 0) + 1 }), {});
    console.log(`${kind}: ${JSON.stringify(counts)}`);
  }
  console.log('DB model audit complete: every discovered object has a KEEP, REDESIGN, or DELETE decision.');
}
