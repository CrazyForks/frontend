#!/usr/bin/env bash
set -euo pipefail

cd /workspace
mkdir -p /out

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
