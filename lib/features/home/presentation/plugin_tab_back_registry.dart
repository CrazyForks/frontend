import 'dart:async';

/// 进程级注册表：把「当前激活的插件 tab 的返回处理」暴露给路由层。
///
/// 背景：插件 tab 路由 `/plugin-tab/:entryPath` 的页面是 `SizedBox.shrink` 占位，
/// 真正的 `PluginTabPage`（带 `PopScope`）由 `ShellLayout` 用 Offstage 单独渲染、
/// 不在路由页的 widget 树里。于是 go_router 的返回键只在嵌套 navigator 上弹那个
/// 占位路由（→ 上一个 tab），根本不会咨询 `PluginTabPage` 的 `PopScope`，插件内部
/// 的弹窗 / 编辑器 / 多级页面就无法用返回键收起。
///
/// 修法：插件 tab 路由页自己挂一个 `PopScope`，回调里经本注册表找到当前激活插件
/// tab 的 `goBackIfPossible`（即插件 `consumeBack`）；返回 true（已消费）就留在页面，
/// false 就 `context.pop()` 退回上一个 tab。
class PluginTabBackRegistry {
  PluginTabBackRegistry._();

  static final Map<String, Future<bool> Function()> _handlers = {};

  /// 插件 tab 在拿到渲染控制器（`onControllerReady`）时注册自己的返回处理。
  static void register(String entryPath, Future<bool> Function() handler) {
    _handlers[entryPath] = handler;
  }

  /// 插件 tab 销毁时注销，避免回调打到已销毁的渲染面上。
  static void unregister(String entryPath) {
    _handlers.remove(entryPath);
  }

  /// 路由页的 `PopScope` 在返回键时调用；未注册（控制器还没就绪）返回 false。
  static Future<bool> handleBack(String entryPath) {
    final handler = _handlers[entryPath];
    if (handler == null) return Future.value(false);
    return handler();
  }
}
