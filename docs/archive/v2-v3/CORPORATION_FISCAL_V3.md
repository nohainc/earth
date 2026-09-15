# Corporation fiscal model V3

- Status: Canonical

EARTH and Corporation are the only fiscal layers.

- EARTH owns global taxes and the global treasury.
- A Corporation owns the sole local public treasury for its Territories.
- Corporation budget categories and budget lines are the only local public
  budget authority.
- Corporation tax rules benefit the Corporation treasury.
- Territories do not own treasuries, taxes, or budgets.

The database restricts `budget_categories.institution_kind` to `CORPORATION`
and restricts tax governance scopes and beneficiaries to `EARTH` or
`CORPORATION`. Corporation public spending uses the Corporation treasury and
Corporation operations account, with budget-line accounting and an auditable
economic transaction.
