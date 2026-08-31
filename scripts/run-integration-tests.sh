#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

export DATABASE_URL="${DATABASE_URL:-postgres://earth:earth_dev_only@localhost:5432/earth}"

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}         EARTH Live Database Integration Suite       ${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "Database Target: ${YELLOW}$DATABASE_URL${NC}"
echo ""

# Step 1: Ensure migrations are up to date
echo -e "${GREEN}[1/5] Applying & verifying database migrations...${NC}"
node scripts/migrate-postgres.mjs

# Step 2: Run schema and invariant assertions
echo -e "${GREEN}[2/5] Verifying PostgreSQL schema invariants & boundaries...${NC}"
node scripts/assert-postgres-authority.mjs
node scripts/audit-mutation-boundaries.mjs
node scripts/verify-schema-manifest.mjs
node scripts/verify-postgres-invariants.mjs

# Step 3: Run live PostgreSQL E2E suite
echo -e "${GREEN}[3/5] Executing Live PostgreSQL E2E suite (test/postgres-live-e2e.test.mjs)...${NC}"
node --test test/postgres-live-e2e.test.mjs

# Step 4: Run Node backend test suite
echo -e "${GREEN}[4/5] Executing backend unit and API test suite...${NC}"
npm test

# Step 5: Optional Flutter client test suite
if [ "${SKIP_FLUTTER:-false}" != "true" ] && command -v flutter >/dev/null 2>&1; then
  echo -e "${GREEN}[5/5] Executing Flutter client test suite...${NC}"
  (cd flutter_client && flutter test)
else
  echo -e "${YELLOW}[5/5] Skipping Flutter tests (SKIP_FLUTTER=true or flutter not found)${NC}"
fi

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  ✔ ALL INTEGRATION & E2E TESTS PASSED SUCCESSFULLY! ${NC}"
echo -e "${GREEN}=====================================================${NC}"
