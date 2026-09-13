# EARTH Community V2 Contract

Status: **defined, not enabled**

Community is a social association, not an economic institution. It has no
treasury, CREDIT account, resource inventory, buildings, loans, taxes,
budgets, research, patents, insolvency process, or daily settlement.

## Identity and continuity

- The persistent membership principal is a **House**.
- The current Human is the actor who creates a community, posts, approves a
  request, changes a role, or disbands a community.
- Human identifiers may be retained for event/audit attribution only.
- Human death or succession must not remove or downgrade the House's active
  membership or role.

## Domain values

Membership roles are `OWNER`, `MODERATOR`, and `MEMBER`.

Visibility is `PUBLIC` or `PRIVATE`.

Join policy is `OPEN` or `REQUEST`.

Community status is `ACTIVE` or `DISBANDED`.

The last Owner cannot leave until another Owner exists. Owners may add/remove
Owners; Owners and Moderators may approve, reject, or remove members. Owners
may edit or disband the Community. Members may view, post, and leave.

## Deferred funding

Community contributions are intentionally not part of V2. If fundraising is
added later, it must be a separate Community Project/Fundraiser with an
explicit payer, escrow, beneficiary, budget, and audit trail. It must not turn
the Community into another treasury-owning institution.

## Enablement rule

The feature remains disabled until a House-principal schema and service are
implemented and certified. Disabled Community routes must fail closed rather
than return empty or fabricated gameplay state.
