#!/usr/bin/env bash
# WebF 验证容器：一条命令跑通「构建 → 渲染 → 抓屏」（songloft-org/songloft#341）
#
#   ./scripts/webf-verify/run.sh                 # 跑图标连字生死闸
#   ./scripts/webf-verify/run.sh --build         # 强制重建镜像
#   PROBE_URL=http://... ./scripts/webf-verify/run.sh   # 换成渲染真实插件页
#
# 产出（宿主）：songloft-player/scripts/webf-verify/out/
#   probe.png       截图（判据见 probe.html 顶部注释）
#   build.log       Flutter/CMake 构建日志
#   flutter.log     探针运行期 stdout/stderr
#   codepoints.txt  从真实 woff2 cmap 查到的图标码点
#   env.txt         glibc / flutter / webf 实际版本
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# scripts/webf-verify → songloft-player → 主仓库根
REPO_ROOT=$(cd "$HERE/../.." && cd .. && pwd)
IMAGE=songloft-webf-verify
OUT="$HERE/out"

if [ "${1:-}" = '--build' ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "[run] 构建镜像 $IMAGE（首次约 10-20 分钟：Flutter SDK + webf 28.5 MB 包 + CMake）"
  docker build -t "$IMAGE" "$HERE"
fi

mkdir -p "$OUT"
echo "[run] 主仓库根：$REPO_ROOT"
echo "[run] 输出目录：$OUT"

# --network 用默认 bridge 就够：静态服务与探针都在容器内 127.0.0.1，
# 不需要访问宿主（与仓库里那套「无头 Chrome 验前端」不同，那个要 --network host）
docker run --rm \
  -v "$REPO_ROOT:/repo:ro" \
  -v "$OUT:/out" \
  ${PROBE_URL:+-e PROBE_URL="$PROBE_URL"} \
  ${SETTLE:+-e SETTLE="$SETTLE"} \
  ${FONT_FIX:+-e FONT_FIX="$FONT_FIX"} \
  "$IMAGE"

echo
echo "[run] 完成。看截图：$OUT/probe.png"
