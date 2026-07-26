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

PROJECT_ID="${PROJECT_ID:-run-now-79767}"
REGION="${REGION:-asia-southeast1}"
REPOSITORY="${REPOSITORY:-runnow-backend}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/backend:${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
API_SERVICE="${API_SERVICE:-runnow-api}"
WORKER_SERVICE="${WORKER_SERVICE:-runnow-worker}"
BOT_SERVICE="${BOT_SERVICE:-runnow-bot}"
API_RUNTIME_SA_NAME="${API_RUNTIME_SA_NAME:-runnow-api-runtime}"
WORKER_RUNTIME_SA_NAME="${WORKER_RUNTIME_SA_NAME:-runnow-worker-runtime}"
BOT_RUNTIME_SA_NAME="${BOT_RUNTIME_SA_NAME:-runnow-bot-runtime}"
INVOKER_SA_NAME="${INVOKER_SA_NAME:-runnow-task-invoker}"
SCHEDULER_JOB="${SCHEDULER_JOB:-runnow-strava-reconcile}"
API_RUNTIME_SA="${API_RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WORKER_RUNTIME_SA="${WORKER_RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BOT_RUNTIME_SA="${BOT_RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
INVOKER_SA="${INVOKER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

: "${STRAVA_CLIENT_ID:?Set STRAVA_CLIENT_ID before running deploy.sh}"
: "${MOBILE_RETURN_URI:=com.threei.run://localhost/oauth}"
: "${WEB_RETURN_URI:=https://run-now-79767.web.app/oauth}"
: "${ALLOWED_WEB_ORIGINS:=https://run-now-79767.web.app}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

validate_resource_id() {
  local kind="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
    echo "Invalid ${kind} ID '${value}': use lowercase letters, numbers, and hyphens; start with a letter." >&2
    exit 1
  fi
}

ensure_service_account() {
  local name="$1"
  local display_name="$2"
  if ! gcloud iam service-accounts describe "${name}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$name" --display-name "$display_name" --project "$PROJECT_ID"
  fi
}

ensure_queue() {
  local queue="$1"
  local rate="$2"
  local concurrency="$3"
  if ! gcloud tasks queues describe "$queue" --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud tasks queues create "$queue" \
      --location "$REGION" \
      --max-dispatches-per-second "$rate" \
      --max-concurrent-dispatches "$concurrency" \
      --max-attempts 8 \
      --project "$PROJECT_ID"
  fi
}

require_secret() {
  if ! gcloud secrets describe "$1" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "Missing Secret Manager secret: $1" >&2
    exit 1
  fi
  if ! gcloud secrets versions access latest \
    --secret "$1" \
    --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "Secret Manager secret has no accessible enabled latest version: $1" >&2
    echo "Run ./scripts/setup-secrets.sh before deploy." >&2
    exit 1
  fi
}

write_env_file() {
  local target="$1"
  local public_url="$2"
  local worker_url="$3"
  cat >"$target" <<EOF
NODE_ENV: production
GOOGLE_CLOUD_PROJECT: ${PROJECT_ID}
GOOGLE_CLOUD_REGION: ${REGION}
PUBLIC_BASE_URL: ${public_url}
WORKER_BASE_URL: ${worker_url}
WEB_BASE_URL: ${WEB_BASE_URL:-https://threei.run}
MOBILE_RETURN_URI: ${MOBILE_RETURN_URI}
WEB_RETURN_URI: ${WEB_RETURN_URI}
ALLOWED_WEB_ORIGINS: ${ALLOWED_WEB_ORIGINS}
STRAVA_CLIENT_ID: '${STRAVA_CLIENT_ID}'
STRAVA_SUBSCRIPTION_ID: '${STRAVA_SUBSCRIPTION_ID:-}'
TASK_INVOKER_SERVICE_ACCOUNT: ${INVOKER_SA}
STRAVA_EVENTS_QUEUE: strava-events
STRAVA_BACKFILL_QUEUE: strava-backfill
DERIVED_DATA_QUEUE: derived-data
NOTIFY_QUEUE: notifications
BOT_INBOUND_QUEUE: bot-inbound
TELEGRAM_CHAT_ID: '${TELEGRAM_CHAT_ID:-}'
TELEGRAM_BOT_USERNAME: '${TELEGRAM_BOT_USERNAME:-}'
TELEGRAM_WEBHOOK_SECRET: '${TELEGRAM_WEBHOOK_SECRET:-}'
GEMINI_LOCATION: '${GEMINI_LOCATION:-us-central1}'
GEMINI_MODEL: '${GEMINI_MODEL:-gemini-2.5-pro}'
BOT_HOURLY_LIMIT: '${BOT_HOURLY_LIMIT:-100}'
EOF
}

require_command gcloud
validate_resource_id "Artifact Registry repository" "$REPOSITORY"
validate_resource_id "Cloud Run API service" "$API_SERVICE"
validate_resource_id "Cloud Run worker service" "$WORKER_SERVICE"
validate_resource_id "Cloud Run bot service" "$BOT_SERVICE"
validate_resource_id "API service account" "$API_RUNTIME_SA_NAME"
validate_resource_id "worker service account" "$WORKER_RUNTIME_SA_NAME"
validate_resource_id "bot service account" "$BOT_RUNTIME_SA_NAME"
validate_resource_id "invoker service account" "$INVOKER_SA_NAME"
validate_resource_id "Scheduler job" "$SCHEDULER_JOB"

printf '%s\n' \
  "Deploy configuration:" \
  "  project:    ${PROJECT_ID}" \
  "  region:     ${REGION}" \
  "  repository: ${REPOSITORY}" \
  "  api:        ${API_SERVICE}" \
  "  worker:     ${WORKER_SERVICE}"

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  cloudtasks.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  firestore.googleapis.com \
  aiplatform.googleapis.com \
  --project "$PROJECT_ID"

if ! gcloud artifacts repositories describe "$REPOSITORY" --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$REPOSITORY" \
    --repository-format docker \
    --location "$REGION" \
    --project "$PROJECT_ID"
fi

ensure_service_account "$API_RUNTIME_SA_NAME" "3I API runtime"
ensure_service_account "$WORKER_RUNTIME_SA_NAME" "3I worker runtime"
ensure_service_account "$BOT_RUNTIME_SA_NAME" "3I bot runtime"
ensure_service_account "$INVOKER_SA_NAME" "3I Cloud Tasks and Scheduler invoker"

for runtime_sa in "$API_RUNTIME_SA" "$WORKER_RUNTIME_SA" "$BOT_RUNTIME_SA"; do
  for role in roles/datastore.user roles/cloudtasks.enqueuer roles/secretmanager.secretAccessor; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member "serviceAccount:${runtime_sa}" \
      --role "$role" \
      --condition=None >/dev/null
  done
  gcloud iam service-accounts add-iam-policy-binding "$INVOKER_SA" \
    --member "serviceAccount:${runtime_sa}" \
    --role roles/iam.serviceAccountUser \
    --project "$PROJECT_ID" >/dev/null
done

# Chỉ API service xoá tài khoản, nên chỉ nó cần quyền gỡ user khỏi Firebase
# Auth và xoá ảnh trong Storage. Worker không đụng tới hai thứ này.
for role in roles/firebaseauth.admin roles/storage.objectAdmin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${API_RUNTIME_SA}" \
    --role "$role" \
    --condition=None >/dev/null
done

# Cả hai service gọi Gemini qua Vertex AI: API cho bot Q&A, worker cho chưng
# cất trí nhớ đêm và nhận xét buổi chạy. Cùng service account nên không phải
# quản thêm API key — xác thực bằng chính danh tính Cloud Run.
for ai_sa in "$API_RUNTIME_SA" "$WORKER_RUNTIME_SA" "$BOT_RUNTIME_SA"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${ai_sa}" \
    --role roles/aiplatform.user \
    --condition=None >/dev/null
done

ensure_queue strava-events 5 2
ensure_queue strava-backfill 2 1
ensure_queue derived-data 20 8
ensure_queue notifications 20 8
# bot-inbound: xử lý tin bot song song có kiểm soát. Concurrency 6 — mỗi task
# một cú Gemini Pro, quá nhiều cùng lúc dễ dính 429 Vertex AI (đã có retry).
ensure_queue bot-inbound 10 6
require_secret STRAVA_CLIENT_SECRET
require_secret STRAVA_WEBHOOK_VERIFY_TOKEN
# Telegram thông báo hoạt động là tính năng tuỳ chọn — chỉ đòi hỏi secret
# này nếu bạn thật sự đang cấu hình nó (set TELEGRAM_BOT_TOKEN trước khi
# chạy script), để không chặn deploy ở môi trường chưa muốn bật.
BASE_SECRETS="STRAVA_CLIENT_SECRET=STRAVA_CLIENT_SECRET:latest,STRAVA_WEBHOOK_VERIFY_TOKEN=STRAVA_WEBHOOK_VERIFY_TOKEN:latest"
WORKER_SECRETS="$BASE_SECRETS"
API_SECRETS="$BASE_SECRETS"
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  require_secret TELEGRAM_BOT_TOKEN
  # Worker cần token để gửi thông báo hoạt động Strava; API cần để bot trả
  # lời trong group Telegram. Thiếu ở API thì telegram.Enabled()=false nên
  # Bot=nil và mọi câu hỏi rơi vào im lặng.
  WORKER_SECRETS="${WORKER_SECRETS},TELEGRAM_BOT_TOKEN=TELEGRAM_BOT_TOKEN:latest"
  API_SECRETS="${API_SECRETS},TELEGRAM_BOT_TOKEN=TELEGRAM_BOT_TOKEN:latest"
fi

for ttl_collection in oauthStates integrationEvents activityTombstones botRateLimits botMessages; do
  gcloud firestore fields ttls update expiresAt \
    --collection-group "$ttl_collection" \
    --enable-ttl \
    --project "$PROJECT_ID" >/dev/null
done

# Chỉ đích danh thư mục backend thay vì "." — Dockerfile nằm ở đó, còn "."
# là thư mục người dùng đang đứng lúc gọi script, chạy từ scripts/ sẽ lỗi
# "Dockerfile required when specifying --tag".
gcloud builds submit "${SCRIPT_DIR}/.." --tag "$IMAGE" --project "$PROJECT_ID"

temporary_env="$(mktemp)"
trap 'rm -f "$temporary_env"' EXIT
placeholder_url="https://bootstrap.invalid"
write_env_file "$temporary_env" "$placeholder_url" "$placeholder_url"

gcloud run deploy "$WORKER_SERVICE" \
  --image "$IMAGE" \
  --command /worker \
  --args '' \
  --default-url \
  --region "$REGION" \
  --service-account "$WORKER_RUNTIME_SA" \
  --env-vars-file "$temporary_env" \
  --set-secrets "$WORKER_SECRETS" \
  --no-allow-unauthenticated \
  --min-instances 0 \
  --max-instances 5 \
  --concurrency 8 \
  --project "$PROJECT_ID"

WORKER_URL="$(gcloud run services describe "$WORKER_SERVICE" --region "$REGION" --project "$PROJECT_ID" --format='value(status.url)')"
write_env_file "$temporary_env" "$placeholder_url" "$WORKER_URL"

gcloud run deploy "$API_SERVICE" \
  --image "$IMAGE" \
  --command /api \
  --args '' \
  --default-url \
  --ingress all \
  --region "$REGION" \
  --service-account "$API_RUNTIME_SA" \
  --env-vars-file "$temporary_env" \
  --set-secrets "$API_SECRETS" \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 5 \
  --concurrency 80 \
  --project "$PROJECT_ID"

API_URL="$(gcloud run services describe "$API_SERVICE" --region "$REGION" --project "$PROJECT_ID" --format='value(status.url)')"
write_env_file "$temporary_env" "$API_URL" "$WORKER_URL"

# runnow-bot: service PRIVATE (như worker) để xử lý riêng phần AI. Deploy sau
# khi đã có URL api/worker để env đầy đủ. Bước này CHƯA trỏ traffic tới nó —
# chỉ dựng lên và verify. Concurrency 6 khớp queue bot-inbound.
gcloud run deploy "$BOT_SERVICE" \
  --image "$IMAGE" \
  --command /bot \
  --args '' \
  --default-url \
  --region "$REGION" \
  --service-account "$BOT_RUNTIME_SA" \
  --env-vars-file "$temporary_env" \
  --set-secrets "$WORKER_SECRETS" \
  --no-allow-unauthenticated \
  --min-instances 0 \
  --max-instances 5 \
  --concurrency 6 \
  --project "$PROJECT_ID"
BOT_URL="$(gcloud run services describe "$BOT_SERVICE" --region "$REGION" --project "$PROJECT_ID" --format='value(status.url)')"

# Cập nhật lại env (URL đầy đủ) cho api & worker.
write_env_file "$temporary_env" "$API_URL" "$WORKER_URL"
gcloud run services update "$WORKER_SERVICE" \
  --region "$REGION" \
  --env-vars-file "$temporary_env" \
  --project "$PROJECT_ID" >/dev/null
gcloud run services update "$API_SERVICE" \
  --region "$REGION" \
  --env-vars-file "$temporary_env" \
  --project "$PROJECT_ID" >/dev/null
gcloud run services update "$BOT_SERVICE" \
  --region "$REGION" \
  --env-vars-file "$temporary_env" \
  --project "$PROJECT_ID" >/dev/null

# Set BOT_BASE_URL RIÊNG bằng --update-env-vars (không qua env-file): env-file
# bỏ rơi biến có value rỗng ở các lần ghi sớm, nên cách này chắc ăn. API cần nó
# để TaskPublisher đẩy bot-inbound sang runnow-bot; set cả 3 cho nhất quán.
for svc in "$API_SERVICE" "$WORKER_SERVICE" "$BOT_SERVICE"; do
  gcloud run services update "$svc" \
    --region "$REGION" \
    --update-env-vars "BOT_BASE_URL=${BOT_URL}" \
    --project "$PROJECT_ID" >/dev/null
done

gcloud run services add-iam-policy-binding "$WORKER_SERVICE" \
  --region "$REGION" \
  --member "serviceAccount:${INVOKER_SA}" \
  --role roles/run.invoker \
  --project "$PROJECT_ID" >/dev/null
# Cho task-invoker gọi được runnow-bot (bot-inbound sẽ trỏ tới đây ở bước sau).
gcloud run services add-iam-policy-binding "$BOT_SERVICE" \
  --region "$REGION" \
  --member "serviceAccount:${INVOKER_SA}" \
  --role roles/run.invoker \
  --project "$PROJECT_ID" >/dev/null

if gcloud scheduler jobs describe "$SCHEDULER_JOB" --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  scheduler_action=update
  scheduler_header_flag=--update-headers
else
  scheduler_action=create
  scheduler_header_flag=--headers
fi
gcloud scheduler jobs "${scheduler_action}" http "$SCHEDULER_JOB" \
  --location "$REGION" \
  --schedule '17 */6 * * *' \
  --uri "${WORKER_URL}/tasks/reconcile-connections" \
  --http-method POST \
  "${scheduler_header_flag}" 'Content-Type=application/json' \
  --message-body '{}' \
  --oidc-service-account-email "$INVOKER_SA" \
  --oidc-token-audience "$WORKER_URL" \
  --project "$PROJECT_ID"

# Chưng cất trí nhớ bot mỗi đêm 20:00 giờ VN (13:00 UTC). Một lần/ngày là đủ
# — trí nhớ dài hạn không cần cập nhật liên tục.
MEMORY_JOB="${MEMORY_JOB:-runnow-bot-memory}"
if gcloud scheduler jobs describe "$MEMORY_JOB" --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  memory_action=update
  memory_header_flag=--update-headers
else
  memory_action=create
  memory_header_flag=--headers
fi
gcloud scheduler jobs "${memory_action}" http "$MEMORY_JOB" \
  --location "$REGION" \
  --schedule '0 13 * * *' \
  --uri "${WORKER_URL}/tasks/consolidate-memory" \
  --http-method POST \
  "${memory_header_flag}" 'Content-Type=application/json' \
  --message-body '{}' \
  --oidc-service-account-email "$INVOKER_SA" \
  --oidc-token-audience "$WORKER_URL" \
  --project "$PROJECT_ID"

echo "API URL: $API_URL"
echo "Worker URL: $WORKER_URL"
echo "Strava callback: ${API_URL}/v1/strava/callback"
echo "Strava webhook: ${API_URL}/v1/strava/webhook"

mkdir -p "$(dirname "$LOCAL_CONFIG_FILE")"
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg apiURL "$API_URL" \
    --arg workerURL "$WORKER_URL" \
    --arg callbackURL "${API_URL}/v1/strava/callback" \
    --arg webhookURL "${API_URL}/v1/strava/webhook" \
    --arg subscriptionID "${STRAVA_SUBSCRIPTION_ID:-}" \
    '{
      "RUNNOW_API_URL": $apiURL,
      "API URL": $apiURL,
      "Worker URL": $workerURL,
      "Strava callback": $callbackURL,
      "Strava webhook": $webhookURL,
      "Strava subscription ID": $subscriptionID
    }' >"$LOCAL_CONFIG_FILE"
  echo "Local deployment config: $LOCAL_CONFIG_FILE"
else
  echo "Warning: jq not found; skipped writing $LOCAL_CONFIG_FILE" >&2
fi
