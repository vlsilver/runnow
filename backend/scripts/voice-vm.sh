#!/usr/bin/env bash
# Dựng máy runnow-voice: IP tĩnh, SA chỉ đọc được LIVEKIT_API_SECRET, firewall
# cho TLS và media, VM e2-micro chạy voice-startup.sh. Chạy lại được: thứ gì
# có rồi thì bỏ qua. Chạy sau setup-secrets.sh (cần secret LIVEKIT_API_SECRET).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCAL_SECRETS_FILE="${LOCAL_SECRETS_FILE:-${REPO_ROOT}/.secret/runnow.env}"
if [[ -f "$LOCAL_SECRETS_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_SECRETS_FILE"
  set +a
fi

PROJECT_ID="${PROJECT_ID:-run-now-79767}"
REGION="${REGION:-asia-southeast1}"
ZONE="${ZONE:-asia-southeast1-b}"
VM="${VOICE_VM:-runnow-voice}"
MACHINE_TYPE="${VOICE_MACHINE_TYPE:-e2-micro}"
ADDRESS="${VM}-ip"
TAG="$VM"
SA="${VM}@${PROJECT_ID}.iam.gserviceaccount.com"
: "${LIVEKIT_URL:?Set LIVEKIT_URL (wss://<domain>) in $LOCAL_SECRETS_FILE}"
: "${LIVEKIT_API_KEY:?Set LIVEKIT_API_KEY in $LOCAL_SECRETS_FILE}"
DOMAIN="${LIVEKIT_URL#wss://}"

gcloud secrets describe LIVEKIT_API_SECRET --project "$PROJECT_ID" >/dev/null

if ! gcloud compute addresses describe "$ADDRESS" --region "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute addresses create "$ADDRESS" --region "$REGION" --project "$PROJECT_ID"
fi
IP="$(gcloud compute addresses describe "$ADDRESS" --region "$REGION" --project "$PROJECT_ID" --format 'value(address)')"

if ! gcloud iam service-accounts describe "$SA" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$VM" --project "$PROJECT_ID" --display-name "RunNow voice (LiveKit)"
fi
gcloud secrets add-iam-policy-binding LIVEKIT_API_SECRET --project "$PROJECT_ID" \
  --member "serviceAccount:${SA}" --role roles/secretmanager.secretAccessor >/dev/null

# 80 cho Let's Encrypt cấp cert, 443 cho websocket signal, 7881/tcp và
# 7882/udp cho media. 7880 không mở: chỉ Caddy gọi qua localhost.
if ! gcloud compute firewall-rules describe "$VM" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute firewall-rules create "$VM" --project "$PROJECT_ID" \
    --network default --direction INGRESS --target-tags "$TAG" \
    --allow tcp:80,tcp:443,tcp:7881,udp:7882
fi

if ! gcloud compute instances describe "$VM" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute instances create "$VM" --project "$PROJECT_ID" --zone "$ZONE" \
    --machine-type "$MACHINE_TYPE" \
    --image-family debian-12 --image-project debian-cloud \
    --boot-disk-size 10GB --boot-disk-type pd-standard \
    --address "$IP" --tags "$TAG" \
    --service-account "$SA" --scopes cloud-platform \
    --metadata "livekit-key=${LIVEKIT_API_KEY},voice-domain=${DOMAIN}" \
    --metadata-from-file "startup-script=${SCRIPT_DIR}/voice-startup.sh"
else
  gcloud compute instances add-metadata "$VM" --zone "$ZONE" --project "$PROJECT_ID" \
    --metadata "livekit-key=${LIVEKIT_API_KEY},voice-domain=${DOMAIN}" \
    --metadata-from-file "startup-script=${SCRIPT_DIR}/voice-startup.sh"
fi

if [[ "$DOMAIN" != "$IP" ]]; then
  echo "Máy ${VM} chạy ở ${IP}. Trỏ bản ghi A ${DOMAIN} → ${IP}, rồi kiểm:"
else
  echo "Máy ${VM} chạy ở ${IP}. Khởi động lại máy nếu vừa đổi cấu hình, rồi kiểm:"
fi
echo "  curl -s https://${DOMAIN}   # LiveKit trả OK khi Caddy đã có cert"
