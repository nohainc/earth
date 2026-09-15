# Corporation lifecycle V3

- Status: Canonical
- Scope: Corporation genesis, House membership, and primary Territory provisioning

## Genesis

`POST /api/corporations` accepts a Corporation `name` and optional
`territoryName`. The authenticated Human's House is the founder. One database
transaction creates:

1. the Corporation institution;
2. the Corporation record;
3. its primary Territory;
4. its CREDIT treasury owner and account;
5. baseline governance roles and rules;
6. the Corporation communication channel; and
7. the founder House's active affiliation.

There is no City prerequisite, population threshold, capital City, City
qualification, or separate formation step.

## Joining and leaving

`POST /api/corporations/{id}/membership` joins the authenticated Human's House
to the Corporation's active primary Territory. A House may have at most one
active Corporation affiliation. Joining another Corporation closes the prior
historical affiliation and creates a new row; it does not rewrite history.

`DELETE /api/corporations/{id}/membership` closes the active affiliation with
`status = 'LEFT'` and records `left_game_day`. House-owned assets are not
relocated or transferred by leaving.

## Authority boundaries

- Corporation membership belongs to the House.
- Political actions and lifecycle events are attributed to the current Human.
- Territory is assigned as a physical location context, not an owner or
  institution.
- Corporation creation always provisions a primary Territory before the
  founder affiliation is committed.

## Removed surface

The V3 API has no `createCity`, `listCities`, `cityQualification`, City
residency, City adoption, or Corporation formation-by-City route. The generated
API contract is the source of truth for the active lifecycle surface.

