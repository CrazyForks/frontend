import 'package:flutter/services.dart';

/// WebF 渲染面所需的字体预注册（songloft-org/songloft#341）。
///
/// ## 为什么需要它
///
/// 插件页的图标全部是 Material Symbols 的**连字写法**（`<span
/// class="material-symbols-outlined">download</span>`，全部插件合计约 350 处），
/// 字体由后端注入的 `common.css` 用 `@font-face` 声明。这条路在 WebF 下是断的，
/// 两个缺陷叠加（webf 0.24.27，均已实测复现，见 `scripts/webf-verify/`）：
///
/// 1. **woff2 被静默丢弃**。`css/font_face.dart` 的 `supportedFonts` 白名单只有
///    `ttc/ttf/otf/data`，且 format 是从 **URL 扩展名**推断的、完全无视 CSS 里的
///    `format()` 声明；挑不到受支持的源就直接 return —— 不发请求、不打日志。
/// 2. **即使换成 ttf，URL 加载分支本身也是坏的**。它把响应交给 Skia 时取的是
///    整个底层 buffer 而不是视图切片，Skia 解析失败后只写一条默认不输出的
///    warning，表现与「完全没加载」一模一样。（同文件的 `data:` 分支用的是
///    正确的切片写法，所以 base64 内联能work。）
///
/// 结果：连字渲染成字面单词 "download"，改用码点则是豆腐块。
///
/// ## 解法
///
/// WebF 的文本最终走 Flutter 的 `TextStyle.fontFamily`。只要同名 family 已经在
/// 引擎字体表里，CSS 里那条注定失效的 `@font-face` 就无关紧要了。
///
/// 相比在 `common.css` 里内联 base64（另一条实测可行的路），这条的好处是
/// **不动 `common.css`** —— 那个文件由后端服务给所有客户端和普通浏览器，
/// 内联会让它从 17.6 KB 涨到约 1.5 MB，是不可接受的全局回归。
///
/// ## 刻意只注册图标字体
///
/// `common.css` 还声明了三个字重的 Roboto，但**故意不注册**：`Roboto` 是
/// Flutter Material 的默认字族，注册同名 family 会全局覆盖掉它，而后端那份
/// woff2 只有 37 KB、显然是拉丁子集，覆盖后整个 App 的排版都可能出问题。
/// 图标字族名唯一、不存在这个风险；Roboto 回落到平台默认 sans，视觉差异可忽略。
class PluginRenderFonts {
  PluginRenderFonts._();

  static const String _iconFamily = 'Material Symbols Outlined';
  static const String _iconAsset = 'fonts/material-symbols-outlined.ttf';

  static Future<void>? _pending;

  /// 幂等地把图标字体注册进引擎字体表。并发调用共享同一个 Future。
  ///
  /// 只在 WebF 渲染面初始化时调用 —— InAppWebView 路径由系统 WebView 自己
  /// 处理 `@font-face`，不需要也不应该付这份加载开销。
  static Future<void> ensureLoaded() => _pending ??= _load();

  static Future<void> _load() async {
    // rootBundle.load 直接给 ByteData，不存在「视图 vs 底层 buffer」的坑
    // （那正是 WebF 自己踩的那个）。
    final ByteData bytes = await rootBundle.load(_iconAsset);
    final loader = FontLoader(_iconFamily)..addFont(Future.value(bytes));
    await loader.load();
  }
}
