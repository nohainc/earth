import fs from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);
const sourceRoots = [path.join(root, 'cloudflare/src'), path.join(root, 'scripts')];
const manifestPath = path.join(root, 'db/schema-manifest.json');
const baselinePath = path.join(root, 'db/baseline/01_schema.sql');

const legacy = new Set([
  'account_balances', 'resource_balances', 'ledger_entries', 'resource_ledger_entries',
  'global_bank_deposits', 'global_bank_loans', 'tax_rules', 'budgets', 'businesses',
  'business_financials', 'business_management', 'business_shares', 'succession_plans',
  'memberships', 'membership_events', 'ownership_events', 'derivative_obligations',
  'future_positions', 'future_settlement_runs', 'human_technology_adoptions',
  'human_technology_subscriptions', 'corporation_technology_shares',
  'financial_states', 'financial_obligations',
]);

const obsolete = new Set(['businesses', 'business_financials', 'business_management', 'business_shares']);

const rewriteTargets = {
  memberships: 'house_affiliations (House identity) plus institution_governance_roles (personal office)',
  membership_events: 'event_outbox or a V2 affiliation event journal',
  ownership_events: 'event_outbox/game event journal',
  account_balances: 'economic_accounts/economic_entries',
  resource_balances: 'economic_accounts/economic_entries',
  ledger_entries: 'economic_transactions/economic_entries',
  resource_ledger_entries: 'economic_transactions/economic_entries',
  global_bank_deposits: 'bank_deposits',
  global_bank_loans: 'bank_loans',
  tax_rules: 'tax_rule_versions',
  budgets: 'institution_budget_lines',
  succession_plans: 'house_succession_plans',
  human_technology_adoptions: 'corporation_technology_access',
  human_technology_subscriptions: 'corporation_technology_access',
  corporation_technology_shares: 'corporation_technology_access',
  financial_states: 'institution_financial_projections and authoritative Economy V2 balances',
  financial_obligations: 'tax_obligations or an explicitly retained V2 obligation model',
};

const missingRetained = {
  notifications: 'BUILD V2 notification/read-model storage, or remove the notification API callers',
  world_events: 'REWRITE to event_outbox or add a canonical V2 event journal',
  building_settlement_journals: 'BUILD V2 settlement journal/read model if building history is retained',
};

async function walk(dir) {
  const result = [];
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...await walk(file));
    else if (/\.(?:ts|mjs)$/.test(entry.name)) result.push(file);
  }
  return result;
}

function lineNumber(source, index) { return source.slice(0, index).split('\n').length; }

function addRef(refs, name, kind, file, source, index, sql) {
  if (!name || ['select', 'values', 'excluded'].includes(name.toLowerCase())) return;
  const key = `${kind}:${name}`;
  const item = refs.get(key) ?? { name, kind, occurrences: [] };
  const occurrence = `${path.relative(root, file)}:${lineNumber(source, index)}`;
  if (!item.occurrences.includes(occurrence)) item.occurrences.push(occurrence);
  if (sql && !item.example) item.example = sql.replace(/\s+/g, ' ').trim().slice(0, 180);
  refs.set(key, item);
}

function extractRefs(file, source, refs) {
  // Inspect only quoted query literals. Scanning the whole source would mistake
  // ordinary JavaScript words (for example `from` in a comment) for SQL.
  const literalPattern = /(['"`])([\s\S]*?)\1/g;
  const sqlPattern = /\b(?:FROM|JOIN|UPDATE|INTO|TRUNCATE(?:\s+TABLE)?)\s+(?:ONLY\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/gi;
  const functionPattern = /\b(?:SELECT\s+|PERFORM\s+|CALL\s+)([a-z_][a-z0-9_]*)\s*\(/gi;
  for (const literal of source.matchAll(literalPattern)) {
    const sql = literal[2];
    if (!/\b(?:SELECT|INSERT|UPDATE|DELETE|FROM|JOIN|CREATE|ALTER|DROP|TRUNCATE|CALL|PERFORM)\b/i.test(sql)) continue;
    for (const match of sql.matchAll(sqlPattern)) {
      const name = match[1].toLowerCase();
      if (sql[match.index + match[0].length] === '(') continue; // FROM function(...)
      // Keep actual SQL identifiers, not prose fragments such as `active` or
      // `authorized` that happen to occur in a string literal.
      if (name.includes('_') || name === 'humans' || name === 'houses' || name === 'cities' || name === 'corporations' || name === 'buildings' || name === 'proposals' || name === 'ballots') {
        addRef(refs, name, 'table', file, source, literal.index + match.index, match[0]);
      }
    }
    for (const match of sql.matchAll(functionPattern)) {
      const name = match[1].toLowerCase();
      if (name.startsWith('earth_')) {
        addRef(refs, name, 'function', file, source, literal.index + match.index, match[0]);
      }
    }
  }
}

function baselineTables(schema) {
  return new Set([...schema.matchAll(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/gi)].map((m) => m[1].toLowerCase()));
}

function baselineFunctions(schema, functions) {
  return new Set([...`${schema}\n${functions}`.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z_][a-z0-9_]*)/gi)].map((m) => m[1].toLowerCase()));
}

function decision(ref) {
  if (obsolete.has(ref.name)) return { decision: 'DELETE', target: 'delete obsolete Business runtime caller' };
  if (legacy.has(ref.name)) return { decision: 'REWRITE TO EXISTING V2', target: rewriteTargets[ref.name] ?? 'remove the obsolete runtime caller' };
  if (missingRetained[ref.name]) return { decision: 'KEEP + ADD V2 SCHEMA', target: missingRetained[ref.name] };
  if (!ref.present) return { decision: 'KEEP + ADD V2 SCHEMA', target: 'add to the canonical baseline or remove the caller after feature review' };
  return { decision: 'KEEP', target: 'baseline object' };
}

function markdown(rows, manifest, baseline) {
  const counts = rows.reduce((out, row) => { out[row.decision] = (out[row.decision] ?? 0) + 1; return out; }, {});
  const lines = [
    '# Runtime ↔ Database Dependency Inventory',
    '',
    `Generated from active TypeScript/JavaScript sources under \`cloudflare/src\` and operational scripts under \`scripts\`. Baseline: \`${manifest.baseline}\`; migration version: \`${manifest.migrationVersion}\`.`,
    '',
    '> This is an inventory and reconciliation decision record. It makes no database changes.',
    '',
    '## Summary',
    '',
    `- Runtime references found: ${rows.length}`,
    `- Baseline tables: ${baseline.tables.size}`,
    `- Baseline functions: ${baseline.functions.size}`,
    `- Decisions: ${Object.entries(counts).map(([k, v]) => `${k} (${v})`).join(', ')}`,
    '',
    '## Reconciliation table',
    '',
    '| Runtime dependency | Kind | Evidence | Baseline | Manifest | Decision | Target |',
    '| --- | --- | --- | --- | --- | --- | --- |',
  ];
  for (const row of rows) {
    const evidence = row.occurrences.slice(0, 6).join(', ');
    lines.push(`| \`${row.name}\` | ${row.kind} | ${evidence}${row.occurrences.length > 6 ? ', …' : ''} | ${row.present ? 'PRESENT' : 'MISSING'} | ${row.manifestPresent ? 'DECLARED' : 'NOT DECLARED'} | ${row.decision} | ${row.target} |`);
  }
  lines.push('', '## Domain decisions', '',
    '### Keep / existing V2', '',
    'Authentication and House identity use `auth_accounts`, `auth_sessions`, `houses`, `humans`, and succession tables. Economy, Spot Market, banking, taxes, budgets, research/IP, governance, scheduler, and outbox references are retained when they resolve to the baseline V2 objects.', '',
    '### Rewrite to existing V2', '',
    '- Human membership queries must move to `house_affiliations`; personal authority must use `institution_governance_roles`.',
    '- Monetary and resource reads/writes must use `economic_accounts`, `economic_transactions`, and `economic_entries`.',
    '- Banking and tax reads must use `bank_deposits`, `bank_loans`, `tax_rule_versions`, and `tax_obligations`.',
    '- Human-level technology adoption/share/subscription callers must use corporation research/access and then be removed if no V2 behavior remains.',
    '- Business and inheritance callers are obsolete and must be deleted, not backed by compatibility tables.',
    '',
    '### Keep + add V2 schema or delete caller', '',
    '- `notifications`: retained product behavior is present in active routes/services but the table is absent from the clean baseline; add a canonical V2 table/read model or remove those endpoints.',
    '- `world_events`: active lifecycle, finance, institution, and governance code writes it, but the clean baseline uses `event_outbox`; consolidate on the V2 event journal or add an explicit canonical projection.',
    '- `building_settlement_journals`: building settlement and civic dividend code depend on it; retain it as a V2 audit/read model only if its schema is included and verified.',
    '',
    '## Scope limits', '',
    'Test fixtures, historical migrations, documentation, and one-off destructive cleanup scripts are not treated as production runtime callers. They are reported separately by the audit command when they mention retired structures.',
  );
  return `${lines.join('\n')}\n`;
}

const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
const schema = await fs.readFile(baselinePath, 'utf8');
const functionsPath = path.join(root, 'db/baseline/02_functions.sql');
const functions = await fs.readFile(functionsPath, 'utf8').catch(() => '');
const refs = new Map();
for (const rootDir of sourceRoots) for (const file of await walk(rootDir)) {
  if (file === path.resolve(new URL('.', import.meta.url).pathname, 'audit-runtime-db-dependencies.mjs')) continue;
  extractRefs(file, await fs.readFile(file, 'utf8'), refs);
}

const tables = baselineTables(schema);
const functionsInBaseline = baselineFunctions(schema, functions);
const manifestTables = new Set(Object.keys(manifest.requiredTables ?? {}).map((name) => name.toLowerCase()));
const rows = [...refs.values()].filter((ref) => ref.kind === 'table' || ref.kind === 'function').map((ref) => {
  const present = ref.kind === 'table' ? tables.has(ref.name) : functionsInBaseline.has(ref.name);
  const withStatus = { ...ref, present, manifestPresent: ref.kind === 'table' ? manifestTables.has(ref.name) : (manifest.requiredFunctions ?? []).map((x) => x.toLowerCase()).includes(ref.name) };
  return { ...withStatus, ...decision(withStatus) };
}).sort((a, b) => a.name.localeCompare(b.name) || a.kind.localeCompare(b.kind));

const output = { generatedAt: new Date().toISOString(), manifestVersion: manifest.manifestVersion, migrationVersion: manifest.migrationVersion, rows };
if (process.argv.includes('--json')) console.log(JSON.stringify(output, null, 2));
if (process.argv.includes('--write')) await fs.writeFile(path.join(root, 'docs/RUNTIME_DATABASE_DEPENDENCY_INVENTORY.md'), markdown(rows, manifest, { tables, functions: functionsInBaseline }));
if (!process.argv.includes('--json')) {
  const counts = rows.reduce((out, row) => { out[row.decision] = (out[row.decision] ?? 0) + 1; return out; }, {});
  console.log(`Runtime/database dependency audit: ${rows.length} references`);
  console.log(JSON.stringify(counts));
  console.log('Use --write to update docs/RUNTIME_DATABASE_DEPENDENCY_INVENTORY.md or --json for machine-readable output.');
}
