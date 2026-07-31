import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webf/webf.dart';

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
  runApp(const ProbeApp());
}

const String _probeUrl = String.fromEnvironment(
  'PROBE_URL',
  defaultValue: 'http://127.0.0.1:58991/probe.html',
);

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
          createController:
              () => WebFController(
                // 加载失败要在截图里看得见，不能只落日志
                onLoadError: (error, stack) {
                  debugPrint('[probe] onLoadError: $error\n$stack');
                },
                onJSError: (msg) {
                  debugPrint('[probe] onJSError: $msg');
                },
              ),
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
