#!/bin/zsh
set -euo pipefail

# The PostgreSQL URI must be supplied by the caller and is never written here.
: "${DATABASE_URL:?Set DATABASE_URL in the shell before running this script}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_PORT="${EARTH_LOCAL_API_PORT:-8788}"
WEB_PORT="${EARTH_LOCAL_WEB_PORT:-50553}"
API_ORIGIN="http://localhost:${WEB_PORT}"

if ! command -v osascript >/dev/null 2>&1; then
  print -u2 "This launcher requires macOS Terminal.app."
  exit 1
fi

api_command="cd ${(q)ROOT_DIR} && DATABASE_URL=${(q)DATABASE_URL} DATABASE_READ_ONLY=true CORS_ORIGIN=${(q)API_ORIGIN} PORT=${API_PORT} npm run start:prod-local"
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

print "Started the read-only production-backed API on port ${API_PORT} and Flutter on port ${WEB_PORT}."
print "Open http://localhost:${WEB_PORT}"
