import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/storage/secure_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import 'plugin_theme_utils.dart';
import 'render/plugin_render_controller.dart';
import 'render/plugin_render_view.dart';

/// 插件全屏页面（原生平台实现）
/// 在应用内加载插件 HTML 页面，通过 URL 参数传递 JWT token。
///
/// 渲染、加载态、超时与错误处理全部委托 [PluginRenderView]；本页只负责全屏
/// 特有的壳：AppBar（返回 / 关闭 / 在浏览器中打开）与路由级返回键处理。
class PluginWebViewPage extends ConsumerStatefulWidget {
  final String pluginUrl;
  final String pluginName;

  const PluginWebViewPage({
    super.key,
    required this.pluginUrl,
    required this.pluginName,
  });

  @override
  ConsumerState<PluginWebViewPage> createState() => _PluginWebViewPageState();
}

class _PluginWebViewPageState extends ConsumerState<PluginWebViewPage> {
  PluginRenderController? _renderController;

  String _buildPluginUrl(String theme) {
    final token = SecureStorageService.cachedAccessToken ?? '';
    final uri = Uri.parse(widget.pluginUrl);
    final query = Map<String, String>.from(uri.queryParameters)
      ..['theme'] = theme;
    if (token.isNotEmpty) {
      query['access_token'] = token;
    }
    return ensurePluginPathTrailingSlash(
      uri.replace(queryParameters: query).toString(),
    );
  }

  /// 页面内还有历史就先回退，否则退出本路由。
  Future<void> _goBack() async {
    if (await (_renderController?.goBackIfPossible() ?? Future.value(false))) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final brightness = MediaQuery.of(context).platformBrightness;
    final theme = resolveEffectiveTheme(themeMode, brightness);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.pluginName),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: AppLocalizations.of(context).homePluginClose,
              onPressed: () => Navigator.of(context).pop(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: AppLocalizations.of(context).homePluginOpenInBrowser,
              onPressed:
                  () => launchUrl(
                    Uri.parse(_buildPluginUrl(theme)),
                    mode: LaunchMode.externalApplication,
                  ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: PluginRenderView(
            url: _buildPluginUrl(theme),
            theme: theme,
            onControllerReady: (controller) => _renderController = controller,
          ),
        ),
      ),
    );
  }
}
