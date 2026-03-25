// 插件 WebView 页面
// 使用条件导出：原生平台使用 flutter_inappwebview，Web 平台使用桩实现。
// 这样 Web 构建时 tree-shaking 不会包含 flutter_inappwebview 的代码。
export 'plugin_webview_page_stub.dart'
    if (dart.library.io) 'plugin_webview_page_native.dart';
