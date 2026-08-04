import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/webview_environment.dart';
import '../../../../l10n/app_localizations.dart';
import '../plugin_host_bridge.dart';
import 'plugin_render_controller.dart';

/// `flutter_inappwebview` 渲染面（songloft-org/songloft#341 抽层前的原实现）。
///
/// 只负责「渲染 + 宿主桥 + 主题下推」，加载态 / 超时 / 错误 UI / 重试全部归
/// `PluginRenderView` 管，两个宿主页面因此不再各自持有一份重复逻辑。
class PluginRenderSurfaceWebView extends ConsumerStatefulWidget {
  /// 已经拼好的完整插件页 URL（含 theme / access_token / embed）。
  final String url;

  /// 当前生效主题（`light` / `dark`），变化时下推给页面。
  final String theme;

  /// Android 是否使用 Hybrid Composition。
  ///
  /// 插件 Tab 传 false（改用 Virtual Display）：Tab 靠 shell 层 `Offstage` 保活
  /// （songloft-org/songloft#273），而 Hybrid Composition 下 WebView 是独立原生
  /// 表面 + overlay 合成，反复 Offstage 切换后 overlay 会重建异常，把画在其上的
  /// 底部 NavigationBar 抹成黑块。代价是 Virtual Display 的 IME 支持较弱，
  /// 需要大量文本输入的场景走全屏页（传 true，即默认）。
  /// iOS/macOS 忽略此项（WKWebView 无此问题）。
  final bool useHybridComposition;

  final VoidCallback onLoadStart;
  final VoidCallback onLoadStop;
  final void Function(String message) onError;
  final void Function(PluginRenderController controller) onControllerReady;

  const PluginRenderSurfaceWebView({
    super.key,
    required this.url,
    required this.theme,
    required this.onLoadStart,
    required this.onLoadStop,
    required this.onError,
    required this.onControllerReady,
    this.useHybridComposition = true,
  });

  @override
  ConsumerState<PluginRenderSurfaceWebView> createState() =>
      _PluginRenderSurfaceWebViewState();
}

class _PluginRenderSurfaceWebViewState
    extends ConsumerState<PluginRenderSurfaceWebView>
    with PluginHostBridgeMixin
    implements PluginRenderController {
  InAppWebViewController? _controller;
  bool _pageReady = false;

  @override
  void didUpdateWidget(covariant PluginRenderSurfaceWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 首屏主题靠 URL 的 ?theme= 参数，这里只处理运行中的切换。
    if (oldWidget.theme != widget.theme && _pageReady) {
      _controller?.evaluateJavascript(
        source:
            "window.postMessage({type:'songloft-theme',theme:'${widget.theme}'},'*')",
      );
    }
  }

  // ── PluginRenderController ──────────────────────────────────────────
  @override
  Future<bool> goBackIfPossible() async {
    final controller = _controller;
    if (controller == null) return false;
    if (!await controller.canGoBack()) return false;
    await controller.goBack();
    return true;
  }

  @override
  void clearFocus() => _controller?.clearFocus();

  // ── 渲染 ────────────────────────────────────────────────────────────
  /// token 注入是**冗余的双保险**：token 本来就通过 URL 的 `?access_token=`
  /// 传递，由后端注入的 authBridge 内联脚本（`internal/jsplugin/routes.go`）
  /// 读出来写进 localStorage 并清理 URL。这里再注入一次是为了让页面在
  /// authBridge 执行前就能读到。
  String _buildTokenInjectionScript() {
    final token = SecureStorageService.cachedAccessToken ?? '';
    if (token.isEmpty) return '';
    final escapedToken = token
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"');
    return "localStorage.setItem('songloft-auth', JSON.stringify({accessToken: '$escapedToken'}));";
  }

  @override
  Widget build(BuildContext context) {
    listenPlayerState();

    final tokenScript = _buildTokenInjectionScript();

    return InAppWebView(
      webViewEnvironment: SongloftWebViewEnvironment.instance,
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialUserScripts:
          tokenScript.isNotEmpty
              ? UnmodifiableListView([
                UserScript(
                  source: tokenScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              ])
              : null,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        supportZoom: false,
        useHybridComposition: widget.useHybridComposition,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        registerHostBridge(controller);
        widget.onControllerReady(this);
      },
      onLoadStart: (controller, url) {
        _pageReady = false;
        widget.onLoadStart();
      },
      onLoadStop: (controller, url) {
        _pageReady = true;
        widget.onLoadStop();
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          _pageReady = false;
          widget.onError(error.description);
        }
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        if (request.isForMainFrame ?? false) {
          _pageReady = false;
          final status = errorResponse.statusCode;
          final reason = errorResponse.reasonPhrase;
          final detail = reason == null || reason.isEmpty ? '' : ' $reason';
          widget.onError(
            AppLocalizations.of(
              context,
            ).homePluginLoadFailedHttp(status.toString(), detail),
          );
        }
      },
    );
  }
}
