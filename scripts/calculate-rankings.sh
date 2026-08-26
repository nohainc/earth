#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

mode="${1:-local}"

case "$mode" in
  --prod|prod|production|--production)
    exec "$script_dir/calculate-rankings-prod.sh"
    ;;
  --local|local|dev|--dev)
    exec "$script_dir/calculate-rankings-local.sh"
    ;;
  -h|--help|help)
    echo "Usage:"
    echo "  ./scripts/calculate-rankings.sh          # Defaults to local database"
    echo "  ./scripts/calculate-rankings.sh --local  # Calculates local database"
    echo "  ./scripts/calculate-rankings.sh --prod   # Prompts/runs against production database"
    exit 0
    ;;
  *)
    exec "$script_dir/calculate-rankings-local.sh"
    ;;
esac
