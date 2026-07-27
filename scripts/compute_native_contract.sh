#!/usr/bin/env bash
#
# compute_native_contract.sh —— 计算安卓热更「原生契约哈希」。
#
# 背景（见 docs/cn/backend_hotupdate.md 的「原生契约哈希闸」）：
#   安卓热更只换 native .so（前端 libapp.so / 后端 libgojni.so），Java/Kotlin
#   永不热更。若热更后的 Dart 调用了旧 APK 原生层不存在的 MethodChannel 方法，
#   会 MissingPluginException。本脚本把「原生契约」压成两个哈希，由 CI 同时烧进
#   APK（asset）与写进热更 manifest；客户端运行时比对，不等即拒绝热更（落整包）。
#
#   dart 哈希（门控前端 libapp.so，标准版 + bundle 都用）：
#     - 所有 com.songloft/* 自定义 MethodChannel 的名字 + 方法名集合（从 Kotlin 源解析）
#     - GeneratedPluginRegistrant 注册的插件类集合（插件增删）
#     - .flutter-plugins-dependencies 里 android 原生插件的 name+version（插件版本带原生改动）
#   go 哈希（门控后端 libgojni.so，仅 bundle）：
#     - sha256(mobile/export_surface.txt)（gomobile 导出面，复用既有冻结文件）
#
# 确定性：所有集合 LC_ALL=C 排序后拼接再 sha256，跨机器/跨构建同源同值。
#
# 残余风险（诚实）：Kotlin 方法集为启发式解析（call.method == "x" 与 when 分支
#   "x" -> 标签）。若方法名动态拼接或走非常规 dispatch，可能解析不到 → 哈希不变
#   → 不兼容补丁漏过。解析规则宁滥勿缺（宁可多纳入误触发整包=安全侧）。插件「同版本
#   号但内部原生实现变化」也不在捕获范围（版本号一致时哈希不变）。这些换来了零手维护。
#
# 用法：
#   compute_native_contract.sh [--export-surface <path>] [--write-asset <path>]
#     --export-surface <path>  gomobile 导出面文件路径（bundle 构建传父仓库
#                              mobile/export_surface.txt；标准版不传 → go 哈希为空）
#     --write-asset <path>     额外把结果 JSON 写到该文件（供 APK 打包为 asset）
#   始终把结果 JSON 打印到 stdout：{"dart":"<sha256>","go":"<sha256>"}
#
# 脚本假定从 songloft-player 仓库根目录运行（或任意目录，内部按脚本位置定位仓库根）。

set -euo pipefail
export LC_ALL=C

EXPORT_SURFACE=""
WRITE_ASSET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --export-surface) EXPORT_SURFACE="${2:-}"; shift 2 ;;
    --write-asset)    WRITE_ASSET="${2:-}"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

# 仓库根 = 脚本所在目录的上一级（scripts/ 的父目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KT_DIR="$REPO_ROOT/android/app/src/main/kotlin/com/songloft/songloft_flutter"
REGISTRANT="$REPO_ROOT/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
PLUGIN_DEPS="$REPO_ROOT/.flutter-plugins-dependencies"

sha256() { sha256sum | cut -d' ' -f1; }

# ---- dart 契约面 ----------------------------------------------------------
dart_surface() {
  # 1) 自定义 channel 名（com.songloft/*）
  echo "## channels"
  if [ -d "$KT_DIR" ]; then
    grep -rhoE '"com\.songloft/[a-z_]+"' "$KT_DIR" 2>/dev/null \
      | tr -d '"' | sort -u
  fi

  # 2) MethodChannel 方法名：call.method == "x" 与 when 分支 "x" -> 标签
  echo "## methods"
  if [ -d "$KT_DIR" ]; then
    {
      grep -rhoE 'call\.method[[:space:]]*==[[:space:]]*"[A-Za-z0-9_]+"' "$KT_DIR" 2>/dev/null \
        | grep -oE '"[A-Za-z0-9_]+"' | tr -d '"'
      grep -rhoE '"[A-Za-z0-9_]+"[[:space:]]*->' "$KT_DIR" 2>/dev/null \
        | grep -oE '"[A-Za-z0-9_]+"' | tr -d '"'
    } | sort -u
  fi

  # 3) 已注册插件类集合（增删插件即变）
  echo "## plugins"
  if [ -f "$REGISTRANT" ]; then
    grep -oE 'add\(new [A-Za-z0-9_.]+\(\)\)' "$REGISTRANT" 2>/dev/null | sort -u
  fi

  # 4) android 原生插件 name+version（插件版本带原生改动即变）
  echo "## plugin-versions"
  if [ -f "$PLUGIN_DEPS" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$PLUGIN_DEPS" <<'PY'
import json, sys, os
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
rows = []
for p in data.get("plugins", {}).get("android", []):
    name = p.get("name", "")
    base = os.path.basename(os.path.normpath(p.get("path", "")))
    ver = base.split("-", 1)[1] if "-" in base else ""
    rows.append("%s\t%s" % (name, ver))
for r in sorted(rows):
    print(r)
PY
  fi
}

DART_HASH="$(dart_surface | sha256)"

# ---- go 契约面（导出面，仅 bundle）----------------------------------------
GO_HASH=""
if [ -n "$EXPORT_SURFACE" ] && [ -f "$EXPORT_SURFACE" ]; then
  GO_HASH="$(sort "$EXPORT_SURFACE" | sha256)"
fi

JSON="{\"dart\":\"${DART_HASH}\",\"go\":\"${GO_HASH}\"}"

if [ -n "$WRITE_ASSET" ]; then
  mkdir -p "$(dirname "$WRITE_ASSET")"
  printf '%s\n' "$JSON" > "$WRITE_ASSET"
fi

printf '%s\n' "$JSON"
