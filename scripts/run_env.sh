#!/usr/bin/env bash
# Chạy hoặc build app theo môi trường: đọc env/<env>.json làm dart-define.
#   scripts/run_env.sh staging                 # flutter run
#   scripts/run_env.sh staging build ios --simulator
#   scripts/run_env.sh prod
# Mọi tham số sau tên môi trường đi thẳng vào flutter (mặc định là `run`).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <prod|staging> [flutter args...]" >&2
  exit 1
fi

app_env="$1"
shift
env_file="env/$app_env.json"
if [[ ! -f "$env_file" ]]; then
  echo "Không có $env_file. Môi trường có sẵn: $(ls env | sed 's/\.json$//' | tr '\n' ' ')" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  set -- run
fi
exec flutter "$@" --dart-define-from-file="$env_file"
