#!/usr/bin/env bash
set -euo pipefail

OUT=/out
SERIAL="${ANDROID_SERIAL:-emulator:5555}"
PACKAGE="${APP_PACKAGE:-com.songloft.songloft_flutter}"
SERVER_HOST="${SERVER_HOST:-host.docker.internal}"
SERVER_PORT="${SERVER_PORT:-58192}"
mkdir -p "$OUT"

if [ -n "${ADBKEY:-}" ]; then
  mkdir -p /root/.android
  printf '%s\n' "$ADBKEY" >/root/.android/adbkey
  chmod 600 /root/.android/adbkey
fi

echo "[runner] waiting for emulator $SERIAL"
adb connect "$SERIAL" >/dev/null || true
for _ in $(seq 1 90); do
  if adb -s "$SERIAL" get-state 2>/dev/null | grep -q '^device$'; then
    break
  fi
  adb connect "$SERIAL" >/dev/null 2>&1 || true
  sleep 2
done
adb -s "$SERIAL" wait-for-device
for _ in $(seq 1 90); do
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  sleep 2
done
[ "$(adb -s "$SERIAL" shell getprop sys.boot_completed | tr -d '\r')" = 1 ]

echo "[runner] configuring deterministic Android display"
adb -s "$SERIAL" shell settings put global window_animation_scale 0
adb -s "$SERIAL" shell settings put global transition_animation_scale 0
adb -s "$SERIAL" shell settings put global animator_duration_scale 0
adb -s "$SERIAL" shell settings put system screen_off_timeout 1800000
adb -s "$SERIAL" shell settings put system system_locales zh-CN || true
echo "[runner] forwarding server ${SERVER_HOST}:${SERVER_PORT}"
socat "TCP-LISTEN:${SERVER_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${SERVER_HOST}:${SERVER_PORT}" >/tmp/server-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT
adb -s "$SERIAL" reverse "tcp:${SERVER_PORT}" "tcp:${SERVER_PORT}"

echo "[runner] installing downloader plugin"
bootstrap_token=$(curl -fsS "http://${SERVER_HOST}:${SERVER_PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data '{"username":"admin","password":"admin"}' | jq -r '.access_token')
curl -fsS "http://${SERVER_HOST}:${SERVER_PORT}/api/v1/jsplugins/upload" \
  -H "Authorization: Bearer ${bootstrap_token}" \
  -F "file=@${OUT}/downloader.jsplugin.zip" >"$OUT/plugin-upload.json"
curl -fsS "http://${SERVER_HOST}:${SERVER_PORT}/api/v1/jsplugins/" \
  -H "Authorization: Bearer ${bootstrap_token}" \
  | tee "$OUT/plugins.json" \
  | jq -e '.plugins[] | select(.entry_path == "downloader" and .render_engine == "webf")' >/dev/null

echo "[runner] installing APK"
adb -s "$SERIAL" install -r -g "$OUT/songloft-x86_64-release.apk" >"$OUT/install.log"
adb -s "$SERIAL" shell pm clear "$PACKAGE" >/dev/null
adb -s "$SERIAL" shell monkey -p "$PACKAGE" 1 >"$OUT/launch.log"

wait_for_text() {
  python3 /opt/webf-android-runner/ui.py "$SERIAL" wait "$1" --timeout "${2:-30}"
}

click_text() {
  python3 /opt/webf-android-runner/ui.py "$SERIAL" click "$1"
}

echo "[runner] logging in"
wait_for_text 'API 地址|服务器地址|API URL|Server URL' 30
click_text 'API 地址|服务器地址|API URL|Server URL'
adb -s "$SERIAL" shell input text "http://localhost:${SERVER_PORT}"
click_text '用户名|Username'
adb -s "$SERIAL" shell input text admin
click_text '密码|Password'
adb -s "$SERIAL" shell input text admin
click_text '登录|Login'
wait_for_text '歌曲下载' 45

echo "[runner] opening downloader WebF page"
click_text '歌曲下载'
sleep 5
adb -s "$SERIAL" exec-out screencap -p >"$OUT/plugin-main.png"

# The WebF button is a content-desc in most Android builds. The fallback tap
# targets the fixed action row of the known 1080x2400 emulator profile.
if ! click_text '下载设置'; then
  adb -s "$SERIAL" shell input tap 1010 245
fi
wait_for_text '路径与命名' 30
wait_for_text '嵌入元数据' 30
sleep 2

echo "[runner] capturing downloader settings"
adb -s "$SERIAL" exec-out screencap -p >"$OUT/settings-light.png"
adb -s "$SERIAL" shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb -s "$SERIAL" exec-out cat /sdcard/window.xml >"$OUT/uiautomator.xml" || true

python3 /usr/local/bin/assert-switch-alignment.py "$OUT/settings-light.png" >"$OUT/assertion.json"

echo "[runner] verifying switch interaction through the server"
before=$(curl -fsS "http://${SERVER_HOST}:${SERVER_PORT}/api/v1/jsplugin/downloader/api/settings" \
  -H "Authorization: Bearer ${bootstrap_token}")

python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path('/out/assertion.json').read_text())
switch = data['switches'][0]
print(f"[runner] tapping first switch at {((switch['left'] + switch['right']) // 2)} {((switch['top'] + switch['bottom']) // 2)}")
Path('/out/first-switch.json').write_text(json.dumps(switch))
PY
switch_x=$(jq -r '(.left + .right) / 2 | floor' "$OUT/first-switch.json")
switch_y=$(jq -r '(.top + .bottom) / 2 | floor' "$OUT/first-switch.json")
adb -s "$SERIAL" shell input tap "$switch_x" "$switch_y"
sleep 2
after=$(curl -fsS "http://${SERVER_HOST}:${SERVER_PORT}/api/v1/jsplugin/downloader/api/settings" \
  -H "Authorization: Bearer ${bootstrap_token}")
printf '%s\n' "$before" >"$OUT/settings-before.json"
printf '%s\n' "$after" >"$OUT/settings-after.json"

python3 - <<'PY'
import json
from pathlib import Path

before = json.loads(Path('/out/settings-before.json').read_text())
after = json.loads(Path('/out/settings-after.json').read_text())
if before.get('embed_metadata') == after.get('embed_metadata'):
    raise SystemExit('switch tap did not change embed_metadata on the server')
print('[runner] server state changed:', before.get('embed_metadata'), '->', after.get('embed_metadata'))
PY

adb -s "$SERIAL" logcat -d >"$OUT/logcat.txt"
adb -s "$SERIAL" shell dumpsys package "$PACKAGE" >"$OUT/package-dump.txt"
echo "[runner] Android WebF verification passed"
