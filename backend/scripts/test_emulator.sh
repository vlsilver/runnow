#!/usr/bin/env bash
# Chạy test Go kể cả test cần Firestore và Auth emulator (build tag `emulator`).
# Emulator chạy project demo-runnow, không đụng project thật.
#
#   backend/scripts/test_emulator.sh                          # cả backend
#   backend/scripts/test_emulator.sh -run Emulator -v ./internal/backend
set -euo pipefail
cd "$(dirname "$0")/../.."
# Quote lại từng tham số vì emulators:exec chạy lệnh qua shell (-run 'A|B').
args="./..."
if [ $# -gt 0 ]; then args="$(printf '%q ' "$@")"; fi
exec npx firebase-tools emulators:exec --only firestore,auth --project demo-runnow \
  "cd backend && go test -tags emulator -count=1 $args"
