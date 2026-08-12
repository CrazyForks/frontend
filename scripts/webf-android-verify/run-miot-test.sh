#!/usr/bin/env bash
# 针对 miot 插件的 Android WebF 测试（复用已有 APK 和模拟器基础设施）
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT="$HERE/out/miot-test"
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
MIOT_ROOT="$REPO_ROOT/jsplugins-src/songloft-plugin-miot"
SERVER_PORT="${SERVER_PORT:-58394}"
COMPOSE=(docker compose -f "$HERE/compose.yaml")
server_pid=''

[ -e /dev/kvm ] || { echo "[miot-test] /dev/kvm required" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "[miot-test] Docker unavailable" >&2; exit 1; }
[ -f "$HERE/out/songloft-x86_64-release.apk" ] || {
  echo "[miot-test] APK not found. Run run.sh first to build it." >&2; exit 1
}
[ -f "$MIOT_ROOT/dist/miot.jsplugin.zip" ] || {
  echo "[miot-test] miot.jsplugin.zip not found. Run 'npm run build' in $MIOT_ROOT" >&2; exit 1
}

mkdir -p "$OUT"
cp "$MIOT_ROOT/dist/miot.jsplugin.zip" "$OUT/miot.jsplugin.zip"
cp "$HERE/out/songloft-x86_64-release.apk" "$OUT/songloft-x86_64-release.apk"

export ADBKEY=$(<"$HOME/.android/adbkey")
export SERVER_PORT

cleanup() {
  if [ "${KEEP_RUNNING:-}" != 1 ]; then
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null && wait "$server_pid" 2>/dev/null || true
    "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Build and start temp server
RUNTIME_DIR="$OUT/runtime"
mkdir -p "$RUNTIME_DIR/data" "$RUNTIME_DIR/music"

if (echo >/dev/tcp/127.0.0.1/"$SERVER_PORT") 2>/dev/null; then
  echo "[miot-test] port $SERVER_PORT in use" >&2; exit 1
fi

echo "[miot-test] building temp server"
(cd "$REPO_ROOT" && go build -tags 'dev lite' -o "$RUNTIME_DIR/songloft-server" .)
"$RUNTIME_DIR/songloft-server" \
  -port "$SERVER_PORT" \
  -db "$RUNTIME_DIR/data/songloft.db" \
  -music "$RUNTIME_DIR/music" \
  >"$OUT/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null

echo "[miot-test] starting emulator"
"${COMPOSE[@]}" up -d emulator

echo "[miot-test] uploading miot plugin & configuring tabs"
token=$(curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data '{"username":"admin","password":"admin"}' | jq -r '.access_token')

curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugins/upload" \
  -H "Authorization: Bearer ${token}" \
  -F "file=@${OUT}/miot.jsplugin.zip" >"$OUT/plugin-upload.json"

curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/jsplugins/" \
  -H "Authorization: Bearer ${token}" | tee "$OUT/plugins.json" | jq .

plugin_id=$(jq -r '.plugins[] | select(.entry_path == "miot") | .id' "$OUT/plugins.json")
if [ -z "$plugin_id" ] || [ "$plugin_id" = "null" ]; then
  echo "[miot-test] miot plugin not found after upload!" >&2
  cat "$OUT/plugin-upload.json" >&2
  exit 1
fi
echo "[miot-test] miot plugin id: $plugin_id"

curl -fsS -X PUT "http://127.0.0.1:${SERVER_PORT}/api/v1/settings/tab-config" \
  -H "Authorization: Bearer ${token}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -n --argjson id "$plugin_id" \
    '{show_library: true, show_playlists: true,
      plugin_tabs: [{plugin_id: $id, entry_path: "miot", name: "智能音箱"}]}')" \
  >"$OUT/tab-config.json"

echo "[miot-test] running test on emulator"
"${COMPOSE[@]}" run --rm --no-deps \
  --entrypoint bash \
  -e SERVER_PORT="$SERVER_PORT" \
  -e ADBKEY="$ADBKEY" \
  -v "$OUT:/out" \
  -v "$HERE/runner-miot:/opt/runner-miot:ro" \
  test-runner \
  /opt/runner-miot/run-miot-test.sh

echo "[miot-test] done. Screenshots in $OUT/"
