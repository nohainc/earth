#!/bin/zsh
set -euo pipefail

API_PORT="${EARTH_LOCAL_API_PORT:-8788}"
API_URL="http://127.0.0.1:${API_PORT}/__scheduled"

if ! curl --fail --silent --show-error --max-time 30 "$API_URL"; then
  print -u2 "Unable to run the local scheduled tick. Start the local app with ./scripts/run-local-ui-test.sh first."
  exit 1
fi

print "Local scheduled game tick completed. Refresh the app to load the updated PostgreSQL state."
