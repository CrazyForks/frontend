import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/semantics.dart';

import 'semantics_pointer_override.dart';

/// Web 端语义树（无障碍）句柄管理。
///
/// Songloft **桌面** Web 默认常驻语义树（`ensureSemantics()`，见无障碍改进
/// songloft-org/songloft#186），让读屏器无需用户先点「Enable accessibility」；
/// 移动端浏览器**不常驻**，否则软键盘弹不出来（见下文 songloft-player#26）。
///
/// ## 全局 pointer-events 覆盖（songloft-org/songloft#378）
///
/// 常驻语义树时，引擎为每个语义节点设置 `pointer-events: auto`，形成覆盖在
/// canvas 之上的 DOM 层。Flutter 自身的 hover 检测走 canvas 层 hit-testing（始终
/// 准确），但点击可被语义 DOM 节点拦截。若语义节点的位置因滚动、布局变化
/// （ExpansionTile 展开/收起）等原因与渲染树不同步（flutter/flutter#175119），
/// 就会出现「hover 高亮在 A 项、点击却落到 B 项」的错位。
///
/// 修复：[enableByDefault] 在获取句柄的同时**全局注入**
/// `pointer-events: none !important`，确保所有指针事件统一走 Flutter canvas
/// 层 hit-testing，彻底消除 hover/click 位置漂移。屏幕阅读器通过无障碍 API
/// 操作元素、不依赖 DOM pointer events，功能不受影响。
///
/// ## 插件 Tab iframe 遮挡（songloft-org/songloft#295）
///
/// 插件 Tab 是内嵌 iframe 的**平台视图**（HtmlElementView）。即使全局 CSS 已禁止
/// 语义节点拦截指针，语义 DOM 本身仍可能叠在 iframe 上方、干扰原生事件分发
/// （尤其在读屏器激活、平台持有独立句柄时语义 DOM 不可拆除）。
///
/// [suspendForPlugin] 临时释放我们持有的句柄：若此时没有读屏器，语义树句柄计数
/// 归零、整棵语义 DOM 被拆除，iframe 恢复正常；离开插件 Tab 时 [resume] 重新
/// 获取句柄。引用计数支持多个调用方（shell_layout 插件 Tab + plugin_webview_page
/// 全屏插件路由）安全嵌套。
///
/// ## 移动端浏览器不常驻语义树（songloft-org/songloft-player#26）
///
/// **常驻语义树会让移动浏览器（尤其 iOS Safari）的软键盘无法弹出**，登录页的
/// 用户名/密码框首当其冲。原因：引擎的 `HybridTextEditing.strategy` 是
/// `late final`，**首次用到文本输入时**按当时的 `semanticsEnabled` 一次性定型。
/// 启动即 `ensureSemantics()` 会把整个会话钉死在 `SemanticsTextEditingStrategy`
/// 上，从此绕开 `IOSTextEditingStrategy` —— 后者才带着 iOS 的全部绕法（聚焦前
/// 先移出屏外、100ms 后再定位、tap 监听），以及 iOS 26「自动填充前先 blur 输入
/// 框」的补救（该补救只监听 `flt-text-editing-host` 的 focusin，语义模式下输入
/// 框在 `flt-semantics-host` 里，够不着）。
///
/// 上游长期未修：[flutter/flutter#129324]（仍 open，3.41 可复现）、
/// [flutter/flutter#123338]、[flutter/flutter#141975]、[flutter/flutter#154741]
/// —— 症状均为「语义模式 + 移动浏览器 → 键盘不弹或弹起立刻收起」，且与
/// `InputDecoration`（label/hint/suffixIcon）、滚动容器组合相关，正是登录页的形状。
///
/// 故 [enableByDefault] 在移动端浏览器（iOS / Android）直接跳过：Web 移动端回落
/// 到引擎默认的按需启用路径（`MobileSemanticsEnabler` 检测读屏器的双击手势后自动
/// 开启语义树），读屏器用户仍可用，普通用户的输入法恢复正常。桌面 Web 不受影响，
/// 继续常驻（#186 的收益主要也在桌面读屏器）。
///
/// 非 Web 平台所有方法均为 no-op。
class WebSemanticsController {
  WebSemanticsController._();

  static final WebSemanticsController instance = WebSemanticsController._();

  /// 我们主动持有的语义树句柄（仅 Web）。为空表示当前未持有。
  SemanticsHandle? _handle;

  /// 是否处于「默认应常驻语义树」的状态（启动后置真）。用于确保 [resume] 只在
  /// 我们本就希望常驻时才重新获取句柄，避免在插件 Tab 之外的意外调用打开语义树。
  bool _wantEnabledByDefault = false;

  /// 当前活跃的 suspend 调用计数。多个独立调用方（shell_layout 的插件 Tab 边沿
  /// 触发 + plugin_webview_page 的 initState/dispose）可能交叉调用
  /// suspend/resume，引用计数确保仅当**所有**调用方都 resume 后才真正恢复语义。
  int _suspendCount = 0;

  /// 应用启动时调用一次：桌面 Web 默认启用（常驻）语义树，并全局注入
  /// `pointer-events: none` 覆盖，防止语义 DOM 节点拦截指针事件导致
  /// hover/click 位置漂移（songloft-org/songloft#378）。
  ///
  /// 移动端浏览器跳过，否则软键盘弹不出来（见类注释
  /// songloft-org/songloft-player#26）。
  void enableByDefault() {
    if (!kIsWeb) return;
    if (isMobileWebPlatform(defaultTargetPlatform)) return;
    _wantEnabledByDefault = true;
    _acquire();
    injectSemanticsPointerOverride();
  }

  /// 当前 Web 运行环境是否为移动端浏览器。
  ///
  /// Web 上 `defaultTargetPlatform` 由引擎按 `navigator.platform` /
  /// `maxTouchPoints` 推断浏览器所在系统；iPadOS 谎报 `MacIntel` 的情况引擎已处理
  /// （`maxTouchPoints > 2` → iOS），故无需自己解析 UA。引擎把无法识别的系统归为
  /// `android`，此处一并按移动端处理（宁可少开语义树，也不要赌输入法）。
  @visibleForTesting
  static bool isMobileWebPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.android;

  /// 进入插件 Tab（iframe 平台视图激活）时调用：临时释放语义句柄，让无读屏器
  /// 时的语义 DOM 被完全拆除，避免残留节点叠在 iframe 上方干扰原生事件分发
  /// （songloft-org/songloft#295）。同时注入全局 pointer-events 覆盖——桌面 Web
  /// 上由 [enableByDefault] 已注入（此处幂等 no-op），移动端 Web 则在此处兜底
  /// 读屏器自行开启语义树的场景。
  ///
  /// 支持嵌套：多次调用需匹配等量的 [resume] 才真正恢复。
  ///
  /// 不要求 [_wantEnabledByDefault]：移动端浏览器不常驻语义树，但读屏器可能自己
  /// 开启语义树（[_release] 在未持句柄时本就是 no-op）。
  void suspendForPlugin() {
    if (!kIsWeb) return;
    _suspendCount++;
    if (_suspendCount == 1) {
      _release();
      injectSemanticsPointerOverride();
    }
  }

  /// 离开插件 Tab 时调用：当所有 suspend 调用方都已 resume 后，仅当本就常驻语义树
  /// （桌面 Web）时重新获取句柄。
  void resume() {
    if (!kIsWeb) return;
    if (_suspendCount <= 0) return;
    _suspendCount--;
    if (_suspendCount == 0) {
      if (_wantEnabledByDefault) _acquire();
    }
  }

  void _acquire() {
    _handle ??= SemanticsBinding.instance.ensureSemantics();
  }

  void _release() {
    _handle?.dispose();
    _handle = null;
  }
}
