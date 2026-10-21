#!/usr/bin/env bash
# Chạy luồng Ma Sói qua API: tạo ván → đăng ký → dryRun → Start, kèm hai ca âm
# (user thường gọi start thì 403, người ngoài ván gọi /me thì 404). Sai mã nào
# là dừng, exit 1.
#
#   BASE_URL=https://<api> ADMIN_TOKEN=<id token> OUTSIDER_TOKEN=<id token> \
#   TEST_CHAT_ID=<chat id group test> CANCEL_AT_END=1 backend/scripts/game_smoke.sh
#
# ADMIN_TOKEN     ID token Firebase của một uid trong gameState/config.adminUids,
#                 đã liên kết Telegram và đang ở PSC.
# OUTSIDER_TOKEN  ID token của tài khoản thường, không đăng ký ván này.
# PLAYER_TOKENS   (tuỳ chọn) token của người chơi thật khác, cách nhau bởi dấu cách.
#                 Với ván thử, uid của họ phải nằm trong testerUids, không thì 404.
# TEST_CHAT_ID    Có thì tạo ván thử trong group đó và thêm người giả cho đủ 10.
#                 Không có thì tạo ván thật trong PSC, cần đủ 10 người thật.
# APP_VERSION     (tuỳ chọn) gửi trong X-App-Version, khi config có minAppVersion.
# CANCEL_AT_END   =1 thì huỷ ván ở cuối.
# POLL_SECONDS    Đợi bot chia bài tối đa bao lâu, mặc định 60.
#
# Script tạo ván thật trên môi trường BASE_URL trỏ tới. Đang có ván chưa kết thúc
# thì dừng ở 409 game_running.
set -euo pipefail

: "${BASE_URL:?thiếu BASE_URL}"
: "${ADMIN_TOKEN:?thiếu ADMIN_TOKEN}"
: "${OUTSIDER_TOKEN:?thiếu OUTSIDER_TOKEN}"
POLL_SECONDS="${POLL_SECONDS:-60}"
command -v jq >/dev/null || { echo "cần jq" >&2; exit 1; }

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

# call <token> <method> <path> <mã mong đợi> [body]: in body ra stdout.
call() {
  local token="$1" method="$2" path="$3" want="$4" data="${5:-}"
  local args=(-sS -o "$body_file" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $token")
  if [ -n "${APP_VERSION:-}" ]; then args+=(-H "X-App-Version: $APP_VERSION"); fi
  if [ -n "$data" ]; then args+=(-H 'Content-Type: application/json' --data "$data"); fi
  local got
  got="$(curl "${args[@]}" "$BASE_URL$path")"
  if [ "$got" != "$want" ]; then
    echo "FAIL $method $path: $got, mong đợi $want" >&2
    cat "$body_file" >&2; echo >&2
    exit 1
  fi
  cat "$body_file"
}

step() { echo "== $*"; }

step "Tạo ván"
if [ -n "${TEST_CHAT_ID:-}" ]; then
  create="$(jq -cn --arg chat "$TEST_CHAT_ID" '{testMode: true, chatId: $chat}')"
else
  create='{}'
fi
id="$(call "$ADMIN_TOKEN" POST /v1/games 201 "$create" | jq -r .id)"
echo "gameId=$id"

step "Đăng ký"
count="$(call "$ADMIN_TOKEN" POST "/v1/games/$id/registration" 200 | jq .playerCount)"
for tok in ${PLAYER_TOKENS:-}; do
  count="$(call "$tok" POST "/v1/games/$id/registration" 200 | jq .playerCount)"
done
echo "đã đăng ký $count người thật"
if [ -n "${TEST_CHAT_ID:-}" ] && [ "$count" -lt 10 ]; then
  call "$ADMIN_TOKEN" POST "/v1/games/$id/admin/fake-players" 200 "{\"count\": $((10 - count))}" | jq -c .uids
fi

step "Ca âm"
call "$OUTSIDER_TOKEN" POST "/v1/games/$id/start" 403 | jq -r .error
call "$OUTSIDER_TOKEN" GET "/v1/games/$id/me" 404 | jq -r .error

step "dryRun"
preview="$(call "$ADMIN_TOKEN" POST "/v1/games/$id/start?dryRun=true" 200)"
echo "$preview" | jq -r '"count=\(.count) canStart=\(.canStart) balanceScore=\(.balanceScore)"'
echo "$preview" | jq -r '.players[] | "  \(.uid)\t\(.name)\t@\(.tgUsername // "-")\(if .fake then "\tgiả" else "" end)"'
echo "$preview" | jq -r '.willExclude[] | "  loại \(.uid)\t\(.name)\t\(.reasonLabel)"'
if [ "$(echo "$preview" | jq .canStart)" != "true" ]; then
  echo "FAIL chưa Start được: chỉ có $(echo "$preview" | jq .count) người đủ điều kiện" >&2
  exit 1
fi

step "Start"
call "$ADMIN_TOKEN" POST "/v1/games/$id/start" 202 | jq -c .
waited=0
while :; do
  detail="$(call "$ADMIN_TOKEN" GET "/v1/games/$id" 200)"
  status="$(echo "$detail" | jq -r .status)"
  if [ "$status" != starting ] || [ "$waited" -ge "$POLL_SECONDS" ]; then break; fi
  sleep 2
  waited=$((waited + 2))
done
echo "status=$status"
if [ "$status" != running ]; then
  echo "FAIL bot chưa chia bài xong: $(echo "$detail" | jq -c '.startError // empty')" >&2
  exit 1
fi
echo "admin nhận vai: $(call "$ADMIN_TOKEN" GET "/v1/games/$id/me" 200 | jq -r .roleLabel)"

if [ "${CANCEL_AT_END:-}" = 1 ]; then
  step "Huỷ ván"
  call "$ADMIN_TOKEN" POST "/v1/games/$id/admin/cancel" 200 | jq -c .
fi
echo "OK"
