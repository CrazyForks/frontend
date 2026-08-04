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
PROBE_HOME=${PROBE_HOME:-/opt/webf_probe}
# 产品的自定义元素目录。刻意直接编译**产品那一份**，不在探针里抄副本：
# 探针与产品是两个 Dart package，跨 package 相对 import 不可行，所以只能拷。
ELEMENTS_SRC="$REPO/songloft-player/lib/features/home/presentation/render/elements"
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

# ── 1b. 把产品的自定义元素源码拷进探针 lib/ ───────────────────────
# 必须 fail-fast：拷不到就不能悄悄跑一个「没有自定义元素」的探针 ——
# 那样截图里 ring 全空，看起来跟「元素实现坏了」一模一样，会误判。
[ -d "$ELEMENTS_SRC" ] || {
  echo "找不到 $ELEMENTS_SRC，检查 /repo 挂载与子模块 checkout" >&2; exit 1; }
rm -rf "$PROBE_HOME/lib/elements"
cp -r "$ELEMENTS_SRC" "$PROBE_HOME/lib/elements"
log "已拷入产品自定义元素（编译的是产品实现，非副本）："
(cd "$PROBE_HOME/lib/elements" && sha1sum ./*.dart) | tee "$OUT/elements.sha1"

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
      --dart-define=DIAGNOSE_JS_B64="${DIAGNOSE_JS_B64:-}" \
      --dart-define=DRAG_PROBE="${DRAG_PROBE:-}" \
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

# ── 6b. 绘制层判据：在截图上逐点取色 ─────────────────────────────
# 为什么需要这一步：探针页里那些 `imgSet=ok` / `bgRect=16x16` / `naturalWidth`
# **只证明元素盒子有尺寸、赋值没抛异常**，不证明像素真被画出来了。实测一个
# 硬编码 1×1 红点 PNG 三项全正常、截图里方块却是灰的 —— 判据从缝里漏过去了。
# 唯一可信的证据在帧缓冲里，所以只能抓屏取色。
#
# 坐标与期望颜色由**页面自己**经 console 报上来（`[probe] step6-px img=x,y,HEX …`），
# 不写死在这里：版面一改死坐标就静默失效，表现是「PASS 变 FAIL」，看起来像 WebF 坏了。
# 渲染真实插件页时这一行压根不存在 → 整步跳过（不是失败）。
# 主判据是**存在性**（期望颜色在整张截图里出现了多少像素），不是点取色 ——
# 点取色对版面漂移敏感：页面报坐标的那一刻（≈3.8s）与抓屏那一刻（SETTLE=12s）
# 之间，上面几组的异步读数还在往 DOM 里写文字，把下面的行整体推下去。
# 第一版就栽在这里：三个方块**都画出来了**，但点取色全 FAIL（y 差 96px），
# 差一点被误判成「WebF 画不出 data: URL 图」。
# 三个方块的颜色在整页里唯一（刻意选的），所以「出现了 ≈196 个该色像素」
# 就是充分证据；点取色降级为附注，用来发现坐标漂移。
sample_pixels() {
  local line
  # 同一条 console 消息在 flutter.log 里会出现两次（一次裸文本、一次带引号），
  # 所以先 tr -d '"' 再取最后一条 —— 否则 want 会带上一个尾引号。
  line=$(grep -o 'step6-px .*' "$OUT/flutter.log" | tr -d '"' | tail -1 || true)
  if [ -z "$line" ]; then
    echo 'no step6-px line in flutter.log（渲染的不是探针页，或第 18 组没跑完）' \
      >"$OUT/pixels.txt"
    log '跳过取色判据（flutter.log 里没有 step6-px）'
    return 0
  fi
  local st=0
  python3 - "$OUT/probe.png" "$OUT/pixels.txt" "${line#step6-px }" <<'PY' || st=$?
import subprocess, sys

png, report, spec = sys.argv[1], sys.argv[2], sys.argv[3]


def im(args):
    return subprocess.run(['convert', png] + args,
                          capture_output=True, text=True).stdout.strip()


def exact(hexcolor):
    """整张截图里颜色恰好等于 hexcolor 的像素数 + 它们的外接矩形。

    极性必须是「匹配 -> 白、不匹配 -> 黑」：这样 %[fx:mean] 直接就是匹配比例，
    而 %@（trim 外接矩形，按角落像素当背景色）也正好圈出匹配区域，一趟出两个数。
    反过来写（匹配 -> 黑）会让 mean 变成「不匹配比例」—— 读数接近 1，
    很容易被当成「几乎整页都是这个颜色」。
    """
    common = ['-fill', 'black', '+opaque', '#' + hexcolor,
              '-fill', 'white', '-opaque', '#' + hexcolor]
    res = im(common + ['-format', '%[fx:mean] %w %h %@', 'info:']).split()
    try:
        n = round(float(res[0]) * int(res[1]) * int(res[2]))
        bbox = res[3] if len(res) > 3 else '?'
    except Exception:
        n, bbox = -1, '?'
    return n, bbox


def point(x, y):
    txt = im(['-crop', '1x1+%s+%s' % (x, y), '+repage', '-depth', '8', 'txt:-'])
    for tok in txt.replace('(', ' ').replace(')', ' ').split():
        if tok.startswith('#') and len(tok) >= 7:
            return tok[1:7].upper()
    return '??'


lines, fail = [], 0
for tok in spec.split():
    name, _, val = tok.partition('=')
    bits = val.split(',')
    if len(bits) != 3:
        lines.append('%s: SKIP (%s)' % (name, val))
        continue
    x, y, want = bits[0], bits[1], bits[2].upper()
    n, bbox = exact(want)
    got = point(x, y)
    verdict = 'PASS' if n > 0 else 'FAIL'
    if n <= 0:
        fail = 1
    note = ''
    if n > 0 and got != want:
        # 画出来了但报的坐标上不是它 —— 坐标漂移，不是绘制失败
        note = '  [坐标已漂移，判定看 present]'
    lines.append('%s: %s want=%s present=%dpx bbox=%s point@%s,%s=%s%s'
                 % (name, verdict, want, n, bbox, x, y, got, note))

out = '\n'.join(lines) + '\n'
open(report, 'w').write(out)
sys.stdout.write(out)
sys.exit(0 if fail == 0 else 3)
PY
  # 刻意**不**让容器 exit 1：本容器的产物是「事实」，判定留给读结论的人。
  # ctl（纯 CSS 背景色）FAIL 才说明取色环节自己坏了；img/bg FAIL 是 WebF 的事实。
  [ "$st" = 0 ] || log '取色判据有 FAIL —— 先看 ctl 那行：ctl 也 FAIL 说明取色环节自己坏了'
  return 0
}
sample_pixels

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
