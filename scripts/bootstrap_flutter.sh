#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter CLI is required. Install Flutter, then run this script again." >&2
  exit 1
fi

flutter create \
  --platforms=ios,android \
  --org=com.3ae \
  --project-name=myrun \
  .

echo "Native scaffold created. Install ignored iOS secrets next with:"
echo "  scripts/configure_ios_secrets.sh /path/to/GoogleService-Info.plist"
