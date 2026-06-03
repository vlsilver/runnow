#!/usr/bin/env bash
set -euo pipefail

failures=0

check_command() {
  local command_name="$1"
  local install_hint="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$command_name"
  else
    printf 'missing %s: %s\n' "$command_name" "$install_hint"
    failures=$((failures + 1))
  fi
}

check_file() {
  local path="$1"
  local install_hint="$2"
  if [[ -f "$path" ]]; then
    printf 'ok      %s\n' "$path"
  else
    printf 'missing %s: %s\n' "$path" "$install_hint"
    failures=$((failures + 1))
  fi
}

check_command flutter 'install Flutter stable and add it to PATH'
check_command pod 'install CocoaPods after activating full Xcode'

if xcodebuild -version >/dev/null 2>&1; then
  printf 'ok      full Xcode\n'
else
  printf 'missing full Xcode: install Xcode and run xcode-select --switch\n'
  failures=$((failures + 1))
fi

check_file ios/Runner/GoogleService-Info.plist \
  'run scripts/configure_ios_secrets.sh with the Firebase plist'

if grep -q 'GoogleService-Info\.plist in Resources' ios/Runner.xcodeproj/project.pbxproj; then
  printf 'ok      Firebase plist included in Runner resources\n'
else
  printf 'missing Firebase plist Runner resource: add GoogleService-Info.plist to the Runner target\n'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '\niOS readiness failed with %d missing requirement(s).\n' "$failures"
  exit 1
fi

printf '\niOS environment is ready for Firebase-backed acceptance testing.\n'
