#!/bin/zsh
set -euo pipefail

API_PORT="${EARTH_LOCAL_API_PORT:-8788}"
API_URL="http://127.0.0.1:${API_PORT}/__scheduled"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

HTTP_STATUS="$(curl --silent --show-error --output "$RESPONSE_FILE" --write-out '%{http_code}' --max-time 30 "$API_URL" || true)"
if [[ "$HTTP_STATUS" != 2* ]]; then
  print -u2 "Local scheduled tick returned HTTP ${HTTP_STATUS:-connection error}."
  if [[ -s "$RESPONSE_FILE" ]]; then
    print -u2 "Worker response:"
    cat "$RESPONSE_FILE" >&2
  fi
  print -u2 "Confirm that Wrangler was started with --test-scheduled and that migrations (through 083) are applied to this local database."
  exit 1
fi

print "Local scheduled game tick completed. Refresh the app to load the updated PostgreSQL state."
