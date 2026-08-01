import 'package:flutter/foundation.dart';
import 'package:webf/webf.dart';

import 'songloft_progress_ring.dart';

/// WebF 自定义元素注册点（songloft-org/songloft#341）。
///
/// ── 为什么单独一个入口 ────────────────────────────────────────────────────
///
/// `WebF.defineCustomElement` 写的是 **进程级全局** 注册表
/// （`dom/element_registry.dart` 里的 `_widgetElements` map），而且
/// `defineWidgetElement` 对重复注册是 **抛异常** 而非覆盖。所以它必须：
///   ① 只做一次（幂等）；
///   ② 早于任何 `WebFController` 创建 —— controller 初始化期会预取
///      widget 元素的形状/属性默认值（`collectDefaultAttributePairsForWidgetShape`），
///      注册晚了那一页就只能拿到 `_UnknownHTMLElement`。
/// 这与 `PluginRenderSurfaceWebF._ensureWebFProcessSetup()` 里的
/// `WebFControllerManager.instance.initialize` 是同一类约束，故两者放在一起调用。
///
/// ── 硬约束：标签名必须带连字符 ────────────────────────────────────────────
///
/// `WebF._isValidCustomElementName` 要求「首字符 a-z + 必须含至少一个 `-`」，
/// 不合规直接 `throw ArgumentError`。所以 **无法用这套机制去覆盖 `<svg>` /
/// `<audio>` / `<table>` / `<input>` 这类内建标签**（`overrideCustomElement`
/// 同样过这道校验）。后续所有原生组件都只能是「新标签」，也就是说：
/// 插件必须显式改用我们的标签，宿主没法悄悄替换掉插件里既有的内建标签。
/// 「自动替换内联 SVG 进度环」这条路因此走不通，也是刻意不做的原因之一
/// （SVG 是任意图形，机械判定「这个 svg 是进度环」必然误伤）。
///
/// ── 命名 ────────────────────────────────────────────────────────────────
///
/// 一律 `songloft-` 前缀：注册表是全局单例，插件页自己也可能 `defineElement`
/// 或用带连字符的标签名，前缀是避免撞名的唯一手段。
class SongloftCustomElements {
  const SongloftCustomElements._();

  static bool _registered = false;

  /// 幂等注册。可安全重复调用（产品侧每次建 controller 前都会调，
  /// 验证探针也会在 `main()` 里调）。
  static void ensureRegistered() {
    if (_registered) return;
    _registered = true;

    _define(
      kSongloftProgressRingTag,
      (context) => SongloftProgressRingElement(context),
    );
  }

  /// 逐个元素包 try/catch，理由与 `common.js` 的 `runShims` 一致：
  /// 一个元素注册失败只该让 **那一个标签** 退回 WebF 的原生表现
  /// （`_UnknownHTMLElement`，即一个空的 display:block 盒子），
  /// 绝不该连带打掉其它元素、更不该让整个插件渲染面起不来。
  static void _define(String tagName, ElementCreator creator) {
    try {
      WebF.defineCustomElement(tagName, creator);
    } catch (e) {
      // 已注册（热重启后 registry 仍在）或标签名不合规都会走到这里。
      debugPrint('[plugin][element] define "$tagName" failed: $e');
    }
  }
}
