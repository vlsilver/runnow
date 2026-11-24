#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 /path/to/GoogleService-Info.plist [prod|staging]" >&2
  exit 1
fi

firebase_plist="$1"
if [[ ! -f "$firebase_plist" ]]; then
  echo "Firebase plist not found: $firebase_plist" >&2
  exit 1
fi

app_env="${2:-prod}"
if [[ "$app_env" == "prod" ]]; then
  dest=ios/Runner/GoogleService-Info.plist
else
  # Bản build có APP_ENV khác prod lấy plist ở đây (ios/scripts/use_firebase_env.sh).
  dest="ios/config/$app_env/GoogleService-Info.plist"
  mkdir -p "$(dirname "$dest")"
fi
cp "$firebase_plist" "$dest"

echo "Installed ignored iOS Firebase configuration."
