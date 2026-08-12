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
# 找「同意协议」复选框：它是 checkable 节点里最窄的那个（纯方框，desc 为空），
# SSL 那个是整行（很宽、带长 desc），不能选它。
python3 - "$SERIAL" <<'PY'
import sys, subprocess, re, xml.etree.ElementTree as ET
serial = sys.argv[1]
def adb(*a):
    return subprocess.run(["adb","-s",serial,*a],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True).stdout
adb("shell","uiautomator","dump","/sdcard/lg.xml")
raw = subprocess.check_output(["adb","-s",serial,"exec-out","cat","/sdcard/lg.xml"])
try: root = ET.fromstring(raw)
except ET.ParseError: sys.exit(0)
def bounds(n):
    m=re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.attrib.get("bounds",""))
    return tuple(map(int,m.groups())) if m else None
boxes=[]
for n in root.iter("node"):
    if n.attrib.get("checkable")=="true":
        b=bounds(n)
        if b: boxes.append((b, n.attrib.get("content-desc","")))
# 优先：desc 含 agree/terms/privacy；否则取最窄的（纯方框，排除整行）。
target=None
for b,d in boxes:
    dl=d.lower()
    if "agree" in dl or "terms" in dl or "privacy" in dl:
        target=b; break
if target is None and boxes:
    boxes.sort(key=lambda x: (x[0][2]-x[0][0]))  # 按宽度升序，最窄的在前
    target=boxes[0][0]
if target:
    l,t,r,bb=target
    subprocess.run(["adb","-s",serial,"shell","input","tap",str((l+r)//2),str((t+bb)//2)])
PY
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

# ===== Regression verifications (report-only; never abort the run) =====
VRF="$OUT/verify-report.txt"; : > "$VRF"

# #1: FullscreenPlayer must not overlay the main page (v-show → KeepAlive+v-if)
if grep -q '收起播放器\|顺序播放\|延迟停止\|停止播放' "$OUT/miot-ui.xml" 2>/dev/null; then
  echo "FAIL #1: FullscreenPlayer overlay still present on main page" >> "$VRF"
else
  echo "PASS #1: no FullscreenPlayer overlay on main page" >> "$VRF"
fi

# #4: non-player icons must render as glyphs, not as literal ligature text
if grep -qE 'content-desc="[^"]*(speaker_group|music_note|construction|record_voice_over|keyboard_arrow_down|chevron_right|auto_fix_high|restart_alt|expand_more|expand_less|delete_sweep|auto_awesome|bedtime|timer_off|qr_code_2|person_add|audio_file|open_in_new|swap_horiz|format_list_numbered|looks_one|queue_music|my_location|favorite_border|repeat_one|volume_up|volume_down|volume_mute|volume_off|skip_previous|skip_next|play_arrow|equalizer|alarm_on|terminal|database|science|campaign|lyrics|memory|mic|favorite|repeat|shuffle|volume_off|search|settings|refresh|schedule|dns|warning|arrow_back|artist|label)[^"]*"' "$OUT/miot-ui.xml" 2>/dev/null; then
  echo "FAIL #4: an icon name leaked as literal text in content-desc" >> "$VRF"
  grep -oE 'content-desc="[^"]*(speaker_group|music_note|construction|record_voice_over|keyboard_arrow_down|chevron_right|expand_more|auto_fix_high|restart_alt|delete_sweep|auto_awesome|bedtime|timer_off|terminal|database|science|campaign|lyrics|memory|mic|search|settings|refresh|schedule|dns|warning|swap_horiz|looks_one|queue_music|equalizer|alarm_on|qr_code_2|person_add|audio_file|open_in_new|format_list_numbered|my_location|skip_previous|skip_next|play_arrow|volume_up|volume_down|volume_mute|volume_off|repeat_one|favorite_border|chevron_right|keyboard_arrow_down|expand_less|artist|label|arrow_back|favorite|repeat|shuffle)[^"]*"' "$OUT/miot-ui.xml" >> "$VRF" 2>/dev/null || true
else
  echo "PASS #4: no icon name leaked as literal text on main page" >> "$VRF"
fi

# #2: host back button must close the device picker instead of exiting
echo "[miot-runner] verify #2: back closes device picker"
if click_text '选择设备'; then
  sleep 2
  adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-picker.png" 2>/dev/null || true
  adb -s "$SERIAL" shell uiautomator dump /sdcard/pk.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /sdcard/pk.xml >"$OUT/miot-picker-ui.xml" 2>/dev/null || true
  if grep -q '暂无可选设备\|取消' "$OUT/miot-picker-ui.xml" 2>/dev/null; then
    adb -s "$SERIAL" shell input keyevent 4
    sleep 2
    adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-picker-after-back.png" 2>/dev/null || true
    adb -s "$SERIAL" shell uiautomator dump /sdcard/pk2.xml >/dev/null 2>&1 || true
    adb -s "$SERIAL" exec-out cat /sdcard/pk2.xml >"$OUT/miot-picker-after-back.xml" 2>/dev/null || true
    # PASS only if we are still on the miot main page (选择歌单 present) AND the dialog is gone (取消 absent)
    if grep -q '选择歌单' "$OUT/miot-picker-after-back.xml" 2>/dev/null && ! grep -q '取消' "$OUT/miot-picker-after-back.xml" 2>/dev/null; then
      echo "PASS #2: back closed the device picker (stayed on miot page)" >> "$VRF"
    else
      echo "FAIL #2: back did not close picker (选择歌单=$([ -f "$OUT/miot-picker-after-back.xml" ] && grep -q 选择歌单 "$OUT/miot-picker-after-back.xml" && echo yes || echo no))" >> "$VRF"
    fi
  else
    echo "SKIP #2: device picker dialog did not open" >> "$VRF"
  fi
else
  echo "SKIP #2: 选择设备 button not found" >> "$VRF"
fi

# #3: SlSelect dropdown must close on outside click
echo "[miot-runner] verify #3: select closes on outside click"
if click_text '选择歌单'; then
  sleep 2
  adb -s "$SERIAL" shell uiautomator dump /sdcard/s1.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /sdcard/s1.xml >"$OUT/miot-select-open.xml" 2>/dev/null || true
  open_count=$(grep -o '选择歌单' "$OUT/miot-select-open.xml" 2>/dev/null | wc -l)
  adb -s "$SERIAL" shell input tap 540 250   # empty area, not on the panel/trigger
  sleep 2
  adb -s "$SERIAL" shell uiautomator dump /sdcard/s2.xml >/dev/null 2>&1 || true
  adb -s "$SERIAL" exec-out cat /sdcard/s2.xml >"$OUT/miot-select-closed.xml" 2>/dev/null || true
  closed_count=$(grep -o '选择歌单' "$OUT/miot-select-closed.xml" 2>/dev/null | wc -l)
  echo "  select open occurrences=$open_count closed occurrences=$closed_count" >> "$VRF"
  if [ "${open_count:-0}" -gt "${closed_count:-0}" ] 2>/dev/null; then
    echo "PASS #3: select dropdown closed on outside tap" >> "$VRF"
  else
    echo "FAIL #3: select did not close (open=$open_count closed=$closed_count)" >> "$VRF"
  fi
else
  echo "SKIP #3: 选择歌单 trigger not found" >> "$VRF"
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

# #4 on settings page: nav items must not leak icon ligature text
if grep -qE 'content-desc="[^"]*(speaker_group|music_note|construction|record_voice_over|schedule|swap_horiz|chevron_right|auto_fix_high|restart_alt|delete_sweep|auto_awesome|bedtime|timer_off|terminal|database|science|campaign|lyrics|memory|mic|dns|search|settings|refresh|warning|looks_one|queue_music|equalizer|alarm_on|qr_code_2|person_add|audio_file|open_in_new|format_list_numbered|my_location|expand_more|expand_less|keyboard_arrow_down|arrow_back|artist|label|favorite|repeat|shuffle|volume_up|volume_down|volume_mute|volume_off|skip_previous|skip_next|play_arrow|repeat_one|favorite_border)[^"]*"' "$OUT/miot-settings-ui.xml" 2>/dev/null; then
  echo "FAIL #4 (settings): icon name leaked as literal text" >> "$VRF"
  grep -oE 'content-desc="[^"]*(speaker_group|music_note|construction|record_voice_over|schedule|swap_horiz|chevron_right|expand_more|expand_less|keyboard_arrow_down|dns|search|settings|refresh|terminal|database|science|campaign|lyrics|memory|mic|alarm_on|queue_music|equalizer|looks_one)[^"]*"' "$OUT/miot-settings-ui.xml" >> "$VRF" 2>/dev/null || true
else
  echo "PASS #4 (settings): no icon name leaked as literal text" >> "$VRF"
fi

# Try scrolling the settings page (tests our dvh -> vh fix)
echo "[miot-runner] testing settings page scroll"
adb -s "$SERIAL" shell input swipe 540 1800 540 600 300
sleep 2
adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-settings-scrolled.png"
echo "[miot-runner] captured miot-settings-scrolled.png"

# Settings back test: requestBack path must bring us back to the miot main page, not exit
echo "[miot-runner] verify settings back returns to miot main page"
adb -s "$SERIAL" shell input keyevent 4
sleep 2
adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-settings-after-back.png" 2>/dev/null || true
adb -s "$SERIAL" shell uiautomator dump /sdcard/sb.xml >/dev/null 2>&1 || true
adb -s "$SERIAL" exec-out cat /sdcard/sb.xml >"$OUT/miot-settings-after-back.xml" 2>/dev/null || true
if grep -q '选择歌单' "$OUT/miot-settings-after-back.xml" 2>/dev/null; then
  echo "PASS settings-back: returned to miot main page (requestBack path works)" >> "$VRF"
else
  echo "FAIL settings-back: did not return to miot main page (requestBack path broken?)" >> "$VRF"
fi

# Re-enter the miot tab + dump the host-side [miot-back] debug traces from logcat
echo "[miot-runner] re-entering miot tab"
if click_text '智能音箱'; then
  sleep 6
  adb -s "$SERIAL" exec-out screencap -p >"$OUT/miot-reentry.png" 2>/dev/null || true
fi
echo "[miot-runner] host back traces ([miot-back]):" >> "$VRF"
adb -s "$SERIAL" logcat -d 2>/dev/null | grep -E "miot-back" | head -20 >> "$VRF" || true

# Grab logcat for the full session
adb -s "$SERIAL" logcat -d >"$OUT/miot-logcat.txt" 2>/dev/null || true

echo "[miot-runner] ===== MIOT ANDROID WEBF TEST COMPLETE ====="
echo "[miot-runner] Verify report:"
cat "$VRF" 2>/dev/null || true
echo "[miot-runner] Screenshots:"
ls -la "$OUT"/miot-*.png 2>/dev/null || true
