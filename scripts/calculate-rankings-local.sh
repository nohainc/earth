#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

DATABASE_URL="${DATABASE_URL:-postgres://earth:earth_dev_only@localhost:5432/earth}"

if [[ "$DATABASE_URL" != *"localhost"* && "$DATABASE_URL" != *"127.0.0.1"* && "$DATABASE_URL" != *"::1"* ]]; then
  echo "Refusing non-local database target in local script: $DATABASE_URL" >&2
  exit 1
fi

echo "==============================================="
echo " Calculating Local Civic Rankings (PostgreSQL)"
echo "==============================================="
(cd "$project_dir" && DATABASE_URL="$DATABASE_URL" node scripts/calculate-rankings-local.mjs)

echo ""
echo "Local rankings calculation completed successfully."
