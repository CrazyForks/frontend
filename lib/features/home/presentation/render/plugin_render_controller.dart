/// 插件页渲染层的**引擎无关**契约（songloft-org/songloft#341）。
///
/// 插件页历史上只有一种 native 实现（`flutter_inappwebview`），渲染逻辑与
/// 页面 chrome 混在两个近乎重复的 State 里。引入 WebF 作为备选引擎后，
/// 需要一层薄抽象把「谁来渲染」与「外面套什么壳」分开：
///
///   - [PluginRenderController]：宿主页面能对渲染面做的操作
///   - `PluginRenderView`：引擎无关的壳（加载态 / 超时 / 错误 UI / 重试）
///   - `PluginRenderSurface*`：各引擎自己的渲染面 + 宿主桥 + 主题下推
library;

/// 可选的插件页渲染引擎。
///
/// 仅 native 平台有意义：Web 端永远走 iframe（`*_stub.dart`），WebF 不支持
/// Flutter Web（其 `lib/` 内有 39 处无条件 `import 'dart:ffi'`，是编译失败而
/// 非运行时降级）。
enum PluginRenderEngine {
  /// `flutter_inappwebview`，当前默认。
  webView,

  /// WebF，渲染进 Flutter 管线、零 platform view。
  webF;

  /// 该引擎的渲染面是否是独立的原生表面（platform view）。
  ///
  /// 为 true 时宿主要额外伺候一堆平台细节：Windows 上 WebView2 是独立 HWND，
  /// 最小化后不自动收起、残留拦截桌面右键（songloft-org/songloft#293），
  /// `Offstage` 收不起来，必须把整个渲染面移出 widget 树才能销毁。
  ///
  /// WebF 产出的是普通 Flutter RenderObject（`WebFRootViewport extends
  /// MultiChildRenderObjectWidget`），没有独立原生表面，这类补丁全都不需要。
  bool get usesPlatformView => this == PluginRenderEngine.webView;
}

/// 宿主页面对渲染面的操作句柄。
///
/// 由具体引擎实现，经 `PluginRenderView` 的 `onControllerReady` 回调交给宿主。
abstract class PluginRenderController {
  /// 页面内若还有可回退的历史则回退，并返回 `true`；
  /// 否则返回 `false`，由宿主决定是退出路由还是退出应用。
  ///
  /// 之所以是「回退与否的判断 + 动作」打包成一个方法、而不是暴露
  /// `canGoBack()` + `goBack()` 两个原语：WebF 侧**没有** `canGoBack`
  /// （`module/history.dart` 的 case 列表里只有 length/state/back/forward/
  /// pushState/replaceState/go，controller 上也没有 `goBack()`），只能由页面内
  /// 的 JS 自己判断后回报结果，拆成两步在那边无法原子实现。
  Future<bool> goBackIfPossible();

  /// 释放渲染面持有的输入焦点。
  ///
  /// 原生 WebView 即使被 `Offstage` 隐藏，仍可能在系统层面握着键盘焦点、
  /// 抢走 Flutter 的输入法上下文，所以 Tab 切走时要主动释放。
  void clearFocus();
}
