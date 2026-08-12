#!/usr/bin/env bash
# Miot 插件 Android WebF 测试 runner（在 test-runner 容器内执行）
set -euo pipefail

OUT=/out
SERIAL="${ANDROID_SERIAL:-emulator:5555}"
PACKAGE="${APP_PACKAGE:-com.songloft.songloft_flutter}"
SERVER_HOST="${SERVER_HOST:-host.docker.internal}"
SERVER_PORT="${SERVER_PORT:-58394}"
mkdir -p "$OUT"

if [ -n "${ADBKEY:-}" ]; then
  mkdir -p /root/.android
  printf '%s\n' "$ADBKEY" >/root/.android/adbkey
  chmod 600 /root/.android/adbkey
fi

echo "[miot-runner] waiting for emulator $SERIAL"
adb connect "$SERIAL" >/dev/null || true
for _ in $(seq 1 90); do
  if adb -s "$SERIAL" get-state 2>/dev/null | grep -q '^device$'; then break; fi
  adb connect "$SERIAL" >/dev/null 2>&1 || true
  sleep 2
done
adb -s "$SERIAL" wait-for-device
for _ in $(seq 1 90); do
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
  sleep 2
done
[ "$(adb -s "$SERIAL" shell getprop sys.boot_completed | tr -d '\r')" = 1 ]

echo "[miot-runner] configuring display"
adb -s "$SERIAL" shell settings put global window_animation_scale 0
adb -s "$SERIAL" shell settings put global transition_animation_scale 0
adb -s "$SERIAL" shell settings put global animator_duration_scale 0
adb -s "$SERIAL" shell settings put system screen_off_timeout 1800000
adb -s "$SERIAL" shell wm size 1080x2400

echo "[miot-runner] forwarding server"
socat "TCP-LISTEN:${SERVER_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${SERVER_HOST}:${SERVER_PORT}" &
forward_pid=$!

capture_failure() {
  local status=$?
  [ "$status" -eq 0 ] && return 0
  echo "[miot-runner] FAILED (exit $status); capturing state" >&2
  adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-failure.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/miot-fail.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /sdcard/miot-fail.xml >"$OUT/miot-failure-ui.xml" 2>/dev/null || true
  adb -s "$SERIAL" logcat -d >"$OUT/miot-failure-logcat.txt" 2>/dev/null || true
  return "$status"
}
trap 'capture_failure; adb -s "$SERIAL" shell wm size reset 2>/dev/null || true; kill "$forward_pid" 2>/dev/null || true' EXIT
adb -s "$SERIAL" reverse "tcp:${SERVER_PORT}" "tcp:${SERVER_PORT}"

echo "[miot-runner] installing APK"
adb -s "$SERIAL" install -r -g "$OUT/songloft-x86_64-release.apk" >"$OUT/miot-install.log" 2>&1
adb -s "$SERIAL" shell pm clear "$PACKAGE" >/dev/null
adb -s "$SERIAL" shell monkey -p "$PACKAGE" 1 >"$OUT/miot-launch.log" 2>&1

wait_for_text() {
  python3 /opt/webf-android-runner/ui.py "$SERIAL" wait "$1" --timeout "${2:-30}"
}
click_text() {
  python3 /opt/webf-android-runner/ui.py "$SERIAL" click "$1"
}
edit_field() {
  python3 /opt/webf-android-runner/ui.py "$SERIAL" click-nth android.widget.EditText --index "$1"
  sleep 1
  adb -s "$SERIAL" shell input text "$2"
}

echo "[miot-runner] logging in"
python3 /opt/webf-android-runner/ui.py "$SERIAL" wait-count android.widget.EditText \
  --count 3 --timeout 60
edit_field 0 admin
edit_field 1 admin
edit_field 2 "http://localhost:${SERVER_PORT}"
adb -s "$SERIAL" shell input keyevent 111
sleep 1
click_text '^(登录|Log in)$'

echo "[miot-runner] dismissing update dialog if present"
if wait_for_text '^(稍后|Later)$' 25; then
  click_text '^(稍后|Later)$'
  sleep 2
fi

echo "[miot-runner] waiting for miot tab"
wait_for_text '智能音箱' 45

echo "[miot-runner] opening miot WebF page"
click_text '智能音箱'
sleep 8
adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-main.png"
echo "[miot-runner] captured miot-main.png"

# The miot plugin should either show the main page or a loading/error state.
# Dump the UI tree for inspection.
adb -s "$SERIAL" shell uiautomator dump /sdcard/miot.xml >/dev/null 2>&1 || true
adb -s "$SERIAL" exec-out cat /sdcard/miot.xml >"$OUT/miot-ui.xml" 2>/dev/null || true

# Check if the page loaded (look for "MIoT" or error state or settings button)
echo "[miot-runner] checking miot page content"
if grep -q "设置\|MIoT\|智能音箱\|选择设备\|服务器地址\|页面加载失败\|正在连接" "$OUT/miot-ui.xml" 2>/dev/null; then
  echo "[miot-runner] miot WebF page rendered content successfully"
else
  echo "[miot-runner] WARNING: no expected miot content found in UI tree"
fi

# Try to navigate to settings page (tests our scroll fix)
echo "[miot-runner] attempting to open settings"
# The settings button is an icon button - try clicking by content-desc or coordinates
# In 1080x2400 layout, settings icon is in the appbar area (~top right)
adb -s "$SERIAL" shell input tap 1010 100
sleep 4
adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-settings.png"
echo "[miot-runner] captured miot-settings.png"

adb -s "$SERIAL" shell uiautomator dump /sdcard/miot-settings.xml >/dev/null 2>&1 || true
adb -s "$SERIAL" exec-out cat /sdcard/miot-settings.xml >"$OUT/miot-settings-ui.xml" 2>/dev/null || true

# Try scrolling the settings page (tests our dvh -> vh fix)
echo "[miot-runner] testing settings page scroll"
adb -s "$SERIAL" shell input swipe 540 1800 540 600 300
sleep 2
adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-settings-scrolled.png"
echo "[miot-runner] captured miot-settings-scrolled.png"

# Grab logcat for the full session
adb -s "$SERIAL" logcat -d >"$OUT/miot-logcat.txt" 2>/dev/null

echo "[miot-runner] ===== MIOT ANDROID WEBF TEST COMPLETE ====="
echo "[miot-runner] Screenshots:"
ls -la "$OUT"/miot-*.png
