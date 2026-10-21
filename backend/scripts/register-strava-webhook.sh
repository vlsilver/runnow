#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCAL_SECRETS_FILE="${LOCAL_SECRETS_FILE:-${REPO_ROOT}/.secret/runnow.env}"
LOCAL_CONFIG_FILE="${LOCAL_CONFIG_FILE:-${REPO_ROOT}/.secret/config.json}"
if [[ -f "$LOCAL_SECRETS_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_SECRETS_FILE"
  set +a
fi

if [[ -z "${API_URL:-}" && -f "$LOCAL_CONFIG_FILE" ]]; then
  command -v jq >/dev/null 2>&1 || {
    echo "jq is required to read $LOCAL_CONFIG_FILE" >&2
    exit 1
  }
  API_URL="$(jq -er '.["API URL"] | select(type == "string" and length > 0)' "$LOCAL_CONFIG_FILE")"
fi

: "${STRAVA_CLIENT_ID:?Set STRAVA_CLIENT_ID}"
: "${STRAVA_CLIENT_SECRET:?Set STRAVA_CLIENT_SECRET}"
: "${STRAVA_WEBHOOK_VERIFY_TOKEN:?Set STRAVA_WEBHOOK_VERIFY_TOKEN}"
: "${API_URL:?Set API_URL or add API URL to $LOCAL_CONFIG_FILE}"

curl --fail-with-body --request POST 'https://www.strava.com/api/v3/push_subscriptions' \
  --form-string "client_id=${STRAVA_CLIENT_ID}" \
  --form-string "client_secret=${STRAVA_CLIENT_SECRET}" \
  --form-string "callback_url=${API_URL%/}/v1/strava/webhook" \
  --form-string "verify_token=${STRAVA_WEBHOOK_VERIFY_TOKEN}"
