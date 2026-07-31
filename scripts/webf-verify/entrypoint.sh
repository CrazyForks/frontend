#!/usr/bin/env bash
# WebF 验证容器入口（songloft-org/songloft#341）
#
# 流程：组合 docroot → 起静态服务 → 起 Xvfb → 跑 WebF 探针 app → 抓屏 → 落 /out
#
# 期望的挂载：
#   /repo   主仓库根目录（只读即可，用于取真实的 internal/jsplugin/assets）
#   /out    截图与日志输出目录
set -euo pipefail

REPO=${REPO:-/repo}
OUT=${OUT:-/out}
PORT=${PORT:-58991}
DOCROOT=/tmp/docroot
ASSETS="$REPO/internal/jsplugin/assets"
# 抓屏前等渲染稳定的秒数。WebF 首帧 + woff2 解码 + Xvfb 软渲染都要时间，
# 给太短会拍到空白帧而误判成「闸失败」。
SETTLE=${SETTLE:-12}

log() { echo "[webf-verify] $*"; }

mkdir -p "$OUT"

# ── 1. 组合 docroot ──────────────────────────────────────────────
# 不能把 probe.html 放进 $ASSETS：那个目录被 //go:embed assets/* 嵌进 Go 二进制。
[ -f "$ASSETS/common.css" ] || { echo "找不到 $ASSETS/common.css，检查 /repo 挂载" >&2; exit 1; }
rm -rf "$DOCROOT" && mkdir -p "$DOCROOT"
cp -r "$ASSETS/." "$DOCROOT/"
cp /opt/probe.html "$DOCROOT/probe.html"
cp /opt/probe-after.css "$DOCROOT/probe-after.css"

# ── 2. 从真实 woff2 的 cmap 查图标码点（不猜）────────────────────
resolve_codepoints() {
  python3 - "$DOCROOT/fonts/material-symbols-outlined.woff2" "$DOCROOT/probe.html" <<'PY'
import sys
from fontTools.ttLib import TTFont

font_path, html_path = sys.argv[1], sys.argv[2]
wanted = ['download', 'settings', 'play_arrow']

# Material Symbols 的连字：字形名就是图标名，码点在 Private Use Area。
# 通过 cmap 反查「字形名 -> 码点」，拿不到就留标记，让截图里一眼看出 N/A。
font = TTFont(font_path)
name_to_cp = {}
for table in font['cmap'].tables:
    for cp, glyph_name in table.cmap.items():
        name_to_cp.setdefault(glyph_name, cp)

html = open(html_path, encoding='utf-8').read()
for name in wanted:
    token = '__CODEPOINT_%s__' % name.upper()
    cp = name_to_cp.get(name)
    if cp is None:
        print('cmap-miss %s' % name, file=sys.stderr)
        html = html.replace(token, 'N/A')
    else:
        print('%s -> U+%04X' % (name, cp), file=sys.stderr)
        html = html.replace(token, '&#x%X;' % cp)
open(html_path, 'w', encoding='utf-8').write(html)
PY
}
log '解析图标码点…'
resolve_codepoints 2>&1 | tee "$OUT/codepoints.txt" || log '码点解析失败（不阻塞，CODEPOINT 行会显示 N/A）'

# ── 2b. FONT_FIX：在 docroot 里模拟「woff2 旁边补一份 ttf」的修复 ──────
# WebF 的 supportedFonts 白名单只有 ttc/ttf/otf/data（css/font_face.dart:20），
# 且 format 是从 **URL 扩展名** 推断的（:154 `tmpSrc.split('.').last`），
# 完全无视 CSS 里的 format() 声明；挑不到受支持的源就静默 return（:163），
# 既不发请求也不打日志。所以纯 woff2 的 @font-face 在 WebF 下必然无声失效。
# 这里生成 ttf 并把 src 改写成「woff2 在前、ttf 在后」：浏览器按 format() 选 woff2，
# WebF 跳过 woff2 后按扩展名选中 ttf。不改仓库，只改容器内的 docroot 副本。
FONT_PRELOAD_DIR=''
if [ "${FONT_FIX:-0}" = '3' ]; then
  # FONT_FIX=3：只生成 ttf，**不改 common.css**（页面里仍是注定失效的 woff2 @font-face），
  # 改由 Flutter 侧 FontLoader 预注册同名 family。验证「绕开 @font-face」这条补救路径。
  log 'FONT_FIX=3：生成 ttf，common.css 不动，改由 Flutter 侧预注册字体'
  python3 - "$DOCROOT" <<'PY'
import glob, os, sys
from fontTools.ttLib import TTFont
docroot = sys.argv[1]
for woff2 in glob.glob(os.path.join(docroot, 'fonts', '*.woff2')):
    ttf = woff2[:-len('.woff2')] + '.ttf'
    font = TTFont(woff2)
    font.flavor = None
    font.save(ttf)
    print('%s -> %s (%d bytes)' % (os.path.basename(woff2), os.path.basename(ttf), os.path.getsize(ttf)))
PY
  FONT_PRELOAD_DIR="$DOCROOT/fonts"
fi

if [ "${FONT_FIX:-0}" = '2' ]; then
  # FONT_FIX=2：把 ttf 以 base64 data: URL 内联进 CSS，走 font_face.dart 的
  # FontSource.content 分支（'data' 在 supportedFonts 白名单里），完全绕开网络路径。
  # 用来区分「HTTP 取字体这条路坏了」还是「字体压根没应用到渲染」。
  log 'FONT_FIX=2：woff2 → ttf → base64 data: URL 内联'
  python3 - "$DOCROOT" <<'PY'
import base64, glob, os, re, sys
from fontTools.ttLib import TTFont

docroot = sys.argv[1]
inlined = {}
for woff2 in glob.glob(os.path.join(docroot, 'fonts', '*.woff2')):
    ttf = woff2[:-len('.woff2')] + '.ttf'
    font = TTFont(woff2)
    font.flavor = None          # 见 FONT_FIX=1 的说明
    font.save(ttf)
    stem = os.path.basename(woff2)[:-len('.woff2')]
    with open(ttf, 'rb') as fh:
        inlined[stem] = base64.b64encode(fh.read()).decode('ascii')
    print('%s inlined as %d base64 chars' % (stem, len(inlined[stem])))

css_path = os.path.join(docroot, 'common.css')
css = open(css_path, encoding='utf-8').read()

def repl(m):
    stem = m.group(1)
    b64 = inlined.get(stem)
    if not b64:
        return m.group(0)
    return "src: url('data:font/ttf;base64,%s') format('truetype');" % b64

css, n = re.subn(
    r"src:\s*url\('\./fonts/([^']+)\.woff2'\)\s*format\('woff2'\);", repl, css)
open(css_path, 'w', encoding='utf-8').write(css)
print('rewrote %d @font-face src declarations' % n)
PY
fi

if [ "${FONT_FIX:-0}" = '1' ]; then
  log 'FONT_FIX=1：woff2 → ttf 并改写 common.css 为双 src'
  python3 - "$DOCROOT" <<'PY'
import glob, os, re, sys
from fontTools.ttLib import TTFont

docroot = sys.argv[1]
for woff2 in glob.glob(os.path.join(docroot, 'fonts', '*.woff2')):
    ttf = woff2[:-len('.woff2')] + '.ttf'
    font = TTFont(woff2)
    # 必须显式清掉 flavor：TTFont.save() 默认沿用来源的 flavor，
    # 直接 save 出来的 .ttf 其实还是 woff2 字节（体积几乎不变是特征），
    # Skia 解不了，表现与完全没加载一样（豆腐块）。
    font.flavor = None
    font.save(ttf)
    print('%s -> %s (%d -> %d bytes)' % (
        os.path.basename(woff2), os.path.basename(ttf),
        os.path.getsize(woff2), os.path.getsize(ttf)))

css_path = os.path.join(docroot, 'common.css')
css = open(css_path, encoding='utf-8').read()
# 只改 src 行，保持其余声明不动
css, n = re.subn(
    r"src:\s*url\('(\./fonts/[^']+)\.woff2'\)\s*format\('woff2'\);",
    r"src: url('\1.woff2') format('woff2'),\n       url('\1.ttf') format('truetype');",
    css)
open(css_path, 'w', encoding='utf-8').write(css)
print('rewrote %d @font-face src declarations' % n)
PY
fi

# ── 3. 静态服务 ──────────────────────────────────────────────────
log "起静态服务 :$PORT （docroot=$DOCROOT）"
(cd "$DOCROOT" && python3 -m http.server "$PORT" --bind 127.0.0.1) >"$OUT/http.log" 2>&1 &
sleep 1

# ── 4. Xvfb ──────────────────────────────────────────────────────
export DISPLAY=:99
# Xvfb 下没有 GPU；Flutter Linux 的 GL 后端必须走 Mesa 软渲染，否则起不来。
export LIBGL_ALWAYS_SOFTWARE=1
export GDK_BACKEND=x11
log '起 Xvfb :99'
Xvfb :99 -screen 0 1280x900x24 -nolisten tcp >"$OUT/xvfb.log" 2>&1 &
for _ in $(seq 1 30); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 0.5; done
xdpyinfo -display :99 >/dev/null 2>&1 || { echo 'Xvfb 起不来' >&2; cat "$OUT/xvfb.log" >&2; exit 1; }

# ── 5. 跑探针 ────────────────────────────────────────────────────
PROBE_URL=${PROBE_URL:-http://127.0.0.1:$PORT/probe.html}
log "构建探针（增量），URL=$PROBE_URL"
cd /opt/webf_probe
# 刻意用 build + 直接执行产物，而不是 flutter run：run 需要 tty 交互、
# 失败信号混在日志里不好分辨；build 能把「构建失败」与「运行期渲染失败」
# 干净地分成两段。WebF 的 CMakeLists 在 build 阶段拷 libc++/libunwind。
if ! flutter build linux --release \
      --dart-define=PROBE_URL="$PROBE_URL" \
      --dart-define=FONT_PRELOAD_DIR="$FONT_PRELOAD_DIR" \
      --dart-define=DIAGNOSE="${DIAGNOSE:-}" \
      >"$OUT/build.log" 2>&1; then
  echo '构建失败，日志末尾：' >&2
  tail -60 "$OUT/build.log" >&2
  exit 1
fi

BUNDLE=/opt/webf_probe/build/linux/x64/release/bundle
log '运行探针'
"$BUNDLE/webf_probe" >"$OUT/flutter.log" 2>&1 &
FLUTTER_PID=$!

log "等 ${SETTLE}s 让首帧与字体渲染稳定…"
sleep "$SETTLE"

# ── 6. 抓屏 ──────────────────────────────────────────────────────
if ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
  log '探针进程已退出，很可能是构建/加载失败，见 flutter.log 末尾：'
  tail -40 "$OUT/flutter.log" >&2 || true
fi
import -display :99 -window root "$OUT/probe.png" 2>>"$OUT/xvfb.log" || {
  echo '抓屏失败' >&2; tail -40 "$OUT/flutter.log" >&2; exit 1;
}
log "截图已落 $OUT/probe.png"

# 顺带记录一份环境事实，方便回看
{
  echo "glibc: $(ldd --version | head -1)"
  echo "flutter: $(flutter --version | head -1)"
  echo "webf: $(grep -m1 '  webf:' /opt/webf_probe/pubspec.yaml || true)"
  echo "resolved webf: $(grep -A1 '^  webf:' /opt/webf_probe/pubspec.lock | tail -1 || true)"
} >"$OUT/env.txt" 2>&1

kill "$FLUTTER_PID" 2>/dev/null || true
wait "$FLUTTER_PID" 2>/dev/null || true
log '完成'
