import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:webf/css.dart';
import 'package:webf/webf.dart';

/// 标签名。**必须带连字符**（WebF 的自定义元素名校验只认 dash），
/// 且统一 `songloft-` 前缀防与插件自定义元素撞名。
///
/// 刻意做成顶层常量而不是类的 static：`dom.Element` 已有实例成员 `tagName`，
/// 同名 static 会直接编译报错（`conflicting_static_and_instance`）。
const String kSongloftProgressRingTag = 'songloft-progress-ring';

/// `<songloft-progress-ring>` —— WebF 下的原生环形进度条
/// （songloft-org/songloft#341）。
///
/// ── 为什么要有它 ─────────────────────────────────────────────────────────
///
/// WebF 的 `<svg>` 实现（`webf/src/html/svg.dart`）是：把整棵 svg 子树
/// **重新序列化成字符串**，交给 `flutter_svg` 的 `SvgPicture.string` 渲染。
/// 后果是子节点只作数据存在（`FlutterSVGChildElement` 压根不生成 render box），
/// 拿不到布局、单个 path 无法命中测试或单独动画，**且任何子节点的属性/样式/
/// 子树变更都会 `requestUpdateState()` 让整棵 SVG 重建**（重新拼字符串 + 重新
/// 解析 + 重新光栅化）。也就是说，「每秒改 strokeDashoffset 的 SVG 进度环」
/// 这种高频更新在 WebF 下是最差的一类写法。
///
/// 所以给插件作者提供一个一等公民元素：进度变化只走一次 `CustomPaint` 重绘，
/// 没有字符串序列化、没有 SVG 重解析。
///
/// **刻意不做自动替换**：不写「把插件里的内联 SVG 进度环换成本元素」的垫片。
/// SVG 是任意图形，「含两个 circle + stroke-dasharray 就算进度环」这类启发式
/// 匹配会误伤正常 SVG，代价大于收益；加上自定义元素名必须带连字符（见
/// [SongloftCustomElements]），宿主本来也没法悄悄顶替内建 `<svg>`。替换由插件
/// 自己按需做。
///
/// ── 自包含约束（不要破坏）───────────────────────────────────────────────
///
/// 本目录下的文件只允许 import `flutter` 与 `webf`，**不得** import 项目里
/// 任何其它东西（riverpod / provider / `../` 上层文件）。原因：验证探针
/// （`scripts/webf-verify/`）是独立的 Flutter package，它在容器里把**本目录
/// 原样拷进自己的 lib/** 后编译，测的才是产品实现而不是探针里另抄的一份。
/// 一旦这里引入产品依赖，探针就编不过，只能退化成抄一份 —— 那就失去意义了。
class SongloftProgressRingElement extends WidgetElement {
  SongloftProgressRingElement(super.context);

  /// CSS 没给尺寸时的兜底边长（px）。与 Material 的小号 spinner 同量级。
  static const double defaultSize = 36.0;
  static const double defaultStrokeWidth = 4.0;

  /// 未指定 `track-color` 时，轨道 = 进度色降到这个不透明度。
  ///
  /// 刻意用「从进度色派生」而不是写死一个灰：写死的灰在亮/暗两套主题里必有
  /// 一套难看，而派生值天然跟着进度色（也就是跟着主题）走。
  static const double trackAlphaFactor = 0.24;

  /// `display` 默认 inline-block —— 进度环通常跟文字/按钮并排，
  /// 基类默认的 block 会强行换行。
  @override
  Map<String, dynamic> get defaultStyle => const {DISPLAY: INLINE_BLOCK};

  @override
  WebFWidgetElementState createState() => _SongloftProgressRingState(this);

  /// 只用来给插件作者打一条「你传了个解析不了的值」的提示。
  ///
  /// 重绘**不靠这个钩子**：基类 `setAttribute` / `removeAttribute` 在调用
  /// `attributeDidUpdate` 之前就已经 `state!.requestUpdateState()` 了（条件是
  /// `shouldElementRebuild` 判定值有变化，默认实现即 `prev != next`）。
  /// 本元素的 `build` 每次都现读 `getAttribute`，所以属性一变必然画对，
  /// 不需要在这里缓存解析结果 —— 缓存反而会引入「先 setState 再改字段」的
  /// 时序坑。
  ///
  /// 静默夹紧非法值是对的（页面不该因为一个坏属性就崩），但完全不出声会让
  /// 插件作者调半天，故这里补一条日志。
  @override
  void attributeDidUpdate(String key, String value) {
    super.attributeDidUpdate(key, value);
    if (value.isEmpty) return; // removeAttribute 会传空串，属正常路径
    switch (key) {
      case 'value':
      case 'min':
      case 'max':
      case 'stroke-width':
        if (_tryParseFinite(value) == null) {
          debugPrint(
            '[plugin][$kSongloftProgressRingTag] 属性 $key="$value" 不是有效数字，已忽略',
          );
        }
        break;
      case 'color':
      case 'track-color':
        if (CSSColor.parseColor(value, renderStyle: renderStyle) == null) {
          debugPrint(
            '[plugin][$kSongloftProgressRingTag] 属性 $key="$value" 不是有效颜色，已忽略',
          );
        }
        break;
    }
  }
}

/// 解析成有限 double；NaN / Infinity / 解析失败一律 null。
///
/// `double.tryParse('NaN')` 会成功返回 NaN，而 NaN 参与 clamp / drawArc 会画出
/// 空白或触发断言，所以必须显式拦掉。
double? _tryParseFinite(String raw) {
  final double? parsed = double.tryParse(raw.trim());
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

class _SongloftProgressRingState extends WebFWidgetElementState {
  _SongloftProgressRingState(super.widgetElement);

  double _number(String name, double fallback) {
    final String? raw = widgetElement.getAttribute(name);
    if (raw == null) return fallback;
    return _tryParseFinite(raw) ?? fallback;
  }

  /// 颜色解析的两级链，**这就是「跟随插件页主题」的方案**。两条都在
  /// `scripts/webf-verify` 的第 13 组里有回归用例，下面的结论都是实测的：
  ///
  ///   ① CSS `color` 属性（currentColor 语义）—— 首选，也是**唯一能跟着
  ///      `--md-*` 变量走的路**。插件写
  ///      `songloft-progress-ring { color: var(--md-primary) }` 即可；而且
  ///      `color` 可继承，所以**什么都不配也会取到继承来的文字色**，而
  ///      common.css 把文字色绑到了 `--md-on-surface` —— 零配置就跟主题。
  ///      实测运行时改该变量，环会跟着重绘：变量变更通知会把 `target.style`
  ///      里含 `var(` 的 `color` 重新 set 一遍，进而触发 widget 重建。
  ///   ② `color` / `track-color` 属性 —— 覆盖 ①，用于「进度色与文字色不同」
  ///      或颜色由 JS 计算出来的场合。**只能写具体色值**
  ///      （`#RGB` / `#RRGGBB` / `rgb()` / 颜色关键字）。
  ///
  /// 刻意**不支持**属性里写 `var(--md-primary)`：实测 `CSSColor.parseColor`
  /// 拿到原始 `var(...)` 字符串返回 null（var 展开发生在样式系统内部，属性值
  /// 不走那条路），此时按无效值退回 ①。也**不**在这里自己用
  /// `renderStyle.getCSSVariable()` 展开 —— 那样首帧颜色是对的，但 WebF 的变量
  /// 变更通知（`CSSVariableMixin._notifyCSSVariableChanged`）只驱动「登记在
  /// `target.style` 里、值含 `var(` 的 CSS 属性」，我们在 build 里读的变量不在
  /// 那张依赖表上，主题一切换颜色就**永久停在旧值**。
  /// 「看起来支持、实际会静默过期」比「明确不支持」坏得多。
  ///
  /// 另一条直觉上可行、实际在 WebF 下走不通的写法：用
  /// `getComputedStyle(el).getPropertyValue('--md-primary')` 把变量读成色值再写进
  /// 属性 —— 实测 WebF 的 getComputedStyle **不暴露自定义属性**，一律返回空串。
  /// 想跟变量就只能走 ①。
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

  double _resolveSide(CSSLengthValue length) {
    if (length.isAuto) return SongloftProgressRingElement.defaultSize;
    final double? value = length.value;
    if (value == null || !value.isFinite || value <= 0) {
      return SongloftProgressRingElement.defaultSize;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final renderStyle = widgetElement.renderStyle;
    // 尊重 CSS 的 display:none —— WebF 会照常构建 widget 树，不自己判就会画出来。
    if (renderStyle.display == CSSDisplay.none) return const SizedBox.shrink();

    // 尺寸取 CSS width/height（与 webf 自带的 shimmer 元素同一套做法：
    // 读 renderStyle 而不是 LayoutBuilder —— auto 尺寸下约束是无界的，
    // CustomPaint 必须自己给出确定 size）。
    final double width = _resolveSide(renderStyle.width);
    final double height = _resolveSide(renderStyle.height);
    final double side = math.min(width, height);

    final double min = _number('min', 0);
    final double max = _number('max', 100);
    final double value = _number('value', 0);
    // max <= min 是退化区间（含 max=min 的除零）：算不出比例，按 0 处理，
    // 只画轨道。**不抛异常** —— 插件传坏参数不该让整页白屏。
    final double fraction =
        max > min ? ((value - min) / (max - min)).clamp(0.0, 1.0) : 0.0;

    // 线宽夹到 (0, side/2]：>= side 会让半径变负、drawArc 画不出东西；
    // <= 0 在 Flutter 里表示「hairline」，对进度环没有意义。
    final double strokeWidth = _number(
      'stroke-width',
      SongloftProgressRingElement.defaultStrokeWidth,
    ).clamp(0.5, math.max(0.5, side / 2));

    final Color color = _color('color', renderStyle.color.value);
    final Color trackColor = _color(
      'track-color',
      color.withValues(
        alpha: color.a * SongloftProgressRingElement.trackAlphaFactor,
      ),
    );

    return CustomPaint(
      size: Size(width, height),
      painter: _RingPainter(
        fraction: fraction,
        color: color,
        trackColor: trackColor,
        strokeWidth: strokeWidth,
        rounded: widgetElement.getAttribute('line-cap') == 'round',
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.rounded,
  });

  final double fraction;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final bool rounded;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    // 描边是以路径为中心向两侧各画一半，所以半径要往里收半个线宽，
    // 否则环会被自己的盒子裁掉外沿。
    final double radius = (side - strokeWidth) / 2;
    if (radius <= 0) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    if (fraction <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      // 从 12 点开始顺时针，与浏览器里 SVG 进度环的惯例一致
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = rounded ? StrokeCap.round : StrokeCap.butt
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) {
    return old.fraction != fraction ||
        old.color != color ||
        old.trackColor != trackColor ||
        old.strokeWidth != strokeWidth ||
        old.rounded != rounded;
  }
}
