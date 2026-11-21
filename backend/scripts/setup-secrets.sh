#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCAL_SECRETS_FILE="${LOCAL_SECRETS_FILE:-${REPO_ROOT}/.secret/runnow.env}"
PROJECT_ID="${PROJECT_ID:-run-now-79767}"

if [[ ! -f "$LOCAL_SECRETS_FILE" ]]; then
  echo "Local secrets file not found: $LOCAL_SECRETS_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$LOCAL_SECRETS_FILE"
set +a

: "${STRAVA_CLIENT_SECRET:?Missing STRAVA_CLIENT_SECRET in $LOCAL_SECRETS_FILE}"
: "${STRAVA_WEBHOOK_VERIFY_TOKEN:?Missing STRAVA_WEBHOOK_VERIFY_TOKEN in $LOCAL_SECRETS_FILE}"

ensure_secret_value() {
  local name="$1"
  local value="$2"

  if ! gcloud secrets describe "$name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    printf '%s' "$value" | gcloud secrets create "$name" \
      --project "$PROJECT_ID" \
      --replication-policy automatic \
      --data-file=-
    echo "Created secret and initial version: $name"
    return
  fi

  local latest
  if latest="$(gcloud secrets versions access latest --secret "$name" --project "$PROJECT_ID" 2>/dev/null)"; then
    if [[ "$latest" == "$value" ]]; then
      echo "Secret already matches local value: $name"
      return
    fi
    printf '%s' "$value" | gcloud secrets versions add "$name" \
      --project "$PROJECT_ID" \
      --data-file=-
    echo "Added rotated secret version from local value: $name"
    return
  fi

  printf '%s' "$value" | gcloud secrets versions add "$name" \
    --project "$PROJECT_ID" \
    --data-file=-
  echo "Added initial enabled version: $name"
}

ensure_secret_value STRAVA_CLIENT_SECRET "$STRAVA_CLIENT_SECRET"
ensure_secret_value STRAVA_WEBHOOK_VERIFY_TOKEN "$STRAVA_WEBHOOK_VERIFY_TOKEN"

# Thông báo Telegram là tính năng tuỳ chọn — chỉ tạo secret nếu bạn đã set
# TELEGRAM_BOT_TOKEN trong $LOCAL_SECRETS_FILE (lấy token từ @BotFather).
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  ensure_secret_value TELEGRAM_BOT_TOKEN "$TELEGRAM_BOT_TOKEN"
fi

# Garmin tuỳ chọn: đặt GARMIN_CLIENT_SECRET (consumer secret trên portal Garmin)
# và GARMIN_WEBHOOK_TOKEN (chuỗi ngẫu nhiên, vd openssl rand -hex 24) trong
# $LOCAL_SECRETS_FILE.
if [[ -n "${GARMIN_CLIENT_SECRET:-}" ]]; then
  ensure_secret_value GARMIN_CLIENT_SECRET "$GARMIN_CLIENT_SECRET"
  ensure_secret_value GARMIN_WEBHOOK_TOKEN "${GARMIN_WEBHOOK_TOKEN:?Set GARMIN_WEBHOOK_TOKEN with GARMIN_CLIENT_SECRET}"
fi

# Nói chuyện trong phòng chạy tuỳ chọn: LIVEKIT_API_SECRET là chuỗi ngẫu nhiên
# (vd openssl rand -base64 32), dùng chung cho api và máy voice-vm.sh.
if [[ -n "${LIVEKIT_API_SECRET:-}" ]]; then
  ensure_secret_value LIVEKIT_API_SECRET "$LIVEKIT_API_SECRET"
fi
