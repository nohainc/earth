#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

# Load local-only values when present. This file is gitignored and must never be
# used to supply a remote target to this local-only script.
if [[ -f "$project_dir/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$project_dir/.env.local"
  set +a
fi

# Override this when targeting another local PostgreSQL instance.
DATABASE_URL="${DATABASE_URL:-postgres://earth:earth_dev_only@localhost:5432/earth}"

if [[ "$DATABASE_URL" != *"localhost"* && "$DATABASE_URL" != *"127.0.0.1"* && "$DATABASE_URL" != *"::1"* ]]; then
  echo "Refusing non-local database target: $DATABASE_URL" >&2
  exit 1
fi

echo "Migrating local database: $DATABASE_URL"
(cd "$project_dir" && DATABASE_URL="$DATABASE_URL" npm run db:migrate:postgres -- "$@")

if [[ " $* " =~ " --seed " ]]; then
  echo "Seeding canonical starter data"
  (cd "$project_dir" && DATABASE_URL="$DATABASE_URL" npm run db:seed:postgres)
fi

echo "Local database migration complete."
