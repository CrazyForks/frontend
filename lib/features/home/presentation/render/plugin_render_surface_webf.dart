import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webf/webf.dart';

import '../../../player/domain/player_state.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../plugin_host_dispatch.dart';
import 'plugin_render_controller.dart';
import 'plugin_render_fonts.dart';

/// 宿主桥的 MethodChannel 方法名（JS 侧 `common.js` 必须一致）。
const String _kHostCallMethod = 'songloftHost';
const String _kRequestBackMethod = 'requestBack';

/// WebF 渲染面（songloft-org/songloft#341）。
///
/// 与 `PluginRenderSurfaceWebView` 对等：只管渲染面、宿主桥、主题下推；
/// 加载态 / 超时 / 错误 UI / 重试归 `PluginRenderView`。
///
/// 分发逻辑复用传输无关的 [PluginHostDispatcher]（与 InAppWebView、Web iframe
/// 三条链路共用），所以本文件只实现「传输」这一层。
class PluginRenderSurfaceWebF extends ConsumerStatefulWidget {
  final String url;
  final String theme;
  final VoidCallback onLoadStart;
  final VoidCallback onLoadStop;
  final void Function(String message) onError;
  final void Function(PluginRenderController controller) onControllerReady;

  const PluginRenderSurfaceWebF({
    super.key,
    required this.url,
    required this.theme,
    required this.onLoadStart,
    required this.onLoadStop,
    required this.onError,
    required this.onControllerReady,
  });

  @override
  ConsumerState<PluginRenderSurfaceWebF> createState() =>
      _PluginRenderSurfaceWebFState();
}

class _PluginRenderSurfaceWebFState
    extends ConsumerState<PluginRenderSurfaceWebF>
    implements PluginRenderController {
  /// 限额只需设一次，且必须在创建任何 controller 之前。
  ///
  /// 刻意不用默认的 `maxAliveInstances: 5`：插件 Tab 数可能超过 5，而超出
  /// `maxAliveInstances` 会 **dispose** controller，之后重新挂载虽然会自动重建
  /// （用缓存的初始化参数重放），但页面内 JS 状态归零、还会闪一下 loading。
  /// 超出 `maxAttachedInstances` 只是 detach、状态保留，代价小得多。
  static bool _managerConfigured = false;

  static void _ensureManagerConfigured() {
    if (_managerConfigured) return;
    _managerConfigured = true;
    WebFControllerManager.instance.initialize(
      const WebFControllerManagerConfig(
        maxAliveInstances: 8,
        maxAttachedInstances: 3,
      ),
    );
  }

  WebFController? _controller;
  PluginHostDispatcher? _dispatcher;
  String? _lastPushedStateSig;
  bool _pageReady = false;

  /// controller 缓存键。用**去掉 query 的 URL**：`?theme=` 会随主题变化，
  /// 带上它会让切主题变成「换了一个插件」从而整页重载。
  late final String _controllerName =
      'plugin:${Uri.parse(widget.url).replace(query: '').toString()}';

  PluginHostDispatcher get _hostDispatcher =>
      _dispatcher ??= PluginHostDispatcher(ref, platformName: _platformName());

  @override
  void didUpdateWidget(covariant PluginRenderSurfaceWebF oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 首屏主题靠 URL 的 ?theme= 参数，这里只处理运行中的切换。
    if (oldWidget.theme != widget.theme && _pageReady) {
      _pushToPage("{type:'songloft-theme',theme:'${widget.theme}'}");
    }
  }

  // ── PluginRenderController ──────────────────────────────────────────
  /// WebF 没有 `canGoBack`（`module/history.dart` 的 case 列表里只有
  /// length/state/back/forward/pushState/replaceState/go，controller 上也没有
  /// `goBack()`），所以「能否回退」只能问页面自己：`common.js` 注册的
  /// `requestBack` handler 判断 `history.length` 后回报是否已消费。
  @override
  Future<bool> goBackIfPossible() async {
    final controller = _controller;
    if (controller == null || !_pageReady) return false;
    try {
      final result = await controller.javascriptChannel.invokeMethod(
        _kRequestBackMethod,
        null,
      );
      return _decodeBool(result);
    } catch (_) {
      // 页面没注册 handler（老插件 / common.js 未更新）或调用超时：
      // 当作「没消费」，由宿主退出路由，不能把返回键卡死。
      return false;
    }
  }

  /// WebF 是纯 Flutter 渲染、没有独立原生表面，不存在「原生 WebView 在系统层面
  /// 抢走键盘焦点」的问题（那是 #293 一类 platform view 才有的），故为空实现。
  @override
  void clearFocus() {}

  // ── 桥 ──────────────────────────────────────────────────────────────
  String _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  /// JS → Dart。
  ///
  /// 请求体在两端都做 JSON 字符串化：WebF 的 method channel 对复杂对象的
  /// 序列化形态没有稳定契约，字符串是唯一两端都确定的载体。因此这里对
  /// String 与 Map 都做兼容解析，不假定其中一种。
  Future<dynamic> _onMethodCall(String method, dynamic args) async {
    if (method != _kHostCallMethod) return null;
    final req = _decodeRequest(args);
    if (req == null) {
      return jsonEncode({'ok': false, 'error': 'malformed host call payload'});
    }
    final result = await _hostDispatcher.handleCall(req);
    return jsonEncode(result);
  }

  static Map<String, dynamic>? _decodeRequest(dynamic args) {
    // JS 侧 invokeMethod(method, payload) 会把参数摊成 List
    dynamic payload = args;
    if (payload is List) {
      if (payload.isEmpty) return null;
      payload = payload.first;
    }
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        return null;
      }
    }
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return null;
  }

  static bool _decodeBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
      try {
        return jsonDecode(value) == true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Dart → JS。沿用既有的 `window.postMessage` 协议 —— WebF 的
  /// `window.postMessage` 是同窗口自发自收（直接在同一 window 上 dispatch
  /// MessageEvent），所以 `common.js` 的**接收侧一行都不用改**。
  void _pushToPage(String messageLiteral) {
    // evaluateJavaScripts 返回 Future<void>，拿不到返回值；这里两处推送
    // 都不需要返回值。
    _controller?.view.evaluateJavaScripts(
      'window.postMessage($messageLiteral,"*")',
    );
  }

  void _listenPlayerState() {
    ref.listen<PlayerState>(playerStateProvider, (prev, next) {
      final sig = _hostDispatcher.stateSignature(next);
      if (sig == _lastPushedStateSig) return;
      _lastPushedStateSig = sig;
      if (!_pageReady) return;
      final json = jsonEncode(_hostDispatcher.stateToJson(next));
      _pushToPage("{type:'songloft-player-state',state:$json}");
    });
  }

  // ── 渲染 ────────────────────────────────────────────────────────────
  WebFController _createController() {
    _ensureManagerConfigured();
    widget.onLoadStart();
    final controller = WebFController(
      // 关掉 WebF 自己的 HTTP 缓存（songloft-org/songloft#341）。
      //
      // 实测日志里反复出现 `WebF.HttpCache Cache validation failed / Missing
      // cache files`，并伴随 `Bytecode are not valid to execute.` —— 因果链是：
      // 缓存吐出残缺的脚本内容 → dumpQuickjsByteCode 编译出无效字节码 →
      // script.dart 的 isBytecode 分支**没有回退**（同为字节码执行的
      // to_native.dart 那条有「失败即删缓存、退回原始 JS」的自愈），于是脚本
      // 静默不执行、整个插件页功能缺失。
      //
      // 代价极小：插件静态资源本来就是内容哈希文件名（app.bundle.<hash>.js），
      // 缓存命中率的收益有限，而缓存损坏的代价是整页不可用。
      networkOptions: const WebFNetworkOptions(enableHttpCache: false),
      onLoad: (_) {
        _pageReady = true;
        widget.onLoadStop();
      },
      onLoadError: (error, stack) {
        _pageReady = false;
        widget.onError(error.message);
      },
      // 页面内的 JS 异常必须落日志。
      //
      // 实测教训（songloft-org/songloft#341）：WebF 的
      // `Bytecode are not valid to execute.` 是**次级症状** —— 前面有未捕获的
      // JS 异常污染了 QuickJS 上下文，之后的脚本编译才整体失败。而那条报错既不
      // 带 URL 也不带原始异常，只看它无法归因。没有这里的转发，用户日志里就只
      // 剩下那句无用的字节码报错，真正的第一现场丢失。
      onJSError: (message) {
        debugPrint('[plugin][js-error] $message');
      },
    );
    // onJSLog 是字段而非构造参数，只能构造后赋值。
    // 插件页的 console 输出同样要能进日志，否则排查只能靠猜。
    controller.onJSLog = (level, message) {
      debugPrint('[plugin][console] $message');
    };
    controller.javascriptChannel.onMethodCall = _onMethodCall;
    _controller = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    _listenPlayerState();

    return FutureBuilder<void>(
      // 图标字体必须在渲染面出字之前注册好，否则首屏图标是豆腐块。
      // ensureLoaded 幂等，只有首次真正做事。
      future: PluginRenderFonts.ensureLoaded(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.expand();
        }
        return WebF.fromControllerName(
          controllerName: _controllerName,
          bundle: WebFBundle.fromUrl(widget.url),
          createController: _createController,
          onControllerCreated: (controller) {
            // 被淘汰后重建时 createController 不一定再跑，这里兜住引用与桥。
            _controller = controller;
            controller.javascriptChannel.onMethodCall = _onMethodCall;
            widget.onControllerReady(this);
          },
          loadingWidget: const SizedBox.expand(),
          errorBuilder: (context, error) {
            // 交给 PluginRenderView 统一的错误 UI，这里不自绘。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onError(error?.toString() ?? 'WebF error');
            });
            return const SizedBox.expand();
          },
        );
      },
    );
  }
}
