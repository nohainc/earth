# EARTH — Current Project State

Status: **V5 CURRENT**
Updated: 2026-09-19

## Gameplay baseline

Gameplay V5 is the active design baseline.

The current world model is:

- EARTH: global authority and constitutional framework.
- Corporation: local political/economic institution.
- House: persistent player and private economic principal.
- Human: mortal House representative.
- Community: voluntary many-to-many social association.
- Territory: physical/geographic capacity context only.

City is not part of the current domain model.

Territory must not be treated as a third government or as a required
player-facing management system. Standardized Territory capacity is pooled;
Houses and buildings do not select a specific Territory container in V5.

## Current production architecture

```text
Flutter Web
  -> Cloudflare Worker
  -> PostgreSQL domain/settlement modules
  -> PostgreSQL through Hyperdrive
  -> Durable Objects / realtime delivery where applicable
```

PostgreSQL is the canonical persistence authority. Flutter is presentation.
Worker code validates/orchestrates authoritative commands. Durable Objects do
not own canonical economic state.

## Current database state

- Active migration files currently extend through `140_seed_v5_capacity_policy.sql`.
- `db/schema.sql` and `db/schema-manifest.json` are current-schema artifacts and
  must remain synchronized with the supported migration chain.
- Historical migrations are append-only and may contain obsolete vocabulary.
- V5 final legacy cutover protections are present in migration 129, followed by
  authoritative clock, settlement, market, schema-parity, account-policy, and
  V5 capacity-policy fixes through migration 140.

Do not rely on old documentation that names earlier migration heads.

## Current player navigation direction

Primary gameplay areas are:

```text
COMMAND
  Overview
  Daily Briefing
  News

HOUSE
  Citizen
  House
  Finance
  Automation

ECONOMY
  Buildings
  Market
  Technology

SOCIETY
  My Corporation
  Corporations
  Communities
  Governance

WORLD
  Conditions
  Rankings
  Initiatives
  Constitution
  Memorial
```

A standalone Territories management page is not a required V5 primary gameplay
surface. Territory data may be shown contextually where capacity or world
conditions matter.

## Important remaining cleanup

The repository still contains compatibility code/tests/modules with historical
names such as V2/V3/V4, territory leases/commons, organization adapters, and old
service paths. A historical name alone does not make a module authoritative.

For every cleanup:

1. verify runtime callers;
2. verify schema dependencies;
3. preserve append-only economic/history records;
4. remove obsolete current-source behavior only after tests prove it is unused;
5. update docs/tests in the same change.

## Verification

Use the repository scripts rather than documentation copies of old commands:

```bash
npm run db:verify:migrations
npm run db:verify:canonical
npm run test:certification
npm test
cd flutter_client && flutter test
```

Run narrower domain/QA scripts from `package.json` when appropriate.
