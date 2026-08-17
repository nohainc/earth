#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_PORT="${EARTH_LOCAL_API_PORT:-8788}"
WEB_PORT="${EARTH_LOCAL_WEB_PORT:-50553}"
API_ORIGIN="http://localhost:${WEB_PORT}"

# Default to local Docker PostgreSQL if DATABASE_URL is not set
DEFAULT_LOCAL_DB="postgresql://earth:earth_dev_only@localhost:5432/earth"
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

# Check if using local PostgreSQL and ensure Docker container is started and updated
if [[ "${IS_LOCAL}" == "true" ]]; then
  if command -v docker >/dev/null 2>&1; then
    print "Starting local Docker PostgreSQL server..."
    docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d postgres

    print "Waiting for PostgreSQL to be ready..."
    retries=15
    until docker compose -f "${ROOT_DIR}/docker-compose.yml" exec -T postgres pg_isready -U earth -d earth >/dev/null 2>&1 || (( retries-- <= 0 )); do
      sleep 1
    done

    print "Updating local database schema (17 migrations) & seed data..."
    (cd "${ROOT_DIR}" && DATABASE_URL="${DATABASE_URL}" npm run db:migrate:postgres)
    (cd "${ROOT_DIR}" && DATABASE_URL="${DATABASE_URL}" npm run db:seed:postgres)
    print "Local database is up to date and ready."
  else
    print -u2 "Notice: Docker is not detected in PATH. Assuming local PostgreSQL is already running."
  fi
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

print "Started local PostgreSQL container, API on port ${API_PORT} (read-only: ${DATABASE_READ_ONLY}), and Flutter on port ${WEB_PORT}."
print "Open http://localhost:${WEB_PORT} or static prototype at file://${ROOT_DIR}/prototype3.html"
