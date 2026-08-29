#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_PORT="${EARTH_LOCAL_API_PORT:-8788}"
WEB_PORT="${EARTH_LOCAL_WEB_PORT:-50553}"
API_ORIGIN="http://localhost:${WEB_PORT}"

# Default to local PostgreSQL if DATABASE_URL is not set
DEFAULT_LOCAL_DB="postgres://earth:earth_dev_only@localhost:5432/earth"
DATABASE_URL="${DATABASE_URL:-$DEFAULT_LOCAL_DB}"

# Determine if we are targeting a local database
IS_LOCAL=false
if [[ "${DATABASE_URL}" == *"localhost"* || "${DATABASE_URL}" == *"127.0.0.1"* || "${DATABASE_URL}" == *"::1"* ]]; then
  IS_LOCAL=true
fi

# For local database, default to read/write enabled; for remote, default to read-only guard
if [[ "${IS_LOCAL}" == "true" ]]; then
  DATABASE_READ_ONLY="${DATABASE_READ_ONLY:-false}"
else
  DATABASE_READ_ONLY="${DATABASE_READ_ONLY:-true}"
fi

# Check if using local PostgreSQL and ensure the server is started.
# Schema migrations and seed data are managed separately by migrate-local-db.sh;
# launching the UI must not mutate the local database.
if [[ "${IS_LOCAL}" == "true" ]]; then
  print "Checking local PostgreSQL server status..."

  if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
    print "Local PostgreSQL is not responding. Attempting to start PostgreSQL service..."
    if command -v brew >/dev/null 2>&1 && brew services list 2>/dev/null | grep -q "postgresql"; then
      pg_service=$(brew services list 2>/dev/null | awk '/postgresql/ {print $1; exit}')
      print "Starting Homebrew PostgreSQL service (${pg_service})..."
      brew services start "${pg_service}" || true
    elif command -v docker >/dev/null 2>&1; then
      print "Starting local Docker PostgreSQL server..."
      docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d postgres
    fi
  fi

  print "Waiting for PostgreSQL to be ready..."
  retries=15
  until pg_isready -h localhost -p 5432 >/dev/null 2>&1 || (( retries-- <= 0 )); do
    sleep 1
  done

  if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
    print -u2 "Error: PostgreSQL is not reachable at localhost:5432. Please ensure PostgreSQL is running."
    exit 1
  fi

  print "Local PostgreSQL is reachable; leaving the existing schema and data unchanged."
fi

# Automatically release stale local port listeners before starting
for port in "${API_PORT}" "${WEB_PORT}"; do
  pids=$(lsof -ti :"${port}" || true)
  if [[ -n "${pids}" ]]; then
    print "Releasing stale listener process on port ${port}..."
    echo "${pids}" | xargs kill -9 >/dev/null 2>&1 || true
  fi
done

if ! command -v osascript >/dev/null 2>&1; then
  print -u2 "This launcher requires macOS Terminal.app."
  exit 1
fi

api_command="cd ${(q)ROOT_DIR} && DATABASE_URL=${(q)DATABASE_URL} HYPERDRIVE_CONNECTION_STRING=${(q)DATABASE_URL} CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE=${(q)DATABASE_URL} CORS_ORIGIN=${(q)API_ORIGIN} npx wrangler dev --test-scheduled --config wrangler.api.jsonc --port ${API_PORT} --ip 127.0.0.1"
web_command="cd ${(q)ROOT_DIR}/flutter_client && flutter run -d chrome --web-port ${WEB_PORT} --dart-define=EARTH_API_URL=http://localhost:${API_PORT}"

osascript - "$api_command" "$web_command" <<'APPLESCRIPT'
on run argv
  tell application "Terminal"
    activate
    do script (item 1 of argv)
    do script (item 2 of argv)
  end tell
end run
APPLESCRIPT

print "Started local PostgreSQL server, Wrangler Worker API on port ${API_PORT}, and Flutter Chrome client on port ${WEB_PORT}."
print "Run ./scripts/run-local-game-tick.sh to invoke the same scheduled settlement path locally."
print "Open http://localhost:${WEB_PORT} or static prototype at file://${ROOT_DIR}/prototype3.html"
