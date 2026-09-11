import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/332_institution_action_authorization.sql', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');
const institutions = fs.readFileSync('cloudflare/src/institutions-postgres.ts', 'utf8');
const finance = fs.readFileSync('cloudflare/src/finance-postgres.ts', 'utf8');

test('institution actions resolve from active governance roles', () => {
  assert.match(migration, /institution_governance_roles/);
  for (const action of ['SET_BUDGET', 'CREATE_COMMITMENT', 'APPROVE_SPENDING', 'TRANSFER_TO_RESERVE', 'AUTHORIZE_GRANT', 'CHANGE_TAX_RULE', 'DECLARE_DIVIDEND']) assert.match(migration, new RegExp(action));
  assert.match(migration, /earth_can_perform_institution_action/);
  assert.match(schema, /institution_governance_roles/);
  assert.match(institutions, /institution_governance_roles/);
  assert.match(institutions, /CITY_MAYOR/);
  assert.match(institutions, /CORPORATION_EXECUTIVE/);
  assert.match(finance, /canPerformInstitutionAction/);
  assert.doesNotMatch(finance, /administrator_human_id = \$2/);
});
