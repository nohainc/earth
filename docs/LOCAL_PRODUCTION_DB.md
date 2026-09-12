# Local PostgreSQL database

The local database must be created from an empty volume and the clean baseline:

```bash
docker compose down -v
docker compose up -d postgres
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm run db:migrate:postgres
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm run db:verify:manifest
```

Migration `001_baseline.sql` is version `1`. Do not apply demo data during
baseline verification. For interactive development only, use:

```bash
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm run db:seed:dev
```

Future schema changes use new active migrations beginning at `002_...`.
