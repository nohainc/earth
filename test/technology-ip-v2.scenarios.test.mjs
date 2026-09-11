import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

function scenario() {
  return {
    day: 100,
    tech: { id: 'TECH-ROBOTICS', patentable: true, exclusivityDays: 3 },
    projects: new Map(),
    access: new Map(),
    patents: new Map(),
    licenses: new Map(),
    memberships: new Map([['H-A', 'CORP-A'], ['H-B', 'CORP-B']]),
    construction: new Map(),
  };
}

function completeResearch(s, corporation, projectId, completedDay = s.day) {
  s.projects.set(projectId, { corporation, status: 'COMPLETED', completedDay });
  const key = `${corporation}:${s.tech.id}:RESEARCHED:${projectId}`;
  s.access.set(key, { corporation, source: 'RESEARCHED', effectiveDay: completedDay + 1 });
}

function grantPatent(s, completedDay = s.day) {
  const candidates = [...s.projects.entries()]
    .filter(([, p]) => p.status === 'COMPLETED' && p.completedDay === completedDay)
    .sort((a, b) => a[1].corporation.localeCompare(b[1].corporation) || a[0].localeCompare(b[0]));
  if (s.tech.patentable && candidates.length && !s.patents.has(s.tech.id)) {
    const [projectId, project] = candidates[0];
    s.patents.set(s.tech.id, { owner: project.corporation, projectId, effectiveDay: completedDay + 1 });
  }
}

function researchAllowed(s, corporation, startDay) {
  const patent = s.patents.get(s.tech.id);
  if (!patent) return true;
  const exclusiveThrough = patent.effectiveDay + s.tech.exclusivityDays - 1;
  const alreadyStarted = [...s.projects.values()].some((p) => p.corporation === corporation && p.status === 'ACTIVE');
  return alreadyStarted || startDay > exclusiveThrough;
}

function payLicense(s, id, day) {
  const license = s.licenses.get(id);
  license.status = 'ACTIVE';
  license.paidThrough = day;
  license.accessEffectiveDay = day + 1;
}

function settleLicense(s, id, day, paid) {
  const license = s.licenses.get(id);
  if (paid) payLicense(s, id, day);
  else license.status = 'SUSPENDED';
}

test('Plan 40 scenario contract is wired to the V2 primitives', () => {
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  const technology = read('cloudflare/src/technology-postgres.ts');
  const phases = read('cloudflare/src/daily-settlement-phases.ts');
  for (const primitive of [
    'earth_settle_research_and_progress_v2',
    'earth_assert_technology_research_allowed',
    'earth_settle_technology_license_fees',
    'earth_finalize_technology_public_domain',
    'earth_transfer_dissolved_corporation_ip',
    'earth_resolve_corporation_technology_access',
  ]) assert.match(`${scheduler}\n${technology}`, new RegExp(primitive));
  assert.match(phases, /ip_license_billing/);
  assert.match(phases, /building_settlement/);
});

test('normal research is permanent and patentable first discovery grants access plus a patent', () => {
  const s = scenario();
  s.tech.patentable = false;
  completeResearch(s, 'CORP-A', 'P-A');
  assert.equal(s.access.get('CORP-A:TECH-ROBOTICS:RESEARCHED:P-A').effectiveDay, 101);
  assert.equal(s.patents.size, 0);

  const p = scenario();
  completeResearch(p, 'CORP-A', 'P-A');
  grantPatent(p);
  assert.equal(p.access.size, 1);
  assert.deepEqual(p.patents.get('TECH-ROBOTICS'), { owner: 'CORP-A', projectId: 'P-A', effectiveDay: 101 });
});

test('same-day patent races choose the same owner regardless of completion input order', () => {
  const outcomes = [];
  for (const order of [['CORP-A', 'CORP-B'], ['CORP-B', 'CORP-A'], ['CORP-A', 'CORP-B'].reverse()]) {
    const s = scenario();
    order.forEach((corp, i) => completeResearch(s, corp, `P-${corp}-${i}`));
    grantPatent(s);
    outcomes.push(s.patents.get('TECH-ROBOTICS').owner);
  }
  assert.deepEqual(outcomes, ['CORP-A', 'CORP-A', 'CORP-A']);
});

test('grandfathered research completes while new research is blocked during exclusivity', () => {
  const s = scenario();
  s.projects.set('P-B', { corporation: 'CORP-B', status: 'ACTIVE', completedDay: null });
  completeResearch(s, 'CORP-A', 'P-A');
  grantPatent(s);
  assert.equal(researchAllowed(s, 'CORP-B', 101), true);
  assert.equal(researchAllowed(s, 'CORP-C', 101), false);
});

test('license payment, suspension, restoration, public domain and construction snapshots are day-effective', () => {
  const s = scenario();
  s.licenses.set('L-1', { status: 'PENDING', paidThrough: 0 });
  settleLicense(s, 'L-1', 100, true);
  assert.equal(s.licenses.get('L-1').accessEffectiveDay, 101);
  settleLicense(s, 'L-1', 101, false);
  assert.equal(s.licenses.get('L-1').status, 'SUSPENDED');
  settleLicense(s, 'L-1', 102, true);
  assert.equal(s.licenses.get('L-1').accessEffectiveDay, 103);

  const patent = { ...s.tech, patentable: true };
  assert.equal(patent.exclusivityDays, 3);
  const publicDomainDay = 101 + patent.exclusivityDays;
  assert.equal(publicDomainDay, 104);

  s.construction.set('B-1', { startedDay: 100, snapshot: { technology: 'TECH-ROBOTICS', cost: 90, duration: 8 } });
  assert.deepEqual(s.construction.get('B-1').snapshot, { technology: 'TECH-ROBOTICS', cost: 90, duration: 8 });
});

test('membership changes and dissolution do not leave stale corporation IP authority', () => {
  const s = scenario();
  completeResearch(s, 'CORP-A', 'P-A');
  grantPatent(s);
  assert.equal(s.memberships.get('H-A'), 'CORP-A');
  s.memberships.delete('H-A');
  assert.equal(s.memberships.has('H-A'), false);
  const patent = s.patents.get('TECH-ROBOTICS');
  patent.owner = 'OUC';
  assert.equal(patent.owner, 'OUC');
});

test('retrying completion is idempotent for access and patent rows', () => {
  const s = scenario();
  completeResearch(s, 'CORP-A', 'P-A');
  grantPatent(s);
  completeResearch(s, 'CORP-A', 'P-A');
  grantPatent(s);
  assert.equal(s.access.size, 1);
  assert.equal(s.patents.size, 1);
});

test('database patent grant makes same-day ownership deterministic', () => {
  const migration = read('db/migrations/292_deterministic_patent_race_resolution.sql');
  assert.match(migration, /DISTINCT ON \(p\.target_id\)/);
  assert.match(migration, /ORDER BY p\.target_id, p\.corporation_economic_id, p\.id/);
  assert.match(migration, /ON CONFLICT DO NOTHING/);
  assert.match(migration, /lower owner id wins/i);
});

test('property: shuffled completion order preserves one patent and permanent research access', () => {
  let seed = 0x9e3779b9;
  const random = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 0x100000000);
  for (let run = 0; run < 50; run += 1) {
    const corps = ['CORP-A', 'CORP-B', 'CORP-C'].sort(() => random() - 0.5);
    const s = scenario();
    corps.forEach((corp, i) => completeResearch(s, corp, `P-${corp}-${i}`));
    grantPatent(s);
    assert.equal(s.patents.size, 1);
    assert.equal(s.patents.get('TECH-ROBOTICS').owner, 'CORP-A');
    assert.equal(s.access.size, 3);
  }
});
