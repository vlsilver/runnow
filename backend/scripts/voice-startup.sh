#!/usr/bin/env bash
# Startup script của máy runnow-voice (voice-vm.sh gắn vào metadata), chạy lại
# mỗi lần boot: dựng server LiveKit tự host cho nói chuyện trong phòng chạy và
# Caddy lo TLS cho domain voice. Secret đọc từ Secret Manager bằng SA của máy,
# không nằm trong metadata; mỗi lần boot đọc lại nên đổi secret xong chỉ cần
# reset máy.
set -euo pipefail

LIVEKIT_IMAGE="livekit/livekit-server:v1.13.10"
CADDY_IMAGE="caddy:2.11.7-alpine"
MD="http://metadata.google.internal/computeMetadata/v1"

md() { curl -sf -H 'Metadata-Flavor: Google' "${MD}/$1"; }

if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y docker.io
fi

PROJECT_ID="$(md project/project-id)"
KEY="$(md instance/attributes/livekit-key)"
DOMAIN="$(md instance/attributes/voice-domain)"
ACCESS_TOKEN="$(md instance/service-accounts/default/token | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
SECRET="$(curl -sf -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/LIVEKIT_API_SECRET/versions/latest:access" |
  python3 -c 'import base64,json,sys; print(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode())')"

install -d -m 700 /etc/livekit
install -d -m 700 /var/lib/caddy
umask 077
# Cổng 7880 chỉ cho Caddy gọi qua localhost (firewall không mở). Media đi
# 7881/tcp và 7882/udp; use_external_ip để LiveKit báo IP public cho client
# thay vì IP nội bộ của VPC.
cat >/etc/livekit/livekit.yaml <<EOF
port: 7880
rtc:
  tcp_port: 7881
  udp_port: 7882
  use_external_ip: true
keys:
  ${KEY}: ${SECRET}
logging:
  level: info
EOF
cat >/etc/livekit/Caddyfile <<EOF
${DOMAIN} {
  reverse_proxy 127.0.0.1:7880
}
EOF

docker rm -f livekit caddy >/dev/null 2>&1 || true
docker run -d --name livekit --restart always --network host \
  -v /etc/livekit/livekit.yaml:/etc/livekit.yaml:ro \
  "$LIVEKIT_IMAGE" --config /etc/livekit.yaml
docker run -d --name caddy --restart always --network host \
  -v /etc/livekit/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v /var/lib/caddy:/data \
  "$CADDY_IMAGE"
