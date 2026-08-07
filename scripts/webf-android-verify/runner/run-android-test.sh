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
# The settings page is ~698 CSS px tall; on the stock 1080x1920 screen the viewport
# is only 562 CSS px, so the second switch row sits permanently below the fold and
# the assertion can only ever see one switch. A taller logical screen brings the
# whole page into view. It cannot be solved by scrolling: WebF's CSS overflow
# scrollers do not receive synthetic touch events at all (only programmatic
# scrollTop moves them), so `input swipe` scrolls the Flutter list behind instead.
adb -s "$SERIAL" shell wm size 1080x2400
echo "[runner] forwarding server ${SERVER_HOST}:${SERVER_PORT}"
socat "TCP-LISTEN:${SERVER_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${SERVER_HOST}:${SERVER_PORT}" >/tmp/server-forward.log 2>&1 &
forward_pid=$!

# Every step below drives the UI blind, so a failure is unreadable without the
# screen state at the moment it happened.
capture_failure() {
  status=$?
  [ "$status" -eq 0 ] && return 0
  echo "[runner] step failed (exit $status); capturing device state" >&2
  adb -s "$SERIAL" exec-out screencap -p >"$OUT/failure.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/failure.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /sdcard/failure.xml >"$OUT/failure-uiautomator.xml" 2>/dev/null || true
  adb -s "$SERIAL" logcat -d >"$OUT/failure-logcat.txt" 2>/dev/null || true
  return "$status"
}
restore_display() {
  # Leave the device as we found it, so a kept-running emulator stays reusable.
  adb -s "$SERIAL" shell wm size reset >/dev/null 2>&1 || true
}
trap 'capture_failure; restore_display; kill "$forward_pid" 2>/dev/null || true' EXIT
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

# tab_config.plugin_tabs defaults to empty, so a freshly installed plugin has no
# entry anywhere in the shell. It is server-side config, so publishing it over
# the API is far steadier than driving the tab-config screen.
plugin_id=$(jq -r '.plugins[] | select(.entry_path == "downloader") | .id' "$OUT/plugins.json")
curl -fsS -X PUT "http://${SERVER_HOST}:${SERVER_PORT}/api/v1/settings/tab-config" \
  -H "Authorization: Bearer ${bootstrap_token}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -n --argjson id "$plugin_id" \
    '{show_library: true, show_playlists: true,
      plugin_tabs: [{plugin_id: $id, entry_path: "downloader", name: "歌曲下载"}]}')" \
  >"$OUT/tab-config.json"

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

# Flutter exposes an *empty* TextField as a bare EditText node carrying no text
# and no content-desc — the hint ("Username", "API address") is painted, not
# published to the semantics tree. So the login fields cannot be matched by
# label in any locale and are addressed by their screen order instead.
edit_field() {
  python3 /opt/webf-android-runner/ui.py "$SERIAL" click-nth android.widget.EditText \
    --index "$1"
  # Flutter needs a moment to move focus before it accepts synthetic key events.
  sleep 1
  adb -s "$SERIAL" shell input text "$2"
}

echo "[runner] logging in"
python3 /opt/webf-android-runner/ui.py "$SERIAL" wait-count android.widget.EditText \
  --count 3 --timeout 60
edit_field 0 admin
edit_field 1 admin
edit_field 2 "http://localhost:${SERVER_PORT}"
# The IME covers the login button, and BACK would pop the route instead.
adb -s "$SERIAL" shell input keyevent 111
sleep 1
click_text '^(登录|Log in)$'

# The APK carries a synthetic FRONTEND_VERSION, so the startup patch check
# always resolves the real latest release as newer and pops a modal that covers
# the whole shell. It fires a few seconds after authentication, so it has to be
# cleared before anything else can be driven.
echo "[runner] dismissing the startup update dialog if it appears"
if wait_for_text '^(稍后|Later)$' 25; then
  click_text '^(稍后|Later)$'
  sleep 2
fi

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
# The dump is the assertion's reference frame, not just an artefact: it supplies the
# row content edge the switches must reach. It has to describe the same screen state
# as the screenshot, so keep the two captures adjacent.
adb -s "$SERIAL" shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb -s "$SERIAL" exec-out cat /sdcard/window.xml >"$OUT/uiautomator.xml"

python3 /usr/local/bin/assert-switch-alignment.py \
  "$OUT/settings-light.png" "$OUT/uiautomator.xml" >"$OUT/assertion.json"

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
