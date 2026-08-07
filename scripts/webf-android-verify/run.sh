#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT="$HERE/out"
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
PLUGIN_ROOT="$REPO_ROOT/jsplugins-src/songloft-plugin-downloader"
SERVER_PORT="${SERVER_PORT:-58192}"
RUNTIME_DIR="$OUT/runtime-$(date '+%Y%m%d-%H%M%S')"
COMPOSE=(docker compose -f "$HERE/compose.yaml")
server_pid=''

if [ ! -e /dev/kvm ]; then
  echo "[run] /dev/kvm is required for the Android Emulator container" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "[run] Docker daemon is unavailable" >&2
  exit 1
fi

mkdir -p "$OUT"
if [ ! -f "$HOME/.android/adbkey" ]; then
  adb_bin=${ADB:-$(command -v adb || true)}
  if [ -z "$adb_bin" ] && [ -n "${ANDROID_HOME:-}" ]; then
    adb_bin="$ANDROID_HOME/platform-tools/adb"
  fi
  if [ -z "$adb_bin" ] || [ ! -x "$adb_bin" ]; then
    echo "[run] adb is required once to generate ~/.android/adbkey" >&2
    exit 1
  fi
  mkdir -p "$HOME/.android"
  "$adb_bin" keygen "$HOME/.android/adbkey" >/dev/null
fi
export ADBKEY=$(<"$HOME/.android/adbkey")
export SERVER_PORT
# BuildKit needs the host shell proxy as well as the Docker daemon proxy when
# pulling Flutter and Android SDK layers through a local proxy.
if [ -z "${HTTP_PROXY:-}" ] && [ -z "${HTTPS_PROXY:-}" ] \
    && (echo >/dev/tcp/127.0.0.1/8080) 2>/dev/null; then
  export HTTP_PROXY=http://127.0.0.1:8080
  export HTTPS_PROXY=http://127.0.0.1:8080
fi
# The host's custom docker-container builder does not inherit the Docker daemon
# proxy. The default docker driver does, so image metadata and SDK downloads use
# the same working network path as `docker pull`.
export BUILDX_BUILDER="${BUILDX_BUILDER:-default}"

cleanup() {
  if [ "${KEEP_RUNNING:-}" != 1 ]; then
    if [ -n "$server_pid" ]; then
      kill "$server_pid" 2>/dev/null || true
      wait "$server_pid" 2>/dev/null || true
    fi
    "${COMPOSE[@]}" down --remove-orphans >/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$RUNTIME_DIR/data" "$RUNTIME_DIR/music"

echo "[run] building downloader plugin on the host"
pnpm --dir "$PLUGIN_ROOT" build
cp "$PLUGIN_ROOT/dist/downloader.jsplugin.zip" "$OUT/downloader.jsplugin.zip"

echo "[run] building and starting temporary host server on port $SERVER_PORT"
(
  cd "$REPO_ROOT"
  go build -tags 'dev lite' -o "$RUNTIME_DIR/songloft-server" .
)
"$RUNTIME_DIR/songloft-server" \
  -port "$SERVER_PORT" \
  -db "$RUNTIME_DIR/data/songloft.db" \
  -music "$RUNTIME_DIR/music" \
  >"$OUT/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "[run] host server exited during startup; see $OUT/server.log" >&2
    exit 1
  fi
  sleep 1
done
curl -fsS "http://127.0.0.1:${SERVER_PORT}/api/v1/health" >/dev/null

echo "[run] building verifier images"
"${COMPOSE[@]}" build apk-builder test-runner

echo "[run] starting Android emulator"
"${COMPOSE[@]}" up -d emulator

echo "[run] building APK"
"${COMPOSE[@]}" run --rm apk-builder

echo "[run] running Android screenshot test"
"${COMPOSE[@]}" run --rm --no-deps test-runner

echo "[run] artifacts: $OUT"
