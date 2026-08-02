import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webf/webf.dart';

import '../../../player/domain/player_state.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../plugin_host_dispatch.dart';
import 'elements/songloft_custom_elements.dart';
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
  /// WebF 的两项**进程级**一次性设置。两者都必须在创建任何 controller 之前
  /// 完成，所以放在同一个入口里一次做完。
  static bool _processSetupDone = false;

  static void _ensureWebFProcessSetup() {
    if (_processSetupDone) return;
    _processSetupDone = true;

    // ① 实例限额。
    //
    // 刻意不用默认的 `maxAliveInstances: 5`：插件 Tab 数可能超过 5，而超出
    // `maxAliveInstances` 会 **dispose** controller，之后重新挂载虽然会自动重建
    // （用缓存的初始化参数重放），但页面内 JS 状态归零、还会闪一下 loading。
    // 超出 `maxAttachedInstances` 只是 detach、状态保留，代价小得多。
    WebFControllerManager.instance.initialize(
      const WebFControllerManagerConfig(
        maxAliveInstances: 8,
        maxAttachedInstances: 3,
      ),
    );

    // ② 自定义元素（`<songloft-progress-ring>` 等）。
    //
    // 与限额同一类约束：写的是进程级全局注册表、重复注册会抛、且必须早于
    // controller —— controller 初始化期就会预取 widget 元素的形状与属性默认值，
    // 注册晚了那一页只能拿到 `_UnknownHTMLElement`。详见
    // `elements/songloft_custom_elements.dart` 的头注释。
    SongloftCustomElements.ensureRegistered();
  }

  WebFController? _controller;
  PluginHostDispatcher? _dispatcher;
  String? _lastPushedStateSig;
  bool _pageReady = false;

  /// 最近一次从 `MediaQuery` 读到的安全区，与最近一次**已推给页面**的签名。
  ///
  /// 分成两个字段而不是一个：build() 每次都会更新前者（此时页面可能还没 ready，
  /// 推不出去），`_pageReady` 转 true 时要拿它补推首屏值。
  EdgeInsets _safeAreaInsets = EdgeInsets.zero;
  String? _lastPushedInsetsSig;

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

  /// 安全区（刘海屏 / 圆角屏 / 手势条）下推 —— WebF 不实现
  /// `env(safe-area-inset-*)`（songloft-org/songloft#341）。
  ///
  /// WebF 里 `css/keywords.dart` 那 6 个 `SAFE_AREA_INSET*` / `ENV` 常量是全库
  /// 无引用的死常量，连解析入口都没有，所以插件页写 `env()` 在 WebF 下会顶到状态栏
  /// 或被下巴切掉。宿主这边负责把真实 inset 注入成 CSS 变量 `--sl-safe-*`，
  /// 插件侧统一写 `var(--sl-safe-bottom)`（默认值与三种环境下的取值见
  /// `internal/jsplugin/assets/common.css` 里那段注释）。
  ///
  /// 用 `viewPadding` 而不是 `padding`：前者是「不扣掉键盘遮挡」的安全区，
  /// 与浏览器 `env(safe-area-inset-*)` 的语义一致（软键盘弹出时 `env()` 不变）。
  /// 注意插件页外层是 `SafeArea`（`plugin_tab_page_native.dart` 是
  /// `SafeArea(bottom: false)`），而 Flutter 的 `MediaQuery.removePadding` 会把
  /// `viewPadding` 一并按已消费的 `padding` 扣减，所以这里读到的正是**剩给页面
  /// 自己处理**的那部分 —— 上层已经让开的边不会被重复内缩。
  void _syncSafeArea(EdgeInsets insets) {
    _safeAreaInsets = insets;
    if (!_pageReady) return;
    final sig = _insetsSignature(insets);
    // 去重：MediaQuery 依赖变化会让 build() 反复跑（转屏、进退全屏、键盘），
    // 不去重就是每帧一次 evaluateJavaScripts。
    if (sig == _lastPushedInsetsSig) return;
    _lastPushedInsetsSig = sig;
    _pushToPage("{type:'songloft-safe-area',insets:$sig}");
  }

  /// 既当去重签名又当推送载荷 —— 两者用同一份字符串，不可能不一致。
  static String _insetsSignature(EdgeInsets i) {
    String n(double v) => v.toStringAsFixed(2);
    return '{top:${n(i.top)},right:${n(i.right)},'
        'bottom:${n(i.bottom)},left:${n(i.left)}}';
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
    _ensureWebFProcessSetup();
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
        // 安全区必须在这里补推一次，两个理由：
        //   ① 首屏 —— build() 早于 onLoad，那时 `_pageReady` 还是 false 推不出去；
        //   ② 重挂 —— 超 `maxAliveInstances` 被 dispose 后重建时页面 JS 状态归零，
        //      「注入过一次就不管」会让重挂后的页面永久丢掉安全区。
        // 清签名而不是直接推：让 `_syncSafeArea` 里那条去重判断照常生效。
        _lastPushedInsetsSig = null;
        _syncSafeArea(_safeAreaInsets);
        widget.onLoadStop();
      },
      onLoadError: (error, stack) {
        _pageReady = false;
        _lastPushedInsetsSig = null;
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
    // 在 build() 里读，是为了建立 MediaQuery 依赖：转屏 / 进退全屏 / 键盘弹出
    // 都会让本 widget 重建，从而自动重推。去重在 `_syncSafeArea` 内部做。
    _syncSafeArea(MediaQuery.viewPaddingOf(context));

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
