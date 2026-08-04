import 'dart:async';
import 'dart:convert';
import 'dart:io';

// gestures：PointerScrollEvent 只在这里导出（material.dart 没带出来），
// 合成滚轮滚动要用，见 [_synthScroll]。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webf/webf.dart';

// 产品代码，**不是探针自己的副本**。
//
// `lib/elements/` 在镜像里不存在，由 entrypoint.sh 每次运行时从
// `/repo/songloft-player/lib/features/home/presentation/render/elements/`
// 原样拷进来（拷贝前会校验源目录存在，缺了直接 exit 1）。这样探针编译的就是
// 产品实现本身 —— 探针与产品是两个 package，Dart 不能跨 package 相对 import，
// 「拷贝 + 校验」是唯一能保证「测的是产品那一份」的做法。
// 代价：产品的 `elements/` 目录必须只依赖 flutter 与 webf（那边的头注释里
// 写了这条约束），否则探针编不过。
import 'elements/songloft_custom_elements.dart';

/// WebF 渲染能力探针（songloft-org/songloft#341）。
///
/// 只做一件事：把 `--dart-define=PROBE_URL=...` 指定的页面用 WebF 渲染出来，
/// 供容器外抓屏比对。**不是**产品代码，不参与发布。
///
/// 关键设计：不加任何 Flutter 侧脚手架（AppBar / padding / SafeArea），
/// 让截图里除了 WebF 的输出之外没有别的东西，避免误判是谁渲染的。
///
/// API 注意：`WebF(...)` 是 `@protected` 的私有构造（`widget/webf.dart:206`
/// `const WebF._`），**不能直接 new**。唯一公开挂载入口是静态方法
/// `WebF.fromControllerName`（`:227`），它在 controller 不存在时会用
/// `bundle` + `createController` 自动初始化，返回 `AutoManagedWebF`。
/// 非空时，在起 WebF 之前用 Flutter 的 [FontLoader] 把字体注册进引擎字体表。
///
/// 验证「绕开 @font-face」这条补救路径：WebF 的文本最终走 Flutter 的
/// TextStyle.fontFamily，若同名 family 已在引擎里注册，CSS 里那条注定失效的
/// @font-face 就无关紧要了。
const String _fontPreloadDir = String.fromEnvironment('FONT_PRELOAD_DIR');

// family 名必须与 CSS 里的 font-family 完全一致，故写死映射（探针够用）
const Map<String, String> _fontFamilyByFile = {
  'material-symbols-outlined.ttf': 'Material Symbols Outlined',
  'roboto-400.ttf': 'Roboto',
};

Future<void> _preloadFonts() async {
  for (final entry in _fontFamilyByFile.entries) {
    final file = File('$_fontPreloadDir/${entry.key}');
    if (!file.existsSync()) {
      debugPrint('[probe] preload miss: ${file.path}');
      continue;
    }
    final bytes = await file.readAsBytes();
    final loader = FontLoader(entry.value);
    // 注意用 sublistView 而不是 bytes.buffer.asByteData()：后者会把整个底层
    // buffer 交给 Skia（无视视图 offset/length），正是 WebF 的 URL 加载分支
    // （css/font_face.dart:396）踩的坑。
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    debugPrint('[probe] preloaded ${entry.value} (${bytes.length} bytes)');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_fontPreloadDir.isNotEmpty) {
    await _preloadFonts();
  }
  // 限额必须在创建任何 controller 之前定下来。
  WebFControllerManager.instance.initialize(
    const WebFControllerManagerConfig(
      maxAliveInstances: 4,
      maxAttachedInstances: 2,
    ),
  );
  // 自定义元素同理（且这里调的就是产品的注册入口，见文件头 import 处的说明）。
  // 顺序与产品侧 `_ensureWebFProcessSetup()` 一致。
  SongloftCustomElements.ensureRegistered();
  runApp(const ProbeApp());
}

const String _probeUrl = String.fromEnvironment(
  'PROBE_URL',
  defaultValue: 'http://127.0.0.1:58991/probe.html',
);

/// `--dart-define=DIAGNOSE=1` 时，页面加载完成后注入的诊断脚本。
///
/// 存在的理由：探针页可以自己加检查行，但**真实插件页改不了**。要回答「这个
/// 页面在 WebF 里到底算出了什么样式」只能在页面自身上下文里读，再经 console
/// 回传到 flutter.log。Phase 2 逐插件适配会反复用到。
const String _diagnoseJs = r'''
(function () {
  function log() { console.log('[diag] ' + Array.prototype.join.call(arguments, ' ')); }
  var de = document.documentElement;
  log('data-theme =', JSON.stringify(de.getAttribute('data-theme')));
  log('html.className =', JSON.stringify(de.className));
  log('location.search =', JSON.stringify(window.location.search));
  var cs = getComputedStyle(de);
  ['--md-surface', '--md-background', '--md-on-surface'].forEach(function (v) {
    log('var', v, '=', JSON.stringify(cs.getPropertyValue(v)));
  });
  log('body bg =', JSON.stringify(getComputedStyle(document.body).backgroundColor));
  log('styleSheets =', document.styleSheets ? document.styleSheets.length : 'n/a');
  log('SongloftPlugin =', typeof window.SongloftPlugin);
  if (window.SongloftPlugin) {
    log('host.isAvailable =', String(window.SongloftPlugin.host.isAvailable()));
  }
})();
''';

const bool _diagnose = bool.fromEnvironment('DIAGNOSE');

/// 可选的**自定义**诊断脚本，base64 编码后经 `--dart-define=DIAGNOSE_JS_B64=` 传入
/// （`run.sh` 的 `DIAGNOSE_JS=<宿主上的 .js 文件>`）。
///
/// 为什么要 base64：dart-define 的值要穿过 shell → docker -e → flutter build
/// 三层，而诊断脚本里必然有引号、`$`、换行。base64 是唯一不用逐层转义的形态。
///
/// 为什么要「可换」：[_diagnoseJs] 那份是通用的（主题/CSS 变量/宿主桥在不在），
/// 但**每个插件页的判据都不一样**（downloader 要量 6 列 x 坐标与 sticky 表头，
/// miot 要量竖向滑块几何与安全区求值）。这些判据只能在页面自身上下文里读，
/// 而真实插件页改不了 —— 所以脚本必须能从外面换。
const String _diagnoseJsB64 = String.fromEnvironment('DIAGNOSE_JS_B64');

String get _effectiveDiagnoseJs {
  if (_diagnoseJsB64.isEmpty) return _diagnoseJs;
  try {
    return utf8.decode(base64Decode(_diagnoseJsB64));
  } catch (e) {
    debugPrint('[probe] DIAGNOSE_JS_B64 解码失败，退回内置脚本: $e');
    return _diagnoseJs;
  }
}

/// `onLoad` 之外的**兜底注入**延时（秒）。
///
/// `onLoad` 在 `WebF.fromControllerName` 这条挂载路径下**可能永不触发**
/// （`checkCompleted()` 在 `document.hasPendingRequest` 为真时直接 return，
/// `launcher/controller.dart:1734`）—— 探针页因为两个空 `img src` 就是这样。
/// 真实插件页由后端 `stripEmptySrcAttrs` 剥掉空 src 所以**应当**会触发，
/// 但「应当」不是「一定」：任何一张加载不出来的图、任何一个挂住的请求
/// 都会把这个闸永久关上，而表现是「DIAGNOSE=1 却一行 `[diag]` 都没有」，
/// 与「脚本本身报错」完全无法区分。
///
/// 所以改成「onLoad 与定时器谁先到算谁」+ 一次性闸（[_diagnoseInjected]）。
const int _diagnoseFallbackSeconds = 12;
bool _diagnoseInjected = false;

void _injectDiagnose(WebFController c, String why) {
  if (!_diagnose || _diagnoseInjected) return;
  _diagnoseInjected = true;
  debugPrint('[probe] 注入诊断脚本（触发源：$why）');
  c.view.evaluateJavaScripts(_effectiveDiagnoseJs);
}

/// `--dart-define=DRAG_PROBE=true` 时启用合成拖动（songloft-org/songloft#341 Step 3）。
///
/// **默认关。** 探针本体只截图、没有交互驱动能力，而「`<songloft-slider>` 真的能被
/// 拖动」这件事截图证明不了 —— 它必须由真实的 hit-test → Flutter 手势路径走一遍。
/// 但合成指针事件会改变页面状态（滑块位置、插件侧的值），给既有 13 组的截图基线引入
/// 不确定性，所以做成显式开关。
///
/// `bool.fromEnvironment` **只认字面 `"true"`**（`run.sh` 已做归一化，传 1 也行）。
const bool _dragProbe = bool.fromEnvironment('DRAG_PROBE');

/// 页面报上来的一个拖动目标：屏幕矩形 + 轴向 + 起止比例。
class _DragTarget {
  _DragTarget(Map<String, dynamic> m)
    : id = '${m['id']}',
      axis = '${m['axis']}',
      from = (m['from'] as num).toDouble(),
      to = (m['to'] as num).toDouble(),
      rect = Rect.fromLTWH(
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['w'] as num).toDouble(),
        (m['h'] as num).toDouble(),
      );

  final String id;
  final String axis; // 'h' | 'v'
  final double from;
  final double to;
  final Rect rect;

  Offset at(double t) {
    // 主轴上留 4px 内缩，免得起点正好压在 1px 虚线边框上被边框吃掉命中测试
    if (axis == 'v') {
      final double y = rect.top + 4 + (rect.height - 8) * t;
      return Offset(rect.center.dx, y);
    }
    final double x = rect.left + 4 + (rect.width - 8) * t;
    return Offset(x, rect.center.dy);
  }
}

/// 解出 `slDrag` 的载荷。
///
/// JS 侧 `invokeMethod(name, payload)` 会把参数摊成 List，且两端一律走 JSON
/// 字符串 —— WebF 的 method channel 对复杂对象的序列化形态没有稳定契约，字符串是
/// 唯一两端都确定的载体（与产品侧 `_decodeRequest` 同一结论）。
List<_DragTarget> _decodeTargets(dynamic args) {
  dynamic payload = args;
  if (payload is List && payload.isNotEmpty) payload = payload.first;
  if (payload is String) {
    try {
      payload = jsonDecode(payload);
    } catch (e) {
      debugPrint('[probe] slDrag payload not JSON: $e');
      return const <_DragTarget>[];
    }
  }
  if (payload is! List) return const <_DragTarget>[];
  final List<_DragTarget> out = <_DragTarget>[];
  for (final dynamic item in payload) {
    if (item is Map) {
      try {
        out.add(_DragTarget(Map<String, dynamic>.from(item)));
      } catch (e) {
        debugPrint('[probe] slDrag target skipped: $e');
      }
    }
  }
  return out;
}

/// 合成一次「按下 → 分步移动 → 抬起」。
///
/// 为什么是 `WidgetsBinding.handlePointerEvent` 而不是 flutter_test 的
/// `WidgetTester.drag`：探针是一个真实运行的 app（`flutter build linux` 出来的产物），
/// 不在测试框架里。`handlePointerEvent` 是走真实 hit-test 与真实手势竞技场的唯一入口，
/// 所以它测到的正是产品在真机上会遇到的那条路径（含 WebF 的 `RenderWidget.hitTestChildren`
/// 是否真的把命中传下去、WebF 自己那个 TapGestureRecognizer 会不会抢走手势）。
///
/// 三个必须注意的点（都踩过才知道）：
///   ① `position` 要的是**逻辑**像素。容器里 devicePixelRatio 是 1，所以页面
///      `getBoundingClientRect()` 的坐标可以直接用；哪天 DPR 不是 1 就要先除。
///   ② `PointerMoveEvent` **必须带 `delta`**：`DragGestureRecognizer` 累加的是
///      `event.delta`，不给的话位移永远是 0、识别器永远不接受，表现为「按下有反应、
///      拖动没反应」。
///   ③ 每步之间要 `await` 让出事件循环。同一微任务里连着投递，手势竞技场没有机会
///      在中间做出裁决。
Future<void> _synthDrag(_DragTarget t, {int steps = 12}) async {
  const int pointer = 91;
  Offset prev = t.at(t.from);
  WidgetsBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: pointer, position: prev),
  );
  await Future<void>.delayed(const Duration(milliseconds: 32));
  for (int i = 1; i <= steps; i++) {
    final Offset next = t.at(t.from + (t.to - t.from) * (i / steps));
    WidgetsBinding.instance.handlePointerEvent(
      PointerMoveEvent(pointer: pointer, position: next, delta: next - prev),
    );
    prev = next;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  WidgetsBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: pointer, position: prev),
  );
  await Future<void>.delayed(const Duration(milliseconds: 48));
  debugPrint('[probe] dragged ${t.id} ${t.axis} ${t.rect} ${t.from}->${t.to}');
}

/// 合成一次**真实滚轮滚动**（`slScroll`，songloft-org/songloft#341 Step 6）。
///
/// 为什么不能用页面里的 `el.scrollTop = N`：那条路只挪 scroll offset，而
/// `position: sticky` 在 WebF 里是靠滚动通知链重算子项偏移的
/// （`applyStickyChildOffset`）。要判定「sticky 到底成不成」，必须让滚动从
/// **真实指针事件**进来，走与用户手指/滚轮完全相同的那条路 —— 否则
/// 「sticky 没实现」与「程序化 scroll 不触发 sticky 重算」这两种完全不同的结论
/// 无法区分（而它们对插件作者的含义天差地别）。
///
/// 用 `PointerScrollEvent` 而不是合成拖动：WebF 的可滚容器在桌面端由
/// `Listener`/`Scrollable` 消费滚轮，拖动在桌面语义下不滚动（那是移动端的
/// drag-to-scroll），而验证容器是 Linux 桌面。
///
/// ⚠️ 必须先投一个 `PointerHoverEvent` 建立指针位置：`PointerScrollEvent`
/// 的路由依赖当前 hover 命中的那条链，没 hover 过的位置命中链是空的、
/// 滚动事件会被丢弃（表现与「容器不可滚」一模一样）。
Future<void> _synthScroll(Offset at, double dy, {int steps = 8}) async {
  // Added 也要投：Flutter 的 `PointerRouter` 按 pointer id 维护路由表，
  // 只投 hover 在某些版本下建不起 mouse tracker 的注解链。
  WidgetsBinding.instance.handlePointerEvent(
    const PointerAddedEvent(kind: PointerDeviceKind.mouse),
  );
  WidgetsBinding.instance.handlePointerEvent(
    PointerHoverEvent(kind: PointerDeviceKind.mouse, position: at),
  );
  await Future<void>.delayed(const Duration(milliseconds: 120));
  for (int i = 0; i < steps; i++) {
    WidgetsBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: at,
        scrollDelta: Offset(0, dy / steps),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 48));
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  debugPrint('[probe] scrolled at $at by $dy');
}

/// 从 **Dart 侧**推一次安全区，走产品 `_pushToPage()` 的同一条路
/// （songloft-org/songloft#341 Step 5）。
///
/// 探针页第 17 组自己也 postMessage 一轮，但那验的是 `common.js` 的 handler；
/// 产品里真正的发起方是 Dart 的 `evaluateJavaScripts('window.postMessage({...},"*")')`，
/// 那一跳有两件只有真跑才知道的事：① 字面量拼接（尤其嵌套花括号）在 QuickJS 里
/// 能不能过；② `toStringAsFixed(2)` 产出的 `22.00` 这种形态在 JS 侧是不是数字
/// （common.js 的 handler 只接受 `typeof v === 'number'`，字符串会被跳过）。
///
/// 字面量刻意与 `plugin_render_surface_webf.dart` 的 `_insetsSignature` 逐字符同形。
///
/// 容器里 `MediaQuery.viewPadding` 基本是 0（Xvfb 无刘海），所以这里推的是**人为的
/// 非零值**，且与页面那轮刻意不同（bottom 22 而不是 30），否则读数一样就分不清
/// 是谁写进去的。
///
/// 由**页面**在它自己那一轮读完之后经 methodChannel（`slSafeArea`）叫起来，
/// 不用固定延时赌时序 —— 与第 16 组的 `slDrag` 同一个套路。
void _pushSafeAreaFromDart(WebFController c) {
  const EdgeInsets fake = EdgeInsets.fromLTRB(9, 7, 8, 22);
  String n(double v) => v.toStringAsFixed(2);
  final String sig =
      '{top:${n(fake.top)},right:${n(fake.right)},'
      'bottom:${n(fake.bottom)},left:${n(fake.left)}}';
  Future<void>(() async {
    // 每一步都单独打日志 + 单独 try/catch：静默失败会让 flutter.log 里
    // 「什么都没有」，那与「压根没调度」看起来一模一样，无法归因。
    try {
      debugPrint('[probe] safearea pushing from Dart: $sig');
      await c.view.evaluateJavaScripts(
        'window.postMessage({type:\'songloft-safe-area\',insets:$sig},"*")',
      );
      debugPrint('[probe] safearea dart-push returned');
    } catch (e, st) {
      debugPrint('[probe] safearea dart-push threw: $e\n$st');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    try {
      await c.view.evaluateJavaScripts(
        'window.__saReport && window.__saReport();',
      );
    } catch (e) {
      debugPrint('[probe] safearea __saReport threw: $e');
    }
  });
}

/// Step 6 · `window.open` 的**决定性实验**（songloft-org/songloft#341）。
///
/// 问题：WebF 的 `Window.open`（`dom/window.dart:71-74`）在 Dart 侧是有实现的
/// —— 它调 `handleNavigationAction`，而默认 decision handler 无条件返回 `cancel`
/// （`module/navigation.dart:85-106`）。但 `window.open` 的**入口**在 C++ 桥
/// （`bridge/core/frame/window.cc`），那一层不随 pub 包发布，所以
/// 「C++ 到底有没有把调用转发到 Dart 的 binding」**无法从源码核实**。
///
/// 两种情形导向完全不同的修法：
///   A. C++ 转发 → 现状只是被默认策略 cancel 掉 → 装一个 delegate 就够，无需 JS 垫片
///   B. C++ 自己 return 就结束 → Dart 永远不被调到 → 只能 JS 垫片覆写 window.open
///
/// **本探针把两者一次分辨清楚**，不需要跑两轮：
///   - 装 delegate 时先打一条 `[probe] nav delegate installed`（证明装上了）
///   - 收到决策请求时打 `[probe] nav decision target=…`（证明 C++ 真的转发了）
/// 于是 flutter.log 里：
///   installed + decision → **情形 A**
///   installed 但无 decision → **情形 B**（不是「delegate 没装上」）
///   连 installed 都没有 → 探针自己的问题，先修探针
///
/// 一律返回 `cancel`：返回 allow 会让 WebF 自己 `rootController.load(target)`
/// 把整页替换掉（`view_controller.dart:1138-1143`），探针页当场消失、后续读数全丢。
/// 唯一例外是 `#` 锚点 —— `handleNavigationAction` 里 hash 的 pushState +
/// HashChangeEvent 处理**排在 cancel 检查之后**（`:1126-1134`），cancel 掉页内
/// 跳转就不工作了。产品侧同一条逻辑，见
/// `plugin_render_surface_webf.dart` 的 `_createNavigationDelegate()`。
void _installNavigationDelegate(WebFController controller) {
  final delegate = WebFNavigationDelegate();
  delegate.setDecisionHandler((action) async {
    debugPrint(
      '[probe] nav decision target=${action.target} '
      'source=${action.source} type=${action.navigationType}',
    );
    if (action.target.trim().startsWith('#')) {
      return WebFNavigationActionPolicy.allow;
    }
    return WebFNavigationActionPolicy.cancel;
  });
  controller.navigationDelegate = delegate;
  debugPrint('[probe] nav delegate installed');
}

/// Step 6 · `input[type=file]` 桥的**canned 应答**。
///
/// 探针里刻意不接真的 `file_picker`（那会拉起系统文件选择器、在 Xvfb 里
/// 没有可点的东西，且给探针 package 引入产品依赖）。这里回一个固定文件，
/// 目的是把**链路**钉住：JS `input.click()` → common.js 的 file 垫片 →
/// `songloft.host` methodChannel → Dart → 应答 → 垫片派发 `change` →
/// 页面读到 `event.data.files[0].text`。
///
/// 页面那边只要打出 `picked=probe.m3u/8` 就说明整条链路真的通了；
/// 只装上垫片但桥不通时会显示 `change-nodata` 或 `none`，两者可辨。
String _cannedHostReply(String payload) {
  Map<String, dynamic>? req;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) req = Map<String, dynamic>.from(decoded);
  } catch (_) {
    req = null;
  }
  final String ns = '${req?['ns']}';
  final String method = '${req?['method']}';
  debugPrint(
    '[probe] host call ns=$ns method=$method params=${req?['params']}',
  );
  if (ns == 'files' && method == 'pickFile') {
    return jsonEncode({
      'ok': true,
      'data': {
        'files': [
          {'name': 'probe.m3u', 'size': 8, 'text': '#EXTM3U\n'},
        ],
      },
    });
  }
  return jsonEncode({'ok': false, 'error': 'probe: unhandled $ns.$method'});
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        // 白底：图标字形是深色，透明背景抓屏后不好判读
        backgroundColor: Colors.white,
        body: WebF.fromControllerName(
          controllerName: 'probe',
          bundle: WebFBundle.fromUrl(_probeUrl),
          createController: () {
            final controller = WebFController(
              // 与产品代码保持一致：关掉 WebF 的 HTTP 缓存。
              // 缓存吐出残缺脚本 → 编译出无效字节码 → script.dart 的 isBytecode
              // 分支没有回退 → 脚本静默不执行。探针必须复现同一配置，否则测出的
              // 现象与真机不一致（songloft-org/songloft#341）。
              networkOptions: const WebFNetworkOptions(enableHttpCache: false),
              // 加载失败要在截图里看得见，不能只落日志
              onLoadError: (error, stack) {
                debugPrint('[probe] onLoadError: $error\n$stack');
              },
              onJSError: (msg) {
                debugPrint('[probe] onJSError: $msg');
              },
              onLoad: (c) {
                // ⚠️ 这个回调在**本探针页**上实测不会被调用（日志里从来没有
                // 「onLoad fired」）。交接文档里那条「DIAGNOSE=1 却没有 [diag]
                // 输出、原因未查明」就是同一个现象，根因在这里查明了：
                //
                // `onLoad` 由 `controller.checkCompleted()` 触发，而它在
                // `document.hasPendingRequest` 为真时**直接 return**
                // （`launcher/controller.dart:1734`）。本页第 11 组刻意留了两个
                // `<img src="">`，WebF 会把空 src 解析成文档自身 URL 去请求，
                // 拿到 HTML 后解码失败（日志里那两条 `Failed to decode image
                // (mime=text/html)` 就是它），页面因此永远到不了 complete。
                //
                // **这是探针页特有的**：真实插件页由后端 `stripEmptySrcAttrs`
                // 在 injectHTMLHead 阶段就把空 src 剥掉了，不会卡在这一步。
                // 但结论仍然是：探针里任何「页面加载完之后做点什么」都不要挂在
                // onLoad 上 —— 让页面自己在确定的时点经 methodChannel 叫 Dart
                // （`slDrag` / `slSafeArea` 都是这个套路）。
                debugPrint('[probe] onLoad fired');
                _injectDiagnose(c, 'onLoad');
              },
            );
            // onJSLog 是字段而非构造参数，必须构造后赋值。
            // 页面 console 靠它回传，诊断脚本的输出才能落到 flutter.log。
            controller.onJSLog = (level, message) {
              debugPrint('[page] $message');
            };
            // 页面 → Dart 的唯一通道，与产品侧宿主桥同一套机制
            // （`plugin_render_surface_webf.dart` 的 `javascriptChannel.onMethodCall`）。
            // 这里只用来接「滑块的屏幕坐标」，见 [_synthDrag]。
            controller.javascriptChannel.onMethodCall = (method, args) async {
              // 第 18 组：宿主桥（`common.js` 的 invokeViaWebF 走这个方法名）。
              if (method == 'songloftHost') {
                dynamic payload = args;
                if (payload is List && payload.isNotEmpty) {
                  payload = payload.first;
                }
                return _cannedHostReply(payload is String ? payload : '');
              }
              // 第 17 组：页面读完自己那一轮后叫我们推安全区（Step 5）。
              if (method == 'slSafeArea') {
                _pushSafeAreaFromDart(controller);
                return null;
              }
              // 诊断脚本请求一次真实滚轮滚动，见 [_synthScroll]。
              // 载荷 `{"x":..,"y":..,"dy":..}`（同 slDrag：一律走 JSON 字符串，
              // WebF 的 method channel 对复杂对象的序列化形态没有稳定契约）。
              // 滚完回调 `window.__slScrollDone()`，页面据此继续下一步 ——
              // 不用固定延时赌时序。
              if (method == 'slScroll') {
                dynamic p = args;
                if (p is List && p.isNotEmpty) p = p.first;
                Map<String, dynamic> m = <String, dynamic>{};
                if (p is String) {
                  try {
                    final dynamic d = jsonDecode(p);
                    if (d is Map) m = Map<String, dynamic>.from(d);
                  } catch (e) {
                    debugPrint('[probe] slScroll payload not JSON: $e');
                  }
                }
                final double x = (m['x'] as num?)?.toDouble() ?? 0;
                final double y = (m['y'] as num?)?.toDouble() ?? 0;
                final double dy = (m['dy'] as num?)?.toDouble() ?? 300;
                Future<void>(() async {
                  await _synthScroll(Offset(x, y), dy);
                  await controller.view.evaluateJavaScripts(
                    'window.__slScrollDone && window.__slScrollDone();',
                  );
                });
                return null;
              }
              if (method != 'slDrag') return null;
              final List<_DragTarget> targets = _decodeTargets(args);
              debugPrint(
                '[probe] slDrag: ${targets.length} target(s), DRAG_PROBE=$_dragProbe',
              );
              if (!_dragProbe || targets.isEmpty) return null;
              // 刻意**不在这个回调里 await 拖动**：那样会在 JS 侧的 invokeMethod
              // 还挂着的时候反过来 evaluateJavaScripts 回 QuickJS，属于重入。
              // 立刻返回、异步跑，拖完再回调页面。
              Future<void>(() async {
                for (final _DragTarget t in targets) {
                  await _synthDrag(t);
                }
                await controller.view.evaluateJavaScripts(
                  'window.__slDragDone && window.__slDragDone();',
                );
              });
              return null;
            };
            // Step 6：`window.open` 的决定性实验，见 [_installNavigationDelegate]。
            // 必须在 controller 构造**之后**赋值 —— `navigationDelegate` 不是构造
            // 参数（`launcher/controller.dart:799-828` 的参数列表里没有它，上游
            // `navigation.dart:96-103` 文档示例里那个 `WebFController(
            // navigationDelegate: ...)` 是过时/错误的文档）。setter 会顺带同步到
            // 已经建好的 view（`controller.dart:288-294`）。
            _installNavigationDelegate(controller);
            // 诊断脚本的兜底注入：见 [_diagnoseFallbackSeconds]。
            // 不能只挂 onLoad —— 那个闸可能永不开，而失败形态与「脚本报错」
            // 无法区分。谁先到算谁，[_injectDiagnose] 自带一次性闸。
            if (_diagnose) {
              Timer(const Duration(seconds: _diagnoseFallbackSeconds), () {
                _injectDiagnose(controller, 'timer');
              });
            }
            return controller;
          },
          loadingWidget: const Center(child: CircularProgressIndicator()),
          errorBuilder:
              (context, error) => Center(
                child: Text(
                  'WebF FAILED: $error',
                  style: const TextStyle(color: Colors.red, fontSize: 20),
                ),
              ),
        ),
      ),
    );
  }
}
