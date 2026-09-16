#!/bin/bash
set -eo pipefail

export DATABASE_URL="${DATABASE_URL:-postgres://earth:earth_dev_only@localhost:5432/earth}"
echo "Running retired pre-V4 page integration suites. These tests are preserved for migration history only."
node --test --test-concurrency=1 test/pages/*.page.test.mjs
