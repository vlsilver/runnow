#!/bin/sh
# Chọn GoogleService-Info.plist theo dart-define APP_ENV (env/<tên>.json).
# firebase_core tự configure app mặc định từ plist trong bundle trước khi Dart
# chạy, nên phải đổi plist ở bước build chứ không đổi được từ Dart.
# - APP_ENV trống hoặc prod: giữ ios/Runner/GoogleService-Info.plist (prod).
# - APP_ENV khác: chép ios/config/<APP_ENV>/GoogleService-Info.plist đè lên.
set -e

app_env=""
for item in $(echo "${DART_DEFINES}" | tr ',' ' '); do
  decoded=$(echo "${item}" | base64 --decode)
  case "${decoded}" in
    APP_ENV=*) app_env="${decoded#APP_ENV=}" ;;
  esac
done

if [ -z "${app_env}" ] || [ "${app_env}" = "prod" ]; then
  exit 0
fi

# Xcode Archive dùng lại DART_DEFINES của lần `flutter run` gần nhất, nên một
# lần chạy staging trước đó có thể lọt vào bản phát hành. Chặn ở đây.
if [ "${CONFIGURATION}" = "Release" ]; then
  echo "error: bản Release đang build với APP_ENV=${app_env}. Build lại bằng env/prod.json hoặc flutter build ipa." >&2
  exit 1
fi

src="${SRCROOT}/config/${app_env}/GoogleService-Info.plist"
if [ ! -f "${src}" ]; then
  echo "error: APP_ENV=${app_env} nhưng thiếu ${src} (chạy scripts/configure_ios_secrets.sh <plist> ${app_env})" >&2
  exit 1
fi
cp "${src}" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
echo "GoogleService-Info.plist: dùng bản ${app_env}"
