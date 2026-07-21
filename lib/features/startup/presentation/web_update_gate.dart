import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../core/router/app_router.dart' show rootNavigatorKey;
import '../../../core/utils/web_cache_clearer.dart' as web_cache;
import '../../../core/utils/web_version_checker.dart' as web_version;
import '../../../l10n/app_localizations.dart';

/// Web 端启动时检测「运行中的前端 bundle」是否已落后于「服务端当前部署的
/// 前端 bundle」。落后时弹窗提示，用户点「立即刷新」后清理浏览器缓存并 reload，
/// 避免服务端更新后浏览器仍加载旧缓存产物。
///
/// 判据为前端自服务的 version.json（构建时写入产物根目录），与烤进 bundle 的
/// [AppConfig.frontendVersion] / [AppConfig.frontendBuildTime] 自比，与后端版本
/// 解耦（后端 BuildTime 在 CI 里晚于前端产物单独生成，直接比会误报）。
///
/// 仅 Web 生效：原生端 [build] 直接返回 child（零开销），检测逻辑也经 stub 短路。
class WebUpdateGate extends StatefulWidget {
  final Widget child;
  const WebUpdateGate({super.key, required this.child});

  @override
  State<WebUpdateGate> createState() => _WebUpdateGateState();
}

class _WebUpdateGateState extends State<WebUpdateGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    if (_checked) return;
    _checked = true;

    // 本地 flutter run 无 version.json 且构建时间未注入，无从判断，跳过。
    if (AppConfig.frontendBuildTime == 'unknown') return;

    final remote = await web_version.fetchDeployedVersion();
    if (remote == null) return;

    // 与运行中 bundle 一致 → 无需提示。
    if (remote.version == AppConfig.frontendVersion &&
        remote.buildTime == AppConfig.frontendBuildTime) {
      return;
    }

    // 本会话已为该目标清过一次缓存仍不匹配（SW 顽固），不再重复弹窗防死循环。
    if (web_version.readReloadSentinel() == remote.buildTime) {
      debugPrint(
        '[WebUpdateGate] 已清缓存刷新但版本仍不匹配，跳过重复提示 '
        '(deployed=${remote.version}/${remote.buildTime})',
      );
      return;
    }

    if (!mounted) return;
    await _promptUpdate(remote.buildTime);
  }

  Future<void> _promptUpdate(String targetBuildTime) async {
    // 用根 Navigator 的 context 弹窗：本 widget 位于 MaterialApp.builder，其自身
    // context 在路由 Navigator 之上，直接 showDialog 找不到 Navigator。
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final confirmed = await showDialog<bool>(
      context: navContext,
      barrierDismissible: true,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l10n.webUpdateAvailableTitle),
          content: Text(l10n.webUpdateAvailableContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.webUpdateAvailableLater),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.webUpdateAvailableRefresh),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // 先落 sentinel 再清理+刷新：刷新后若仍不匹配，下次检测据此不再弹窗。
    web_version.writeReloadSentinel(targetBuildTime);
    try {
      await web_cache.clearBrowserCache();
    } catch (_) {}
    web_cache.reloadPage();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
