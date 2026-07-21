import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/semantics.dart';

import 'semantics_pointer_override.dart';

/// Web 端语义树（无障碍）句柄管理。
///
/// Songloft Web 端默认常驻语义树（`ensureSemantics()`，见无障碍改进
/// songloft-org/songloft#186），让读屏器无需用户先点「Enable accessibility」。
///
/// 但插件 Tab 是内嵌 iframe 的**平台视图**（HtmlElementView）。当语义树常驻时，
/// Flutter 引擎的残留 bug（[flutter/flutter#175119]）会把语义节点卡在
/// `pointer-events: auto` 并叠在插件平台视图之上，抢走本该落到 iframe 的点击，
/// 导致插件完全无法操作（songloft-org/songloft#295）。引擎主修复 #182167 已在
/// 当前 Flutter 版本中，但未完全覆盖此场景。
///
/// 方案分两层：
///
/// 1. **释放语义句柄**——进入插件 Tab 时临时释放我们持有的语义句柄。若此时没有
///    读屏器（普通鼠标用户），语义树句柄计数归零、整棵语义 DOM 被拆除，残留的
///    遮挡节点随之消失，iframe 恢复可点击；离开插件 Tab 时重新获取句柄。
///
/// 2. **CSS 层 pointer-events 覆盖**——释放句柄在读屏器激活时（平台持有另一个
///    独立句柄，见 SemanticsBinding `_handleSemanticsEnabledChanged`）不会关闭
///    语义树。此时第二层保底：给 `flt-semantics-host` 加 CSS class，用
///    `pointer-events: none !important` 覆盖引擎对每个 `flt-semantics` 节点设置
///    的内联 `pointer-events: auto/all`，确保语义节点无论是否存在都不会拦截
///    iframe 的点击事件。
///
/// [suspendForPlugin] / [resume] 使用引用计数：多个独立调用方（shell_layout 的
/// 插件 Tab 与 plugin_webview_page 的全屏插件路由）可安全嵌套，仅当所有调用方
/// 都已 resume 后才真正恢复语义树。
///
/// 插件内容本身是独立文档、自带无障碍，故主 App 的无障碍能力不受影响。
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

  /// 应用启动时调用一次：Web 端默认启用（常驻）语义树。
  void enableByDefault() {
    if (!kIsWeb) return;
    _wantEnabledByDefault = true;
    _acquire();
  }

  /// 进入插件 Tab（iframe 平台视图激活）时调用：临时释放语义句柄，并用 CSS
  /// 覆盖禁止语义节点拦截指针事件，避免残留语义节点遮挡 iframe
  /// （songloft-org/songloft#295）。
  ///
  /// 支持嵌套：多次调用需匹配等量的 [resume] 才真正恢复。
  void suspendForPlugin() {
    if (!kIsWeb || !_wantEnabledByDefault) return;
    _suspendCount++;
    if (_suspendCount == 1) {
      _release();
      overrideSemanticsPointerEvents(true);
    }
  }

  /// 离开插件 Tab 时调用：当所有 suspend 调用方都已 resume 后，恢复常驻语义树
  /// 和指针事件。
  void resume() {
    if (!kIsWeb || !_wantEnabledByDefault) return;
    if (_suspendCount <= 0) return;
    _suspendCount--;
    if (_suspendCount == 0) {
      _acquire();
      overrideSemanticsPointerEvents(false);
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
