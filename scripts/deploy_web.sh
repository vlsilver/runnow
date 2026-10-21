#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${RUNNOW_CONFIG_FILE:-$ROOT_DIR/.secret/config.json}"
PROJECT_ID="${PROJECT_ID:-run-now-79767}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing jq. Install with: brew install jq" >&2
  exit 1
fi

RUNNOW_API_URL="${RUNNOW_API_URL:-$(jq -r '.RUNNOW_API_URL // .runnowApiUrl // .apiUrl // empty' "$CONFIG_FILE")}"
if [[ -z "$RUNNOW_API_URL" || "$RUNNOW_API_URL" == "null" ]]; then
  echo "Missing RUNNOW_API_URL in $CONFIG_FILE" >&2
  exit 1
fi

cd "$ROOT_DIR"

echo "Deploying RunNow web"
echo "  project: $PROJECT_ID"
echo "  api:     $RUNNOW_API_URL"

flutter build web --release \
  --dart-define=RUNNOW_API_URL="$RUNNOW_API_URL"

firebase deploy --only hosting --project "$PROJECT_ID"
