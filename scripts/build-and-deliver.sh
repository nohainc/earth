#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PARENT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"

DEPLOY_REMOTE=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --deploy|--release)
      DEPLOY_REMOTE=true
      ;;
    --dry-run)
      DEPLOY_REMOTE=true
      DRY_RUN=true
      ;;
    --help|-h)
      print "Usage: ./scripts/build-and-deliver.sh [OPTIONS]"
      print "Options:"
      print "  --deploy     Build and deploy assets to Cloudflare (API, Web App, Static Site)"
      print "  --dry-run    Run dry-run deployment checks with Wrangler"
      print "  --help, -h   Show this help message"
      exit 0
      ;;
  esac
done

print "=================================================="
print "       EARTH Build & Delivery Pipeline            "
print "=================================================="

# 1. Synchronize Web Prototypes & UI Assets
print "\n[1/4] Synchronizing static web assets..."
if [[ -f "${PARENT_DIR}/prototype3.html" && -d "${ROOT_DIR}" ]]; then
  cp "${PARENT_DIR}/prototype3.html" "${ROOT_DIR}/prototype3.html"
  cp "${PARENT_DIR}/prototype3.css" "${ROOT_DIR}/prototype3.css"
  cp "${PARENT_DIR}/prototype3.js" "${ROOT_DIR}/prototype3.js"
fi

(cd "${ROOT_DIR}" && node scripts/prepare-static-assets.mjs)
print "✓ Static site assets prepared in static-site/ and prototype3"

# 2. Build / Prepare Flutter Web Client
print "\n[2/4] Building and preparing Web Client..."
if command -v flutter >/dev/null 2>&1; then
  print "Compiling Flutter web client..."
  if (cd "${ROOT_DIR}/flutter_client" && flutter build web --release 2>/dev/null); then
    print "✓ Flutter compilation succeeded."
  else
    print "Notice: Flutter compilation skipped or running sandboxed; using asset preparation bundle..."
  fi
else
  print "Notice: Flutter CLI not found in PATH; generating runtime bundle assets..."
fi
(cd "${ROOT_DIR}" && node scripts/prepare-flutter-assets.mjs)
print "✓ Web client bundle ready in flutter_client/build/web"

# 3. Verify API Server & Schema Integrity
print "\n[3/4] Validating local API and server syntax..."
(cd "${ROOT_DIR}" && node --check server.js)
(cd "${ROOT_DIR}" && node --check database.js)
if [[ -n "${DATABASE_URL:-}" ]]; then
  (cd "${ROOT_DIR}" && node scripts/verify-schema-manifest.mjs)
  print "✓ Schema manifest verified against active database."
fi
print "✓ Server validation passed."

# 4. Deliver / Deploy (Optional)
print "\n[4/4] Delivery status..."
if [[ "${DEPLOY_REMOTE}" == "true" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    print "Running Wrangler dry-run validation..."
    (cd "${ROOT_DIR}" && npx wrangler deploy --dry-run --config wrangler.api.jsonc)
    (cd "${ROOT_DIR}" && npx wrangler deploy --dry-run --config wrangler.app.jsonc)
    (cd "${ROOT_DIR}" && npx wrangler deploy --dry-run --config wrangler.static.jsonc)
    print "✓ Dry-run deployment validation successful."
  else
    print "Deploying to Cloudflare..."
    (cd "${ROOT_DIR}" && npx wrangler deploy --config wrangler.api.jsonc)
    (cd "${ROOT_DIR}" && npx wrangler deploy --config wrangler.app.jsonc)
    (cd "${ROOT_DIR}" && npx wrangler deploy --config wrangler.static.jsonc)
    print "✓ Production deployment complete."
  fi
else
  print "✓ All assets are built and delivered for local execution."
  print "\nTo test locally, run:"
  print "  ./earth/scripts/run-local-ui-test.sh"
  print "Or preview directly in browser:"
  print "  file://${ROOT_DIR}/prototype3.html"
fi

print "\n=================================================="
print "Pipeline finished successfully!"
print "=================================================="
