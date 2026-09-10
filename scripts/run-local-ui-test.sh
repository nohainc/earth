#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_PORT="${EARTH_LOCAL_API_PORT:-8788}"
WEB_PORT="${EARTH_LOCAL_WEB_PORT:-50553}"
API_ORIGIN="http://localhost:${WEB_PORT}"
LOCAL_MODE="${EARTH_LOCAL_MODE:-live}"
case "${LOCAL_MODE}" in
  live|manual|ui) ;;
  *) print -u2 "Error: EARTH_LOCAL_MODE must be live, manual, or ui."; exit 1 ;;
esac
LOCAL_SCHEDULER_ENABLED="false"
LOCAL_SETTLEMENT_ENABLED="false"
if [[ "${LOCAL_MODE}" == "live" ]]; then
  LOCAL_SCHEDULER_ENABLED="true"
  LOCAL_SETTLEMENT_ENABLED="true"
fi
# Compatibility aliases: explicit legacy values still work during migration.
if [[ -n "${EARTH_LOCAL_SCHEDULER+x}" ]]; then LOCAL_SCHEDULER_ENABLED="${EARTH_LOCAL_SCHEDULER}"; fi
if [[ -n "${EARTH_LOCAL_SETTLEMENT+x}" ]]; then LOCAL_SETTLEMENT_ENABLED="${EARTH_LOCAL_SETTLEMENT}"; fi

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
  if [[ "${LOCAL_SCHEDULER_ENABLED}" == "true" && "${EARTH_ALLOW_REMOTE_MUTATION:-false}" != "true" ]]; then
    print -u2 "REFUSING TO START: live local scheduler targets a remote DATABASE_URL."
    print -u2 "Use a local database, or explicitly set EARTH_ALLOW_REMOTE_MUTATION=true for staging-only testing."
    exit 1
  fi
  if [[ "${LOCAL_SCHEDULER_ENABLED}" == "true" ]]; then
    print -u2 "WARNING: EARTH_ALLOW_REMOTE_MUTATION=true enables scheduler writes against a remote database."
  fi
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

  print "Local PostgreSQL is reachable; preserving existing schema and data."

  if [[ "${LOCAL_MODE}" == "manual" ]]; then
    psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "SELECT earth_local_set_clock_mode('manual');" >/dev/null
  elif [[ "${LOCAL_MODE}" == "ui" ]]; then
    psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "SELECT earth_local_set_clock_mode('paused');" >/dev/null
  else
    psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "SELECT earth_local_set_clock_mode('realtime');" >/dev/null
  fi

  if [[ "${LOCAL_SETTLEMENT_ENABLED}" == "true" ]]; then
    settlement_status=$(psql "${DATABASE_URL}" -Atqc "SELECT status FROM daily_settlement_control WHERE id = 'WORLD'" 2>/dev/null || true)
    if [[ "${settlement_status}" == "awaiting_baseline" ]]; then
      print "Activating local daily settlement from the last completed game day..."
      psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "SELECT earth_activate_daily_settlement(GREATEST(1, (SELECT earth_game_day_from_total_minutes(total_game_minutes) - 1 FROM world_state WHERE id = 'WORLD')), 'local-ui-launcher');" >/dev/null
    fi
  fi
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

api_command="cd ${(q)ROOT_DIR} && DATABASE_URL=${(q)DATABASE_URL} HYPERDRIVE_CONNECTION_STRING=${(q)DATABASE_URL} CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE=${(q)DATABASE_URL} CORS_ORIGIN=${(q)API_ORIGIN} EARTH_LOCAL_MODE=${(q)LOCAL_MODE} EARTH_LOCAL_SCHEDULER=${(q)LOCAL_SCHEDULER_ENABLED} zsh -c '
  set -u
  scheduler_pid=\"\"
  stop_scheduler() { [[ -n \"\${scheduler_pid}\" ]] && kill \"\${scheduler_pid}\" 2>/dev/null || true; }
  trap stop_scheduler EXIT INT TERM
  if [[ \"\${EARTH_LOCAL_SCHEDULER}\" == \"true\" ]]; then
    (
      # Align every invocation to the next wall-clock minute boundary.
      sleep \$((60 - \$(date +%s) % 60))
      while true; do
        curl --fail --silent --show-error --max-time 30 http://127.0.0.1:${API_PORT}/__scheduled >/dev/null || print -u2 \"Local scheduled tick failed; retrying next minute.\"
        sleep \$((60 - \$(date +%s) % 60))
      done
    ) &
    scheduler_pid=\$!
    print \"Local scheduler enabled: invoking the Worker scheduled handler every 60 seconds.\"
  fi
  npx wrangler dev --test-scheduled --config wrangler.api.jsonc --port ${API_PORT} --ip 127.0.0.1
'"
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

print "Started local mode ${LOCAL_MODE}: PostgreSQL, Wrangler Worker API on port ${API_PORT}, and Flutter Chrome client on port ${WEB_PORT}."
if [[ "${LOCAL_SCHEDULER_ENABLED}" == "true" ]]; then
  print "The local Worker scheduled handler will run every 60 seconds. Set EARTH_LOCAL_SCHEDULER=false to disable it."
else
  print "Local scheduled ticks are disabled. Set EARTH_LOCAL_SCHEDULER=true to enable the one-minute Worker timer."
fi
if [[ "${LOCAL_SETTLEMENT_ENABLED}" == "true" ]]; then
  print "Local daily settlement activation is enabled. Set EARTH_LOCAL_SETTLEMENT=false to disable it."
else
  print "Local daily settlement activation is disabled. Set EARTH_LOCAL_SETTLEMENT=true to enable it."
fi
print "Open http://localhost:${WEB_PORT} or static prototype at file://${ROOT_DIR}/prototype3.html"
