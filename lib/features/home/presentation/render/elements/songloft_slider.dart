import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:webf/css.dart';
import 'package:webf/dom.dart' as dom;
import 'package:webf/webf.dart';

/// 标签名。**必须带连字符**（WebF 的自定义元素名校验只认 dash），
/// 且统一 `songloft-` 前缀防与插件自定义元素撞名。
///
/// 与 [kSongloftProgressRingTag] 同理做成顶层常量而不是类的 static：
/// `dom.Element` 已有实例成员 `tagName`，同名 static 会直接编译报错。
const String kSongloftSliderTag = 'songloft-slider';

/// `<songloft-slider>` —— WebF 下的原生滑块（songloft-org/songloft#341 Step 3）。
///
/// ── 为什么要有它 ─────────────────────────────────────────────────────────
///
/// WebF 的 `<input>` 实现（`html/form/input.dart:251-268` 的 `createInput`
/// switch）只认 radio / checkbox / button / submit / date / time / hidden，
/// **没有 range 分支**，于是 `input[type=range]` 落到 `default` 走
/// `createInputWidget()` → 一个 Flutter `TextField`。也就是说插件页里的音量条
/// 在 WebF 下会渲染成一个**可编辑文本框**：既不是滑块，还能被用户敲进任意字符。
/// 更麻烦的是 `min` / `max` / `step` 在 WebF 里**完全没有实现**（全 lib 无
/// `getAttribute('min')` 之类命中），它们只是普通 DOM 属性，对渲染与取值零影响。
///
/// 所以这里提供一个一等公民滑块元素。配套的 `common.js` 垫片
/// （`rangeSliderShim`）负责把插件页里既有的 `input[type=range]` **隐藏**并挂上
/// 本元素做双向同步 —— 刻意**不换掉原 `<input>`**，因为插件按 id/标签名
/// `querySelector` 后直接读写 `.value`（miot 有 9 处），换标签会静默打断插件
/// 自己的 JS。这是 Step 1 `<details>` 垫片留下的教训。
///
/// ── 为什么不用 Flutter 的 Material `Slider` ─────────────────────────────
///
/// 两条都是硬伤，不是审美问题：
///   ① **颜色跟不上插件页主题**。`Slider` 从 `Theme.of(context).colorScheme`
///      取色，那是**宿主 App** 的主题，而插件页的配色来自它自己 CSS 里的
///      `--md-*` 变量。要跟随插件页就必须显式喂色，那 `Slider` 的主要价值也就
///      没了。本元素沿用 [SongloftProgressRingElement] 已验证的那套「CSS
///      `color`（currentColor）+ 可选 `color` / `track-color` 属性」两级链。
///   ② **竖向做不出来**。`Slider` 内部是 `HorizontalDragGestureRecognizer`，
///      它的接受判据看的是**全局**水平位移；套 `RotatedBox` 转 90° 之后，用户
///      在屏幕上竖着拖的全局水平位移是 0，识别器永远不接受 → 拖不动（只有
///      点击定位还能凑巧工作）。而本任务的主命中面 miot `#volumeSlider`
///      恰恰是竖向的。
///
/// ── 手势：为什么是 axis-matched drag + onDown，而不是 onTap / Listener ──
///
/// WebF 在 `WidgetElement` 这一层只注册了**一个 `TapGestureRecognizer`**
/// （`gesture/gesture_dispatcher.dart:21-25`），**没有任何 pan/drag 识别器**，
/// 所以 Flutter 的拖动手势在这里不会被抢走。据此：
///
///   - **不用 `onTap`**：`GestureDetector(onTap:)` 会在竞技场里赢过 WebF 那个
///     tap recognizer，该元素的 DOM `click` 事件就**不再派发**了。滑块虽然自己
///     不需要 click，但插件可能在祖先上监听 —— 不该顺手掰断这条链。
///   - **不用 `Listener`（裸 pointer）**：它压根不进竞技场，于是在可滚动祖先里
///     会出现「页面在滚 + 滑块同时在动」的双重响应。drag 识别器会与滚动**竞争**，
///     这才是正确行为。
///   - **按朝向选轴**（竖向用 `onVerticalDrag*`、横向用 `onHorizontalDrag*`）而不是
///     统一用 pan：`PanGestureRecognizer` 的接受阈值是 `kPanSlop`（= 2×
///     `kTouchSlop`），而滚动用的是单轴 drag（`kTouchSlop`）—— 同轴向竞争时 pan
///     **必输**，竖滑块放进竖向滚动容器就彻底拖不动。同轴 drag 对同轴 drag 是
///     同阈值，此时命中测试更深的（也就是我们）先进竞技场、先接受、赢。
///     **残留风险**：这条依赖 Flutter 竞技场的「深者先」顺序，miot 的音量面板是
///     弹出层（非滚动容器）所以不受影响；真把竖滑块放进竖向滚动列表里仍可能抢不到。
///   - **`onDown` 就定位**（而不是等 `onStart`）：浏览器里点击 range 轨道会让
///     滑块跳到点击处。而一次纯点击下，WebF 的 tap recognizer 会在抬手时宣告胜利
///     并把我们的 drag **reject** 掉 → `onStart` 永远不触发，只有 `onDown` /
///     `onCancel` 会。所以定位必须挂在 `onDown` 上。
///     代价：拖动被同轴滚动抢走时，`onDown` 已经改过一次值了（随后收到
///     `onCancel`）。刻意**不在 cancel 里回滚** —— 纯点击走的也是
///     `onDown → onCancel` 这条路，回滚会把「点击定位」这个正常功能一起撤销。
///
/// ── 自包含约束（不要破坏）───────────────────────────────────────────────
///
/// 本目录下的文件只允许 import `flutter` 与 `webf`。原因见
/// `songloft_progress_ring.dart` 的同名小节（验证探针会把整目录拷进另一个
/// package 编译）。
class SongloftSliderElement extends WidgetElement {
  SongloftSliderElement(super.context);

  /// CSS 没给尺寸时的兜底：主轴 [defaultMainSize]，交叉轴 [defaultCrossSize]。
  /// 交叉轴取 28 是为了容得下直径 16 的滑块把手 + 上下各 6 的可点区。
  static const double defaultMainSize = 160.0;
  static const double defaultCrossSize = 28.0;

  static const double trackThickness = 4.0;
  static const double thumbRadius = 8.0;

  /// 未指定 `track-color` 时，未填充轨道 = 填充色降到这个不透明度。
  /// 与 [SongloftProgressRingElement.trackAlphaFactor] 同一取舍：从填充色派生
  /// 而不是写死一个灰，才能在亮/暗两套主题下都不难看。
  static const double trackAlphaFactor = 0.24;

  /// `disabled` 时整体再乘这个不透明度（Material 的 disabled 惯例值）。
  static const double disabledAlphaFactor = 0.38;

  /// `display` 默认 inline-block —— 滑块通常与文字/按钮并排（miot 的定时任务
  /// 音量条就在一个 label 下面），基类默认的 block 会强行换行。
  @override
  Map<String, dynamic> get defaultStyle => const {DISPLAY: INLINE_BLOCK};

  @override
  WebFWidgetElementState createState() => _SongloftSliderState(this);

  bool get isVertical =>
      (getAttribute('orientation') ?? '').trim().toLowerCase() == 'vertical';

  /// `disabled` 判定。
  ///
  /// HTML 的语义是「属性存在即禁用」，但那会踩上 WebF 自己的怪癖：
  /// `<input>` 的 disabled 走 `dom.attributeToProperty<bool>`
  /// （`base_input.dart:275-283` + `element.dart:3170-3171`），**任何非空字符串
  /// 都置 true**，连 `disabled="false"` 也等于禁用。垫片会把布尔值转写成
  /// 「加/删属性」，本不会产生 `"false"`；但插件也可能直接用本元素并手写
  /// `disabled="false"`，那种写法在浏览器里同样是禁用、在这里也保持禁用会更一致。
  /// 折中：`false` / `0` 视为未禁用（明显是想表达「否」），其余存在即禁用。
  bool get isDisabled {
    final String? raw = getAttribute('disabled');
    if (raw == null) return false;
    final String v = raw.trim().toLowerCase();
    return v != 'false' && v != '0';
  }

  /// 只用来给插件作者打一条「你传了个解析不了的值」的提示。
  ///
  /// 重绘**不靠这个钩子**：`WidgetElement.setAttribute` 在调 `attributeDidUpdate`
  /// 之前就已经 `state!.requestUpdateState()`（`widget_element.dart:171-179`），
  /// 而 `build` 每次都现读 `getAttribute`，所以属性一变必然画对。
  ///
  /// 例外是 `value`：交互期本地值必须**压过**外部写入，见
  /// [_SongloftSliderState.acceptExternalValue]。
  @override
  void attributeDidUpdate(String key, String value) {
    super.attributeDidUpdate(key, value);
    if (key == 'value') {
      (state as _SongloftSliderState?)?.acceptExternalValue();
    }
    if (value.isEmpty) return; // removeAttribute 会传空串，属正常路径
    switch (key) {
      case 'value':
      case 'min':
      case 'max':
      case 'step':
        if (key == 'step' && value.trim().toLowerCase() == 'any') break;
        if (_tryParseFinite(value) == null) {
          debugPrint(
            '[plugin][$kSongloftSliderTag] 属性 $key="$value" 不是有效数字，已忽略',
          );
        }
        break;
      case 'color':
      case 'track-color':
        if (CSSColor.parseColor(value, renderStyle: renderStyle) == null) {
          debugPrint(
            '[plugin][$kSongloftSliderTag] 属性 $key="$value" 不是有效颜色，已忽略',
          );
        }
        break;
      case 'orientation':
        final String v = value.trim().toLowerCase();
        if (v != 'vertical' && v != 'horizontal') {
          debugPrint(
            '[plugin][$kSongloftSliderTag] 属性 orientation="$value" 未识别'
            '（只认 horizontal / vertical），按 horizontal 处理',
          );
        }
        break;
    }
  }
}

/// 解析成有限 double；NaN / Infinity / 解析失败一律 null。
///
/// `double.tryParse('NaN')` 会成功返回 NaN，而 NaN 参与 clamp / 除法会画出空白
/// 或触发断言，所以必须显式拦掉。与 `songloft_progress_ring.dart` 里同名函数
/// 逻辑一致，刻意各留一份而不抽公共文件：这两个元素都要能被单独拷进验证探针，
/// 少一层文件依赖就少一处「探针编不过」的风险。
double? _tryParseFinite(String raw) {
  final double? parsed = double.tryParse(raw.trim());
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

/// 把 double 格成「像 HTML range 那样」的字符串：整数不带 `.0`，小数去掉尾零。
///
/// 这很重要：miot 全部消费点都是 `parseInt(el.value)`，而 `parseInt('50.0')`
/// 恰好也是 50 —— 但插件把它拼进文案（`volumePercent.textContent = this.value + '%'`）
/// 时就会显示成「50.0%」。
String _formatValue(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return v.toStringAsFixed(0);
  }
  String s = v.toStringAsFixed(6);
  s = s.replaceAll(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

class _SongloftSliderState extends WebFWidgetElementState {
  _SongloftSliderState(super.widgetElement);

  @override
  SongloftSliderElement get widgetElement =>
      super.widgetElement as SongloftSliderElement;

  /// 交互期的本地值。null = 跟随 `value` 属性。
  ///
  /// 为什么需要它：拖动过程中我们**不回写自己的 `value` 属性**（回写会再触发一轮
  /// `setAttribute → requestUpdateState`，把「谁是真值」搅成时序问题）。真值由
  /// 页面侧那个隐藏 `<input>` 持有，本元素在交互期只信自己。
  double? _localValue;

  /// 是否正在被用户拖/点。
  ///
  /// 它同时是**防抖动的最后一道闸**：拖动期间任何外部 `value` 写入都被忽略
  /// （见 [acceptExternalValue]）。这条很关键 —— 插件通常会定时轮询设备状态并
  /// 回写滑块（miot `js/playback.js:400-408` 就是），浏览器里它靠
  /// `el.matches(':active')` 判断「用户正在拖，别覆盖」，而 WebF 里那个隐藏
  /// `<input>` 永远不会真的进入 `:active`（`element.dart:245` 的 `isActive` 只由
  /// 落在**它自己**身上的指针事件置位，而它已经被隐藏了）。所以宿主侧必须自己
  /// 兜住：哪怕垫片那层的抑制失效，滑块也不会在用户手指还没抬起时跳回去。
  bool _dragging = false;

  double get _min => _number('min', 0);
  double get _max => _number('max', 100);

  double _number(String name, double fallback) {
    final String? raw = widgetElement.getAttribute(name);
    if (raw == null) return fallback;
    return _tryParseFinite(raw) ?? fallback;
  }

  /// `step`：默认 1（与 HTML range 一致）；`any` 或 <= 0 视为连续。
  double? get _step {
    final String? raw = widgetElement.getAttribute('step');
    if (raw == null) return 1.0;
    if (raw.trim().toLowerCase() == 'any') return null;
    final double? parsed = _tryParseFinite(raw);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  /// 属性里声明的值（不含交互期本地值）。
  double get _attributeValue => _number('value', _min);

  /// 当前展示值，已夹到 [min, max]。
  double get _effectiveValue {
    final double lo = _min;
    final double hi = _max;
    final double raw = _localValue ?? _attributeValue;
    if (hi <= lo) return lo; // 退化区间：算不出比例，一律停在起点
    return raw.clamp(lo, hi);
  }

  /// 外部（JS）改了 `value` 属性。
  ///
  /// 拖动期间**刻意忽略**，理由见 [_dragging]。非拖动期则放弃本地值、回到属性。
  void acceptExternalValue() {
    if (_dragging) return;
    if (_localValue == null) return;
    _localValue = null;
    requestUpdateState();
  }

  // ── 手势 → 值 ─────────────────────────────────────────────────────────

  /// 主轴上「轨道可用长度」的两端留白：滑块把手要整个待在盒子里，
  /// 否则 0% 与 100% 时把手会被自己的盒子裁掉一半。
  double get _pad => SongloftSliderElement.thumbRadius;

  double _fractionFromLocal(Offset local, Size size) {
    final bool vertical = widgetElement.isVertical;
    final double extent = (vertical ? size.height : size.width) - 2 * _pad;
    if (extent <= 0) return 0;
    final double pos = (vertical ? local.dy : local.dx) - _pad;
    final double frac = pos / extent;
    // 竖向：min 在**下**、max 在上。这是音量条的普遍预期，也与 miot 原本用
    // `transform: rotate(-90deg)` 把横向滑块转成竖向后的方向一致。
    return (vertical ? 1.0 - frac : frac).clamp(0.0, 1.0);
  }

  double _snap(double raw) {
    final double lo = _min;
    final double hi = _max;
    final double? step = _step;
    if (step == null) return raw.clamp(lo, hi);
    final double snapped = lo + ((raw - lo) / step).roundToDouble() * step;
    return snapped.clamp(lo, hi);
  }

  /// build 里按 CSS width/height 算出的尺寸，作为拿不到真实 render box 时的兜底。
  Size? _cssSize;

  /// 命中换算用的尺寸。
  ///
  /// 优先取**真实 render box** 而不是 build 里那份 CSS 尺寸：两者会差一点，
  /// 而差值直接变成「把手落不到手指底下」。实测（探针第 15 组）盒子上有
  /// `border: 1px dashed` 时，`getBoundingClientRect()` 是 90，而 WidgetElement 拿到
  /// 的内容盒是 88 —— 用 CSS 的 90 去换算，一次拖动的落点会偏出约 1% 量程。
  /// `CustomPaint` 的 `paint(canvas, size)` 拿到的本来就是真实盒子，所以只有换算
  /// 这一侧需要对齐。
  Size? get _hitSize {
    final RenderObject? ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) return ro.size;
    return _cssSize;
  }

  void _updateFromPointer(Offset local, {required bool fireInput}) {
    final Size? size = _hitSize;
    if (size == null || size.isEmpty) return;
    final double lo = _min;
    final double hi = _max;
    if (hi <= lo) return;
    final double next = _snap(lo + _fractionFromLocal(local, size) * (hi - lo));
    if (_localValue != null && (next - _localValue!).abs() < 1e-9) return;
    _localValue = next;
    requestUpdateState();
    if (fireInput) _dispatch(input: true);
  }

  /// 派发 DOM 事件给页面 JS。
  ///
  /// `input` 用 `dom.InputEvent(inputType: '', data: <新值>)` 而**不是**裸
  /// `dom.Event('input')`：WebF 自己的 `<input>` 就是这么派发的
  /// （`html/form/base_input.dart:560-562`），`input` 这个类型对应的 raw struct
  /// 比基类多两个字段（`event.dart:589-599` 的 `toRaw`），裸 `Event('input')`
  /// 长度不够、C++ 侧行为未经证实。`change` 则用裸 `dom.Event('change')`
  /// ——WebF 自己也这样（`base_input.dart:503`）。
  ///
  /// 新值同时塞进 `event.data`，页面侧读 `e.data` 即可拿到；**刻意不回写自己的
  /// `value` 属性**（见 [_localValue]）。
  ///
  /// `dispatchEvent` 返回 `Future<void>`、是**异步**的：JS 回调不在同一微任务内
  /// 跑完。这里刻意不 await —— 手势回调不该被页面 JS 的执行时长拖住。
  void _dispatch({bool input = false, bool change = false}) {
    final String data = _formatValue(_effectiveValue);
    try {
      if (input) {
        widgetElement.dispatchEvent(dom.InputEvent(inputType: '', data: data));
      }
      if (change) {
        widgetElement.dispatchEvent(dom.Event('change'));
      }
    } catch (e) {
      // 事件构造/派发失败只该让「页面收不到这一次通知」，不该打断手势。
      debugPrint('[plugin][$kSongloftSliderTag] dispatchEvent 失败: $e');
    }
  }

  void _onDragDown(DragDownDetails d) {
    if (widgetElement.isDisabled) return;
    _dragging = true;
    _updateFromPointer(d.localPosition, fireInput: true);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (widgetElement.isDisabled) return;
    _updateFromPointer(d.localPosition, fireInput: true);
  }

  /// 抬手（或手势被竞技场判负）。
  ///
  /// 两条都收敛到这里并派发 `change`：不然 `_dragging` 会永久卡在 true，
  /// 之后所有外部 `value` 写入都被忽略（滑块就再也跟不上插件的状态了）。
  /// 纯点击走的正是 `onDown → onCancel` 这条路，所以 cancel **必须**也派发
  /// `change` —— 浏览器里点击 range 轨道同样会产生一次 change。
  void _onDragDone() {
    if (!_dragging) return;
    _dragging = false;
    _dispatch(change: true);
  }

  // ── 颜色 ──────────────────────────────────────────────────────────────

  /// 与 `songloft_progress_ring.dart` 完全同一套两级链，结论也照搬（那边有
  /// `scripts/webf-verify` 第 13 组的实测支撑）：
  ///
  ///   ① CSS `color`（currentColor 语义）—— **唯一能跟着 `--md-*` 变量走的路**，
  ///      且 `color` 可继承，所以什么都不配也会取到继承来的文字色。
  ///   ② `color` / `track-color` 属性 —— 覆盖 ①，**只能写具体色值**。
  ///
  /// 刻意**不支持**属性里写 `var(--md-primary)`：`CSSColor.parseColor` 拿到原始
  /// `var(...)` 字符串返回 null（var 展开发生在样式系统内部，属性值不走那条路）。
  /// 也**不**在这里自己 `renderStyle.getCSSVariable()` 展开 —— 那样首帧对、但
  /// WebF 的变量变更通知只驱动「登记在 `target.style` 里、值含 `var(` 的 CSS
  /// 属性」，我们在 build 里读的变量不在那张依赖表上，主题一切换颜色就**永久
  /// 停在旧值**。「看起来支持、实际会静默过期」比「明确不支持」坏得多。
  Color _color(String attr, Color fallback) {
    final String? raw = widgetElement.getAttribute(attr);
    if (raw != null && raw.trim().isNotEmpty) {
      final Color? parsed = CSSColor.parseColor(
        raw,
        renderStyle: widgetElement.renderStyle,
      );
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  double _resolveSide(CSSLengthValue length, double fallback) {
    if (length.isAuto) return fallback;
    final double? value = length.value;
    if (value == null || !value.isFinite || value <= 0) return fallback;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final renderStyle = widgetElement.renderStyle;
    // 尊重 CSS 的 display:none —— WebF 会照常构建 widget 树，不自己判就会画出来。
    if (renderStyle.display == CSSDisplay.none) return const SizedBox.shrink();

    final bool vertical = widgetElement.isVertical;
    // 尺寸取 CSS width/height（与进度环同一套做法：读 renderStyle 而不是
    // LayoutBuilder —— auto 尺寸下约束是无界的，CustomPaint 必须自己给出确定 size）。
    // 兜底值按朝向分配主轴/交叉轴，否则竖向滑块在没写 CSS 时会是个 160 宽的横条。
    final double width = _resolveSide(
      renderStyle.width,
      vertical
          ? SongloftSliderElement.defaultCrossSize
          : SongloftSliderElement.defaultMainSize,
    );
    final double height = _resolveSide(
      renderStyle.height,
      vertical
          ? SongloftSliderElement.defaultMainSize
          : SongloftSliderElement.defaultCrossSize,
    );
    final Size size = Size(width, height);
    _cssSize = size;

    final bool disabled = widgetElement.isDisabled;
    final double lo = _min;
    final double hi = _max;
    final double fraction =
        hi > lo ? ((_effectiveValue - lo) / (hi - lo)).clamp(0.0, 1.0) : 0.0;

    Color active = _color('color', renderStyle.color.value);
    Color track = _color(
      'track-color',
      active.withValues(
        alpha: active.a * SongloftSliderElement.trackAlphaFactor,
      ),
    );
    if (disabled) {
      active = active.withValues(
        alpha: active.a * SongloftSliderElement.disabledAlphaFactor,
      );
      track = track.withValues(
        alpha: track.a * SongloftSliderElement.disabledAlphaFactor,
      );
    }

    final Widget painted = CustomPaint(
      size: size,
      painter: _SliderPainter(
        fraction: fraction,
        vertical: vertical,
        activeColor: active,
        trackColor: track,
        pad: _pad,
      ),
    );

    if (disabled) return painted;

    // 按朝向只挂一条轴的 drag 回调（另一轴传 null，GestureDetector 就不会为它
    // 建识别器）。理由见类注释「手势」小节。
    return GestureDetector(
      // opaque：轨道两侧是透明的，不声明 opaque 时那部分不进命中测试，
      // 用户点在把手之外就没反应。
      behavior: HitTestBehavior.opaque,
      onVerticalDragDown: vertical ? _onDragDown : null,
      onVerticalDragUpdate: vertical ? _onDragUpdate : null,
      onVerticalDragEnd: vertical ? (_) => _onDragDone() : null,
      onVerticalDragCancel: vertical ? _onDragDone : null,
      onHorizontalDragDown: vertical ? null : _onDragDown,
      onHorizontalDragUpdate: vertical ? null : _onDragUpdate,
      onHorizontalDragEnd: vertical ? null : (_) => _onDragDone(),
      onHorizontalDragCancel: vertical ? null : _onDragDone,
      child: painted,
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.fraction,
    required this.vertical,
    required this.activeColor,
    required this.trackColor,
    required this.pad,
  });

  final double fraction;
  final bool vertical;
  final Color activeColor;
  final Color trackColor;
  final double pad;

  @override
  void paint(Canvas canvas, Size size) {
    const double half = SongloftSliderElement.trackThickness / 2;
    const double radius = SongloftSliderElement.thumbRadius;

    if (vertical) {
      final double x = size.width / 2;
      final double top = pad;
      final double bottom = math.max(pad, size.height - pad);
      if (bottom <= top) return;
      // 竖向：min 在下、max 在上，所以「已填充」是从底部往上那一段。
      final double thumbY = bottom - (bottom - top) * fraction;
      _rounded(
        canvas,
        Rect.fromLTRB(x - half, top, x + half, bottom),
        trackColor,
      );
      _rounded(
        canvas,
        Rect.fromLTRB(x - half, thumbY, x + half, bottom),
        activeColor,
      );
      canvas.drawCircle(
        Offset(x, thumbY),
        radius,
        Paint()..color = activeColor,
      );
    } else {
      final double y = size.height / 2;
      final double left = pad;
      final double right = math.max(pad, size.width - pad);
      if (right <= left) return;
      final double thumbX = left + (right - left) * fraction;
      _rounded(
        canvas,
        Rect.fromLTRB(left, y - half, right, y + half),
        trackColor,
      );
      _rounded(
        canvas,
        Rect.fromLTRB(left, y - half, thumbX, y + half),
        activeColor,
      );
      canvas.drawCircle(
        Offset(thumbX, y),
        radius,
        Paint()..color = activeColor,
      );
    }
  }

  void _rounded(Canvas canvas, Rect rect, Color color) {
    if (rect.width <= 0 || rect.height <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        const Radius.circular(SongloftSliderElement.trackThickness / 2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) {
    return old.fraction != fraction ||
        old.vertical != vertical ||
        old.activeColor != activeColor ||
        old.trackColor != trackColor ||
        old.pad != pad;
  }
}
