# Local PostgreSQL database

Local development uses a real PostgreSQL server, not Docker. Keep the local
server on the same major version as the remote service where practical.

Create the local database with the clean baseline:

```bash
createdb earth
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:migrate:postgres
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:verify:manifest
```

Migration `001_baseline.sql` is version `1`. Do not apply demo data during
baseline verification. For interactive development only, use:

```bash
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm run db:seed:dev
```

The pre-production remote workflow resets the existing EARTH database in place,
then applies the same baseline. Future schema changes use new active migrations
beginning at `002_...`.
