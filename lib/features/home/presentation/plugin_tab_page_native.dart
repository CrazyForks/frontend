import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../core/storage/secure_storage.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import 'plugin_theme_utils.dart';
import 'render/plugin_render_controller.dart';
import 'render/plugin_render_view.dart';

/// 插件 Tab 页面（原生平台实现）
/// 在 Shell 内嵌入插件页展示，底部导航栏保持可见。
///
/// 渲染、加载态、超时与错误处理全部委托 [PluginRenderView]；本页只负责 Tab
/// 特有的壳：URL 拼装、返回键接管、切走时释放焦点。
class PluginTabPage extends ConsumerStatefulWidget {
  final String entryPath;
  final bool isActive;

  const PluginTabPage({
    super.key,
    required this.entryPath,
    this.isActive = true,
  });

  @override
  ConsumerState<PluginTabPage> createState() => _PluginTabPageState();
}

class _PluginTabPageState extends ConsumerState<PluginTabPage> {
  PluginRenderController? _renderController;

  @override
  void didUpdateWidget(covariant PluginTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      // 原生 WebView 即使被 Offstage 隐藏仍可在系统层面持有键盘焦点，
      // 释放焦点以防止抢夺 Flutter 输入法上下文。
      _renderController?.clearFocus();
    }
  }

  String _buildPluginUrl(String theme) {
    final token = SecureStorageService.cachedAccessToken ?? '';
    final uri = Uri.parse(
      '${AppConfig.baseUrl}${AppConfig.basePath}/api/v1/jsplugin/${widget.entryPath}',
    );
    final query =
        Map<String, String>.from(uri.queryParameters)
          ..['embed'] = ''
          ..['theme'] = theme;
    if (token.isNotEmpty) {
      query['access_token'] = token;
    }
    return uri.replace(queryParameters: query).toString();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final brightness = MediaQuery.of(context).platformBrightness;
    final theme = resolveEffectiveTheme(themeMode, brightness);

    // 接管 Android 硬件返回键：优先让页面内部后退，无更多历史时再退出应用
    // （songloft-org/songloft#273）。前提是 shell 子 Navigator 保持挂载，
    // 返回键才能分发到本页 PopScope——保活逻辑见 shell_layout.dart。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await (_renderController?.goBackIfPossible() ??
            Future.value(false))) {
          return;
        }
        await SystemNavigator.pop();
      },
      child: SafeArea(
        bottom: false,
        child: PluginRenderView(
          url: _buildPluginUrl(theme),
          theme: theme,
          // Tab 靠 shell 层 Offstage 保活，Hybrid Composition 下反复切换会让
          // overlay 重建异常、把底部 NavigationBar 抹成黑块，故用 Virtual
          // Display（songloft-org/songloft#273）。
          useHybridComposition: false,
          onControllerReady: (controller) => _renderController = controller,
        ),
      ),
    );
  }
}
