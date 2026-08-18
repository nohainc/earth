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

# Check if using local PostgreSQL and ensure server is started, migrated, and seeded
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

  print "Updating local database schema & seed data..."
  (cd "${ROOT_DIR}" && DATABASE_URL="${DATABASE_URL}" npm run db:migrate:postgres)
  (cd "${ROOT_DIR}" && DATABASE_URL="${DATABASE_URL}" npm run db:seed:postgres)
  print "Local database is up to date and ready."
fi

if ! command -v osascript >/dev/null 2>&1; then
  print -u2 "This launcher requires macOS Terminal.app."
  exit 1
fi

api_command="cd ${(q)ROOT_DIR} && DATABASE_URL=${(q)DATABASE_URL} DATABASE_READ_ONLY=${(q)DATABASE_READ_ONLY} CORS_ORIGIN=${(q)API_ORIGIN} PORT=${API_PORT} npm run start:prod-local"
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

print "Started local PostgreSQL server, API on port ${API_PORT} (read-only: ${DATABASE_READ_ONLY}), and Flutter on port ${WEB_PORT}."
print "Open http://localhost:${WEB_PORT} or static prototype at file://${ROOT_DIR}/prototype3.html"
