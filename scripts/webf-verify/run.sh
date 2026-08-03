#!/usr/bin/env bash
# WebF 验证容器：一条命令跑通「构建 → 渲染 → 抓屏」（songloft-org/songloft#341）
#
#   ./scripts/webf-verify/run.sh                 # 跑图标连字生死闸
#   ./scripts/webf-verify/run.sh --build         # 强制重建镜像
#   PROBE_URL=http://... ./scripts/webf-verify/run.sh   # 换成渲染真实插件页
#   DRAG_PROBE=1 ./scripts/webf-verify/run.sh     # 额外对 14~16 组的滑块合成拖动
#   DIAGNOSE_JS=./my-checks.js ./scripts/webf-verify/run.sh  # 换掉内置诊断脚本
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

# DIAGNOSE / DRAG_PROBE 最终落到 Dart 的 bool.fromEnvironment，它**只认字面 "true"**，
# 传 1 会被静默当成 false（诊断脚本不注入、日志里什么都没有）。这里归一化。
case "${DIAGNOSE:-}" in
  1|yes|on|true) DIAGNOSE=true ;;
  *) DIAGNOSE='' ;;
esac
case "${DRAG_PROBE:-}" in
  1|yes|on|true) DRAG_PROBE=true ;;
  *) DRAG_PROBE='' ;;
esac

# DIAGNOSE_JS=<宿主上的 .js 文件> 用自定义诊断脚本替换探针内置的那份。
# 内置脚本是通用的（主题 / CSS 变量 / 宿主桥在不在），但**每个插件页的判据都不同**
# （downloader 要量 6 列 x 坐标与 sticky 表头，miot 要量竖向滑块几何与安全区求值），
# 而真实插件页改不了 —— 判据只能靠外部注入的脚本在页面自身上下文里读出来。
#
# 走 base64：值要穿过 shell → docker -e → flutter build 三层，而脚本里必然有
# 引号 / `$` / 换行，base64 是唯一不用逐层转义的形态。
# 指定 DIAGNOSE_JS 时自动打开 DIAGNOSE（否则脚本传进去了也不会被注入）。
DIAGNOSE_JS_B64=''
if [ -n "${DIAGNOSE_JS:-}" ]; then
  [ -f "$DIAGNOSE_JS" ] || { echo "[run] DIAGNOSE_JS 文件不存在：$DIAGNOSE_JS" >&2; exit 1; }
  DIAGNOSE_JS_B64=$(base64 -w0 < "$DIAGNOSE_JS")
  DIAGNOSE=true
  echo "[run] 自定义诊断脚本：$DIAGNOSE_JS（$(wc -c <"$DIAGNOSE_JS") 字节）"
fi

mkdir -p "$OUT"
echo "[run] 主仓库根：$REPO_ROOT"
echo "[run] 输出目录：$OUT"

# 默认 bridge 就够：静态服务与探针都在容器内 127.0.0.1。
# 但要渲染**真实插件页**（PROBE_URL 指向宿主上跑的 Go 后端）时必须置
# HOST_NETWORK=1，否则容器里的 127.0.0.1 是它自己 —— 与仓库里那套
# 「无头 Chrome 验前端」同样的理由。
docker run --rm \
  ${HOST_NETWORK:+--network host} \
  -v "$REPO_ROOT:/repo:ro" \
  -v "$OUT:/out" \
  ${PROBE_URL:+-e PROBE_URL="$PROBE_URL"} \
  ${SETTLE:+-e SETTLE="$SETTLE"} \
  ${FONT_FIX:+-e FONT_FIX="$FONT_FIX"} \
  ${DIAGNOSE:+-e DIAGNOSE="$DIAGNOSE"} \
  ${DIAGNOSE_JS_B64:+-e DIAGNOSE_JS_B64="$DIAGNOSE_JS_B64"} \
  ${DRAG_PROBE:+-e DRAG_PROBE="$DRAG_PROBE"} \
  "$IMAGE"

echo
echo "[run] 完成。看截图：$OUT/probe.png"
