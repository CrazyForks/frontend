import 'package:flutter/foundation.dart';

/// 全局窗口可见性通知器（桌面端，主要服务于 Windows）。
///
/// Windows 上插件页用的 flutter_inappwebview 底层是 WebView2，作为**独立原生
/// HWND 覆盖**合成在 Flutter 窗口之上。主窗口最小化 / 隐藏到托盘时，这个 HWND
/// 不会自动跟随收起，残留在屏幕上拦截鼠标右键，导致桌面右键菜单弹不出来
/// （songloft-org/songloft#293）。`Offstage` 只停 Flutter 层绘制、收不起原生
/// HWND（同 #246），因此必须在不可见时把 `InAppWebView` 整个移出 widget 树来
/// 销毁 HWND。
///
/// 由 `WindowTrayManager` 在窗口最小化 / 恢复 / 隐藏到托盘 / 从托盘恢复时更新，
/// 插件页监听此状态决定是否挂载 WebView。仅 Windows 会翻转此值（`WindowTrayManager`
/// 只在 Windows 下 setup），其余平台恒为 `true`，插件页行为不变。
final ValueNotifier<bool> windowVisibleNotifier = ValueNotifier<bool>(true);
