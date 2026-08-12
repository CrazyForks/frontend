#!/usr/bin/env bash
set -euo pipefail

cd /workspace
mkdir -p /out

# 源码以卷形式挂载、`.dart_tool` 单独挂卷，故每次先 pub get 解析依赖
# （命中 pub-cache 卷很快）。这比 `docker compose build` 重建镜像里的
# `RUN flutter pub get`（无缓存、~15min）快得多。
flutter pub get

flutter build apk \
  --release \
  --target-platform android-x64 \
  --dart-define=DEPLOY_MODE=standalone \
  --dart-define=HAS_BACKEND=false \
  --dart-define=FRONTEND_VERSION="${FRONTEND_VERSION:-webf-android-test}" \
  --dart-define=FLUTTER_BINDING="${FLUTTER_BINDING:-3.44.6}"

apk="build/app/outputs/flutter-apk/app-release.apk"
test -f "$apk"
cp "$apk" /out/songloft-x86_64-release.apk
sha256sum /out/songloft-x86_64-release.apk | tee /out/apk.sha256
