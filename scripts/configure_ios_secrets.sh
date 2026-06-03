#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/GoogleService-Info.plist" >&2
  exit 1
fi

firebase_plist="$1"
if [[ ! -f "$firebase_plist" ]]; then
  echo "Firebase plist not found: $firebase_plist" >&2
  exit 1
fi

cp "$firebase_plist" ios/Runner/GoogleService-Info.plist

echo "Installed ignored iOS Firebase configuration."
