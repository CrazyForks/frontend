import 'dart:io';

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
                if (_diagnose) c.view.evaluateJavaScripts(_diagnoseJs);
              },
            );
            // onJSLog 是字段而非构造参数，必须构造后赋值。
            // 页面 console 靠它回传，诊断脚本的输出才能落到 flutter.log。
            controller.onJSLog = (level, message) {
              debugPrint('[page] $message');
            };
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
