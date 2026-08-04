import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../jsplugin/data/jsplugin_api.dart';
import '../../../jsplugin/presentation/providers/jsplugin_provider.dart';
import 'plugin_render_controller.dart';

/// 按 `entryPath` 解析某个插件声明的渲染引擎（songloft-org/songloft#341）。
///
/// 引擎是**插件自己的属性**（`plugin.json` → 后端 `render_engine` 字段），不是用户
/// 偏好，所以这里从既有的插件列表 [jsPluginsProvider] 派生，不新增网络请求、也不
/// 落任何本地 pref。
///
/// **`null` = 引擎尚未确定**（插件列表还在首次加载），宿主此时必须只显示 loading、
/// 不要挂渲染面。若加载中先按默认 WebView 渲染、列表回来后再切 WebF，整页会
/// **加载两次**：两套引擎初始化 + 两轮插件 JS 执行，还伴随一次可见闪烁。列表通常
/// 已被首页 / 插件管理页预热，实际几乎不会真的等。
///
/// 列表拉取失败则**不是** null，而是回落到 [PluginRenderEngine.webView]：它无条件
/// 可用，且真正的错误由插件页自己展示，不该因为列表接口挂了就打不开插件页。
/// 同理 entryPath 在列表里找不到（刚卸载 / 列表过期）也按默认引擎渲染，让插件页
/// 自己去报 404。
final pluginRenderEngineForProvider =
    Provider.family<PluginRenderEngine?, String>((ref, entryPath) {
      final plugins = ref.watch(jsPluginsProvider);
      if (plugins.isLoading && !plugins.hasValue && !plugins.hasError) {
        return null;
      }
      for (final plugin in plugins.value ?? const <JSPlugin>[]) {
        if (plugin.entryPath == entryPath) {
          return PluginRenderEngine.fromManifestValue(plugin.renderEngine);
        }
      }
      return PluginRenderEngine.webView;
    });

/// 从插件页 URL 里取出 `entryPath`。
///
/// 插件页 URL 形如 `<base>/api/v1/jsplugin/<entryPath>[/...]`（可带尾斜杠与
/// query）。`PluginWebViewPage` 只拿到拼好的 URL（路由参数就是 URL），没有
/// entryPath，故在此反解。取不到时返回 null，宿主按默认引擎渲染。
String? pluginEntryPathFromUrl(String url) {
  final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty);
  final list = segments.toList();
  final index = list.lastIndexOf('jsplugin');
  if (index < 0 || index + 1 >= list.length) return null;
  return list[index + 1];
}
