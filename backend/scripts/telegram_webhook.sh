#!/usr/bin/env bash
# Xem hoặc đặt lại webhook Telegram của bot 3i mà không làm mất secret_token.
#
#   backend/scripts/telegram_webhook.sh info
#   backend/scripts/telegram_webhook.sh set              # 5 loại update Ma Sói cần
#   backend/scripts/telegram_webhook.sh set message      # quay lại như trước T3
#
# setWebhook đặt lại TOÀN BỘ cấu hình: gọi thiếu secret_token là webhook mất
# secret, api trả 401 cho mọi update và 3i im. Script luôn gửi lại URL đang chạy
# và secret trong LOCAL_SECRETS_FILE. Không xoá update đang chờ.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCAL_SECRETS_FILE="${LOCAL_SECRETS_FILE:-${REPO_ROOT}/.secret/runnow.env}"
# shellcheck disable=SC1090
set -a && source "$LOCAL_SECRETS_FILE" && set +a
: "${TELEGRAM_BOT_TOKEN:?thiếu TELEGRAM_BOT_TOKEN trong $LOCAL_SECRETS_FILE}"
API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

info() {
  curl -fsS "$API/getWebhookInfo" | python3 -c '
import json, sys
r = json.load(sys.stdin)["result"]
print("url:", r.get("url") or "(chưa đặt)")
print("allowed_updates:", r.get("allowed_updates") or "(mặc định của Telegram)")
print("pending_update_count:", r.get("pending_update_count"))
print("last_error:", r.get("last_error_message"), r.get("last_error_date"))'
}

case "${1:-info}" in
  info) info ;;
  set)
    shift
    : "${TELEGRAM_WEBHOOK_SECRET:?thiếu TELEGRAM_WEBHOOK_SECRET trong $LOCAL_SECRETS_FILE}"
    types=("$@")
    [[ ${#types[@]} -eq 0 ]] && types=(message callback_query chat_member my_chat_member chat_join_request)
    url="$(curl -fsS "$API/getWebhookInfo" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"].get("url",""))')"
    [[ -n "$url" ]] || { echo "webhook chưa có URL, không tự đoán URL" >&2; exit 1; }
    # Body đi qua stdin để secret không nằm trên dòng lệnh (ps, history).
    python3 -c 'import json,os,sys; print(json.dumps({"url": sys.argv[1], "secret_token": os.environ["TELEGRAM_WEBHOOK_SECRET"], "allowed_updates": sys.argv[2:]}))' "$url" "${types[@]}" \
      | curl -fsS -X POST "$API/setWebhook" -H 'Content-Type: application/json' --data @- \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); print("setWebhook:", d.get("ok"), d.get("description",""))'
    info
    ;;
  *) echo "dùng: $0 info | set [loại update...]" >&2; exit 2 ;;
esac
