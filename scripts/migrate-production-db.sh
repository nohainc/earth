#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

print -n 'Production PostgreSQL DATABASE_URL: '
read -r DATABASE_URL

if [[ -z "${DATABASE_URL}" ]]; then
  print -u2 'Error: DATABASE_URL is required.'
  exit 1
fi

if [[ "${DATABASE_URL}" != postgresql://* && "${DATABASE_URL}" != postgres://* ]]; then
  print -u2 'Error: enter a PostgreSQL connection URL beginning with postgres:// or postgresql://.'
  exit 1
fi

export DATABASE_URL
trap 'unset DATABASE_URL' EXIT

print 'Applying forward-only production migrations...'
(cd "${ROOT_DIR}" && npm run db:migrate:postgres -- "$@")

print 'Verifying the production schema manifest...'
(cd "${ROOT_DIR}" && npm run db:verify:manifest)

print 'Verifying production database invariants...'
(cd "${ROOT_DIR}" && npm run db:verify:invariants)

print 'Production database migration and verification completed successfully.'
