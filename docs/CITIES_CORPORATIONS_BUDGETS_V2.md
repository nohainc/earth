# Cities, Corporations & Budgets V2

## Institutional money authority

Economy V2 is the only authoritative source of institutional CREDIT. Each City
and Corporation has a CREDIT `TREASURY` account, with separate `OPERATIONS` and
`RESERVE` accounts provisioned for future use. `TREASURY` is the one default
settlement account for institutional CREDIT.

The former `cities.treasury` and `corporations.treasury` scalar columns were
removed after a migration-time equality check against the V2 TREASURY account.
Institution lists, rankings, qualification checks, and scheduler projections
read the V2 account directly.

Budgets and financial summaries are projections or spending permissions. They
do not hold or create money independently of Economy V2 accounts.
