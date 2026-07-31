import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/window_visibility.dart';
import '../../../../l10n/app_localizations.dart';
import 'plugin_render_controller.dart';
import 'plugin_render_surface_webf.dart';
import 'plugin_render_surface_webview.dart';

/// 插件页渲染层的**引擎无关**外壳（songloft-org/songloft#341）。
///
/// 负责所有与「用哪个引擎渲染」无关的事：加载态、20s 超时、错误 UI 与重试、
/// 窗口可见性处理。真正的渲染面由 `PluginRenderSurface*` 提供。
///
/// 抽出它同时消掉了 `plugin_tab_page_native` 与 `plugin_webview_page_native`
/// 里两份逐字重复的超时 / 错误视图 / token 注入 / 重建计数逻辑。
class PluginRenderView extends ConsumerStatefulWidget {
  /// 已经拼好的完整插件页 URL（含 theme / access_token / embed）。
  final String url;

  /// 当前生效主题（`light` / `dark`）。
  final String theme;

  /// 见 `PluginRenderSurfaceWebView.useHybridComposition`。
  final bool useHybridComposition;

  /// 渲染面就绪时回调，宿主用它做返回键处理与焦点释放。
  ///
  /// 注意会被多次调用：重试或窗口重新可见都会重建渲染面，宿主应覆盖旧引用。
  final void Function(PluginRenderController controller) onControllerReady;

  const PluginRenderView({
    super.key,
    required this.url,
    required this.theme,
    required this.onControllerReady,
    this.useHybridComposition = true,
  });

  @override
  ConsumerState<PluginRenderView> createState() => _PluginRenderViewState();
}

class _PluginRenderViewState extends ConsumerState<PluginRenderView>
    with WidgetsBindingObserver {
  static const Duration _pageLoadTimeout = Duration(seconds: 20);

  Timer? _loadTimer;
  bool _isLoading = true;
  String? _errorMessage;

  /// 应用是否处于可见状态（`AppLifecycleState.hidden` 时为 false）。
  bool _appVisible = true;

  /// 窗口是否可见（最小化 / 隐藏到托盘时为 false）。
  ///
  /// 仅 Windows 会翻转（`WindowTrayManager` 只在 Windows setup），其余平台恒 true。
  bool _hwndVisible = windowVisibleNotifier.value;

  /// 重建计数：作为渲染面的 `ValueKey`，递增即重建整个渲染面。
  ///
  /// 不用 `controller.reload()`：Windows 上 WebView 实例创建失败时
  /// `onWebViewCreated` 不触发、controller 恒为 null，reload 是 no-op，
  /// 必须换 key 重建才能重新走环境创建（songloft-org/songloft#271）。
  int _reloadSeq = 0;

  /// 当前引擎。运行时开关在 songloft-org/songloft#341 的后续步骤接入，
  /// 目前恒为 `webView`，行为与抽层前完全一致。
  PluginRenderEngine get _engine => PluginRenderEngine.webView;

  /// 是否需要为独立原生表面做「移出 widget 树以销毁」的处理（#293）。
  bool get _needsHwndUnmount => _engine.usesPlatformView;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowVisibleNotifier.addListener(_onWindowVisibilityChanged);
    _startLoadTimer();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    windowVisibleNotifier.removeListener(_onWindowVisibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state != AppLifecycleState.hidden;
    if (_appVisible != visible) {
      setState(() => _appVisible = visible);
    }
  }

  /// 窗口可见性变化（Windows 最小化 / 托盘）：不可见时下一帧把渲染面移出
  /// widget 树以销毁 WebView2 HWND；恢复可见时换 key 重建并重新计时。
  void _onWindowVisibilityChanged() {
    final visible = windowVisibleNotifier.value;
    if (!mounted || _hwndVisible == visible) return;
    setState(() {
      _hwndVisible = visible;
      if (visible) {
        _isLoading = true;
        _errorMessage = null;
        _reloadSeq++;
        _startLoadTimer();
      }
    });
  }

  void _startLoadTimer() {
    _loadTimer?.cancel();
    _loadTimer = Timer(_pageLoadTimeout, () {
      if (!mounted || !_isLoading) return;
      setState(() {
        _isLoading = false;
        _errorMessage = AppLocalizations.of(context).homePluginLoadTimeout;
      });
    });
  }

  void _onLoadStart() {
    if (!mounted) return;
    _startLoadTimer();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
  }

  void _onLoadStop() {
    _loadTimer?.cancel();
    _loadTimer = null;
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = null;
    });
  }

  void _onError(String message) {
    _loadTimer?.cancel();
    _loadTimer = null;
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _reloadSeq++;
    });
    _startLoadTimer();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 刻意不叫 mounted：那会遮蔽 State.mounted。
    final surfaceMounted = !_needsHwndUnmount || _hwndVisible;

    return Stack(
      children: [
        if (_errorMessage != null)
          _buildErrorView(colorScheme)
        else if (surfaceMounted)
          Offstage(offstage: !_appVisible, child: _buildSurface())
        else
          // 窗口不可见：不挂载渲染面，销毁原生 HWND（#293）。
          const SizedBox.expand(),
        if (_isLoading && surfaceMounted)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildSurface() {
    switch (_engine) {
      case PluginRenderEngine.webView:
        return PluginRenderSurfaceWebView(
          key: ValueKey(_reloadSeq),
          url: widget.url,
          theme: widget.theme,
          useHybridComposition: widget.useHybridComposition,
          onLoadStart: _onLoadStart,
          onLoadStop: _onLoadStop,
          onError: _onError,
          onControllerReady: widget.onControllerReady,
        );
      case PluginRenderEngine.webF:
        return PluginRenderSurfaceWebF(
          key: ValueKey(_reloadSeq),
          url: widget.url,
          theme: widget.theme,
          onLoadStart: _onLoadStart,
          onLoadStop: _onLoadStop,
          onError: _onError,
          onControllerReady: widget.onControllerReady,
        );
    }
  }

  Widget _buildErrorView(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).homePluginLoadFailed,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ??
                  AppLocalizations.of(context).homePluginUnknownError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context).commonRetry),
          ),
        ],
      ),
    );
  }
}
