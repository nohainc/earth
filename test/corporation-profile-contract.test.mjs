import test from 'node:test';
import assert from 'node:assert/strict';
import { corporationDirectoryEntryFromProfile, corporationProfileFromSource } from '../cloudflare/src/corporation-profile.ts';
import fs from 'node:fs';

test('Corporation directory entries are a subset of the canonical profile', () => {
  const profile = corporationProfileFromSource({
    id: 'CORP-1',
    name: 'Nova',
    admission_policy: 'APPROVAL',
    member_house_count: 12,
    occupied_capacity_units: '184',
    standard_capacity_units: '100',
    required_standard_units: '2',
    treasury_units: '18450',
    technology_count: 7,
    income_tax_bps: 200,
    membership_state: 'ELIGIBLE',
    can_join: true,
  });
  const directory = corporationDirectoryEntryFromProfile(profile, {
    income_tax_bps: 200,
  });

  assert.equal(profile.identity.id, directory.id);
  assert.equal(profile.identity.name, directory.name);
  assert.equal(profile.membership.memberHouseCount, directory.memberHouseCount);
  assert.equal(profile.capacity.occupiedUnits, directory.occupiedCapacityUnits);
  assert.equal(profile.accounts.treasuryUnits, directory.treasuryUnits);
  assert.equal(profile.technology.adoptedCount, directory.technologyCount);
  assert.equal(directory.incomeTaxBps, 200);
});

test('profile normalization keeps authoritative monetary values as strings', () => {
  const profile = corporationProfileFromSource({
    id: 'CORP-2',
    treasury_units: 9007199254740993n,
    operations_units: '12500',
    reserve_units: '7',
  });

  assert.equal(profile.accounts.treasuryUnits, '9007199254740993');
  assert.equal(profile.accounts.operationsUnits, '12500');
  assert.equal(profile.accounts.reserveUnits, '7');
});

test('directory utilization is measured against all required standard blocks', () => {
  const source = fs.readFileSync(new URL('../cloudflare/src/institutions-postgres.ts', import.meta.url), 'utf8');
  assert.match(source, /total_occupied_units \* 10000 \/ NULLIF\(s\.standard_territory_capacity_units \* s\.required_territory_units/);
  assert.match(source, /standard_territory_capacity_units \* s\.required_territory_units.*available_capacity_units/);
});

test('Corporation finance does not fabricate missing money as zero', () => {
  const source = fs.readFileSync(new URL('../flutter_client/lib/features/institutions/institutions_panels.dart', import.meta.url), 'utf8');
  const card = source.slice(source.indexOf('Widget _institutionFinanceClarityCard'), source.indexOf('class CorporationDirectoryPanel'));
  assert.match(card, /formatCreditUnits\(pick\(keys\)\)/);
  assert.doesNotMatch(card, /asDouble\(projection/);
  assert.doesNotMatch(card, /math\.max\(0, budget - committed\)/);
  assert.match(card, /BUDGET AUTHORITY/);
  assert.match(card, /DAILY FLOWS/);
});

test('Corporation roles use institution governance roles, not generic organization offices', () => {
  const source = fs.readFileSync(new URL('../cloudflare/src/corporation-roles-postgres.ts', import.meta.url), 'utf8');
  assert.match(source, /institution_governance_roles/);
  assert.match(source, /eligibleMembers/);
  assert.match(source, /canAppoint/);
  assert.match(source, /canRemove/);
  assert.match(source, /canDelegateLeadership/);
  assert.doesNotMatch(source, /organization_offices|organization_office_grants/);
});

test('constitutional policy metadata preserves source and effective timing', () => {
  const source = fs.readFileSync(new URL('../cloudflare/src/corporation-profile.ts', import.meta.url), 'utf8');
  assert.match(source, /corporationPoliciesFromConstitution/);
  assert.match(source, /effectiveFromGameDay/);
  assert.match(source, /calculationKey/);
  assert.match(source, /provenance\[ruleCode\]/);
});

test('affiliated Corporation actions do not expose founding', () => {
  const source = fs.readFileSync(new URL('../flutter_client/lib/features/institutions/institutions_panels.dart', import.meta.url), 'utf8');
  const hub = source.slice(source.indexOf('class CorporationHubPanel'), source.indexOf('class CorporationFormationAccessPanel'));
  assert.doesNotMatch(hub, /FORM CORPORATION/);
  assert.match(hub, /VIEW GOVERNANCE/);
  assert.match(hub, /LEAVE CORPORATION/);
  assert.match(hub, /resulting independent state/);
});
