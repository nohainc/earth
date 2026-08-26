#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

if [[ -z "${PRODUCTION_DATABASE_URL:-${DATABASE_URL:-}}" ]]; then
  echo -n "Enter Production PostgreSQL DATABASE_URL: "
  read -r TARGET_URL
else
  TARGET_URL="${PRODUCTION_DATABASE_URL:-$DATABASE_URL}"
fi

if [[ -z "${TARGET_URL}" ]]; then
  echo "Error: PRODUCTION_DATABASE_URL (or DATABASE_URL) is required." >&2
  exit 1
fi

if [[ "${TARGET_URL}" != postgresql://* && "${TARGET_URL}" != postgres://* ]]; then
  echo "Error: enter a PostgreSQL connection URL beginning with postgres:// or postgresql://." >&2
  exit 1
fi

echo "===================================================="
echo " Calculating Production Civic Rankings (PostgreSQL)"
echo "===================================================="
(cd "$project_dir" && PRODUCTION_DATABASE_URL="$TARGET_URL" node scripts/calculate-rankings-prod.mjs)

echo ""
echo "Production rankings calculation completed successfully."
