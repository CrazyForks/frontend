import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/utils/file_logger.dart';
import 'presentation/desktop_lyric_app.dart';

/// 桌面歌词悬浮窗子 engine 的入口（songloft-org/songloft#318）。
///
/// 由 main.dart 在检测到当前 engine 是桌面歌词窗口时调用，只做窗口管理初始化，
/// 不跑 AudioService/SMTC/Tracely/托盘/单实例检测等主窗口专属逻辑。
///
/// 日志与错误处理必须在这里**单独**装一遍：主窗口 main() 里那套（FileLogger、
/// FlutterError.onError、PlatformDispatcher.onError）只挂在主 engine 的 isolate 上，
/// 悬浮窗这个 engine 一行都继承不到。首个 Windows 版秒退问题难排查就是因为悬浮窗侧
/// 零日志——用户上传的日志里连「悬浮窗启动过」都看不出来。
Future<void> runDesktopLyricWindow() async {
  await FileLogger.init(fileSuffix: '_lyric');
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    originalDebugPrint(message, wrapWidth: wrapWidth);
    if (message != null) {
      FileLogger.writeln(message);
    }
  };
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[DesktopLyric] FlutterError: ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[DesktopLyric] 未捕获异常: $error\n$stack');
    return true;
  };

  debugPrint('[DesktopLyric] 悬浮窗 engine 启动');
  await windowManager.ensureInitialized();
  // 必须在任何 setSkipTaskbar / setProgressBar 之前调一次（songloft-org/songloft#318）：
  // window_manager 的 Windows 实现里 ITaskbarList3* taskbar_ 初值是 nullptr，**只在**
  // waitUntilReadyToShow 的原生实现里 CoCreateInstance 出来；而 SetSkipTaskbar 上来就
  // 无条件 taskbar_->HrInit()。少了这一步，悬浮窗 _init() 里的 setSkipTaskbar(true) 就是
  // 对空指针做虚调用 —— 访问违规、整个进程当场消失，既没有 Dart 异常也没有任何日志。
  // 主窗口侧躲过这一劫只是因为它从不调 setSkipTaskbar。这行**不是**可省的样板代码。
  await windowManager.waitUntilReadyToShow();
  runApp(const DesktopLyricApp());
}
