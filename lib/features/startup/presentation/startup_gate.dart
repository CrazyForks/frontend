import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../config/app_config.dart';
import '../../../core/backend/embedded_backend_service.dart';
import '../../../core/backend/run_mode_provider.dart';
import '../../../core/network/base_url_provider.dart';
import '../../../core/network/server_entry.dart';
import '../../../core/network/server_probe.dart';
import '../../../core/network/servers_provider.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../l10n/app_localizations.dart';

/// 启动时显示一个简单 Splash，期间完成：
/// 1. 读取持久化的服务器列表
/// 2. 并行探测可达性（最长 2.5s）
/// 3. 选优先级最高的成功项写入 baseUrlProvider；全失败则 fallback 列表首项
/// 4. 设置 probeOutcomeProvider 供首屏 SnackBar 提示
///
/// embedded 模式不做任何探测，直接渲染 child。
/// local 模式启动内嵌 Go 后端，连接 localhost 并自动登录。
class StartupGate extends ConsumerStatefulWidget {
  final Widget child;
  const StartupGate({super.key, required this.child});

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

/// 启动 Splash 的提示阶段。文案在 [build] 中通过 [AppLocalizations] 解析，
/// 因为 Splash 的 MaterialApp 在 SongloftApp 之外，设置文案时尚无可用的
/// BuildContext / 全局 l10n。
enum _StartupHint {
  starting,
  startingLocalBackend,
  connectingLocalBackend,
  connectingTo,
}

class _StartupGateState extends ConsumerState<StartupGate>
    with WidgetsBindingObserver {
  bool _ready = false;
  _StartupHint _hint = _StartupHint.starting;
  String _connectingTarget = '';

  /// 上次执行 Web 重绘恢复的时间，用于节流（避免频繁切后台抖动时连续重建整树）。
  DateTime _lastWebRepaint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
    }
    if (AppConfig.isEmbedded) {
      _ready = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb || state != AppLifecycleState.resumed) return;
    _forceWebRepaint();
  }

  /// Web 切后台回前台的渲染恢复。
  ///
  /// Android Chrome 后台会丢弃标签页的 WebGL context。web 构建钉在含引擎修复
  /// flutter/flutter#185116 的 beta 3.47，该修复只去掉 `_handledContextLostEvent`
  /// 的 `late`（避免 `webglcontextlost` 同步触发时的 LateInitializationError 崩溃
  /// = 切后台回来黑屏），引擎(`canvaskit/surface.dart` onContextLost)随后只重建
  /// GrContext/SkSurface，**不会重传已解码位图的 GPU 纹理**。
  ///
  /// 后果分两类：
  /// - **矢量内容**（渐变/纯色/占位）每帧从 Picture 重新录制光栅化，自动恢复；
  /// - **封面等位图**走 cached_network_image_web 的 WebCodecs VideoFrame 惰性纹理，
  ///   其源在后台被浏览器回收后，重绘时从死源惰性重传出全零像素 → **偶发纯黑封面**
  ///   （errorWidget 捕获不到，因为解码在框架层是“成功”的，失败发生在 GPU 绘制层）。
  ///
  /// 修复：resume 时驱逐图片缓存（含活图，保证后续 resolve 缓存未命中），再
  /// `reassembleApplication()` 让每个 Image 重新 resolve → 走 flutter_cache_manager
  /// 字节缓存重新解码 → 新建 VideoFrame → 上传到重建后的 GrContext。缺一不可：只清
  /// 缓存 widget 不会 re-resolve（复用死图）；只 reassemble 又会命中旧缓存（复用死图）。
  /// 单纯 `scheduleFrame` 只重录矢量、对死纹理无效。
  void _forceWebRepaint() {
    if (!mounted) return;

    // 节流：切后台频繁抖动时避免连续重建整棵树，退化为轻量补帧。
    final now = DateTime.now();
    if (now.difference(_lastWebRepaint) < const Duration(seconds: 2)) {
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _lastWebRepaint = now;

    // 1) 驱逐图片缓存（含活图）。clear() 只清 keepAlive 缓存、不动活图，且清缓存
    //    本身不触发重解码，故必须同时 clearLiveImages()。
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();

    // 2) 强制整棵树重新 resolve 图片（否则已挂载 widget 复用旧的死 ui.Image）。
    //    延后到下一帧，避开 resume 回调期间的构建阶段。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WidgetsBinding.instance.reassembleApplication();
    });

    // 3) 兜底补几帧，确保矢量层与重建后的树都被重绘。
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) WidgetsBinding.instance.scheduleFrame();
      });
    }
  }

  Future<void> _bootstrap() async {
    try {
      await ref.read(runModeProvider.notifier).ensureLoaded();
      await ref.read(localMusicDirProvider.notifier).ensureLoaded();
      final runMode = ref.read(runModeProvider);

      // 仅在打包了内嵌后端的构建里才走本地模式；非 bundled 客户端即便
      // 残留了 run_mode=local（如同容器装过 bundled 版）也一律回退远程，
      // 与 backend_lifecycle / servers_page 的 hasEmbeddedBackend 守卫保持一致。
      if (runMode == RunMode.local && !kIsWeb && AppConfig.hasEmbeddedBackend) {
        await _bootstrapLocal();
      } else {
        await _bootstrapRemote();
      }
    } catch (e) {
      debugPrint('[StartupGate] 启动初始化失败: $e');
      ref.read(probeOutcomeProvider.notifier).set(ProbeOutcome.fallbackUsed);
    } finally {
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    }
  }

  Future<void> _bootstrapLocal() async {
    setState(() => _hint = _StartupHint.startingLocalBackend);

    final musicDir = await EmbeddedBackendService.resolveMusicDir(
      ref.read(localMusicDirProvider),
    );
    if (musicDir == null || musicDir.isEmpty) {
      debugPrint('[StartupGate] 本地模式未配置音乐目录，回退到远程模式');
      await ref.read(runModeProvider.notifier).set(RunMode.remote);
      await _bootstrapRemote();
      return;
    }
    await ref.read(localMusicDirProvider.notifier).set(musicDir);

    await EmbeddedBackendService.ensureStoragePermission();

    final dataDir = (await getApplicationSupportDirectory()).path;
    final port = await EmbeddedBackendService.start(
      dataDir: dataDir,
      musicDir: musicDir,
    );

    final baseUrl = 'http://127.0.0.1:$port';
    ref.read(baseUrlProvider.notifier).set(baseUrl);

    setState(() => _hint = _StartupHint.connectingLocalBackend);

    // 等待后端 health 端点就绪
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
    for (var i = 0; i < 10; i++) {
      try {
        final resp = await dio.get('$baseUrl/api/v1/health');
        if (resp.statusCode == 200) break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    dio.close();

    // 尝试恢复本地 session，有效则跳过 auto-login
    final storage = SecureStorageService();
    final restored = await storage.restoreWallet(
      SecureStorageService.localWalletKey,
    );
    if (!restored || await storage.isAccessTokenExpired()) {
      await _autoLogin(baseUrl);
    }

    ref.read(probeOutcomeProvider.notifier).set(ProbeOutcome.success);
  }

  Future<void> _autoLogin(String baseUrl) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
        ),
      );
      final resp = await dio.post(
        '${AppConfig.apiPrefix}/auth/login',
        data: {'username': 'admin', 'password': 'admin'},
      );
      if (resp.statusCode == 200 && resp.data != null) {
        final storage = SecureStorageService();
        await storage.saveTokens(
          accessToken: resp.data['access_token'] ?? '',
          refreshToken: resp.data['refresh_token'] ?? '',
          expiresIn: resp.data['expires_in'] ?? 3600,
          walletKey: SecureStorageService.localWalletKey,
        );
        debugPrint('[StartupGate] 本地模式自动登录成功');
      }
      dio.close();
    } catch (e) {
      debugPrint('[StartupGate] 本地模式自动登录失败: $e');
    }
  }

  Future<void> _bootstrapRemote() async {
    final servers = await ref.read(serversProvider.future);

    if (servers.isEmpty) {
      ref.read(probeOutcomeProvider.notifier).set(ProbeOutcome.noServers);
    } else if (servers.length == 1) {
      final url = servers.first.url;
      ref.read(baseUrlProvider.notifier).set(url);
      // 恢复该服务器的 wallet
      final storage = SecureStorageService();
      await storage.restoreWallet(SecureStorageService.walletKey(url));
      ref.read(probeOutcomeProvider.notifier).set(ProbeOutcome.success);
    } else {
      setState(() {
        _hint = _StartupHint.connectingTo;
        _connectingTarget = _describe(servers.first);
      });

      final picked = await ServerProbe.pickFirstReachable(servers);
      final chosen = picked ?? servers.first;
      ref.read(baseUrlProvider.notifier).set(chosen.url);
      // 恢复选中服务器的 wallet
      final storage = SecureStorageService();
      await storage.restoreWallet(SecureStorageService.walletKey(chosen.url));
      ref
          .read(probeOutcomeProvider.notifier)
          .set(
            picked == null ? ProbeOutcome.fallbackUsed : ProbeOutcome.success,
          );
    }
  }

  String _describe(ServerEntry e) {
    if (e.name.isNotEmpty) return e.name;
    return e.displayName;
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          final hintText = switch (_hint) {
            _StartupHint.starting => l10n.startupStarting,
            _StartupHint.startingLocalBackend => l10n.startupStartingLocalBackend,
            _StartupHint.connectingLocalBackend =>
              l10n.startupConnectingLocalBackend,
            _StartupHint.connectingTo =>
              l10n.startupConnectingTo(_connectingTarget),
          };
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/app_icon.png',
                    width: 64,
                    height: 64,
                    semanticLabel: 'Songloft',
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(hintText),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
