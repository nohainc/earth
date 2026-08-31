#!/bin/bash
set -eo pipefail

export DATABASE_URL="${DATABASE_URL:-postgres://earth:earth_dev_only@localhost:5432/earth}"
echo "========================================================"
echo "    EARTH: All-Page High-Quality Integration Test Suite "
echo "========================================================"
echo "Database: ${DATABASE_URL}"
echo "Target User: vitalii.noga@gmail.com (H-D11AA14C)"
echo ""

node --test --test-concurrency=1 test/pages/*.page.test.mjs

echo ""
echo "✅ All 14 page integration test suites executed successfully!"
echo "========================================================"
