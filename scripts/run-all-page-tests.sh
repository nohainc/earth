#!/bin/bash
set -eo pipefail

export DATABASE_URL="${DATABASE_URL:-postgres://earth:earth_dev_only@localhost:5432/earth}"
echo "========================================================"
echo "    EARTH: Maintained V4 Page Contract Test Suite       "
echo "========================================================"
echo ""

node --experimental-strip-types --test --test-concurrency=1 \
  test/world-snapshot-v4-contract.test.mjs \
  test/v4-decision-queue-contract.test.mjs \
  test/house-needs-services-contract.test.mjs \
  test/house-onboarding-contract.test.mjs \
  test/governance-v4-contract.test.mjs \
  test/organizations-core-contract.test.mjs \
  test/organization-authority-contract.test.mjs \
  test/organization-office-actions-contract.test.mjs \
  test/territory-rights-contract.test.mjs \
  test/territory-commons-flutter-contract.test.mjs \
  test/commons-dividend-contract.test.mjs \
  test/tax-authority-contract.test.mjs \
  test/tax-statement-flutter-contract.test.mjs \
  test/personal-finance-page-api.test.mjs \
  test/flutter-api-contract.test.mjs \
  test/flutter-api-contract-generated.test.mjs

echo ""
echo "✅ Maintained V4 page contract suites passed."
echo "The retired pre-V4 integration suites remain available via scripts/run-legacy-page-tests.sh."
echo "========================================================"
