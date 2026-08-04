import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/home/presentation/render/plugin_render_controller.dart';
import 'package:songloft_flutter/features/home/presentation/render/plugin_render_engine_provider.dart';
import 'package:songloft_flutter/features/jsplugin/data/jsplugin_api.dart';

/// 渲染引擎由每个插件的 plugin.json 声明（songloft-org/songloft#341）。
/// 老服务端不返回 `render_engine`，故解析必须容错到默认 WebView 而不是抛异常。
void main() {
  group('PluginRenderEngine.fromManifestValue', () {
    test('webf 声明生效', () {
      expect(
        PluginRenderEngine.fromManifestValue('webf'),
        PluginRenderEngine.webF,
      );
      expect(
        PluginRenderEngine.fromManifestValue(' WebF '),
        PluginRenderEngine.webF,
      );
    });

    test('缺失 / 空串 / 非法值一律回落 WebView', () {
      for (final value in [null, '', '  ', 'webview', 'WEBVIEW', 'chrome']) {
        expect(
          PluginRenderEngine.fromManifestValue(value),
          PluginRenderEngine.webView,
          reason: 'value=$value',
        );
      }
    });
  });

  group('JSPlugin.fromJson', () {
    JSPlugin parse(Map<String, dynamic> extra) => JSPlugin.fromJson({
      'id': 1,
      'entry_path': 'demo',
      'file_path': 'demo.jsplugin',
      'status': 'active',
      ...extra,
    });

    test('老服务端无 render_engine 字段时不抛异常', () {
      expect(parse(const {}).renderEngine, isNull);
    });

    test('透传字符串值', () {
      expect(parse(const {'render_engine': 'webf'}).renderEngine, 'webf');
    });

    test('非字符串脏值降级为 null', () {
      expect(parse(const {'render_engine': 42}).renderEngine, isNull);
    });
  });

  group('pluginEntryPathFromUrl', () {
    test('从插件页 URL 反解 entryPath', () {
      expect(
        pluginEntryPathFromUrl('http://h:58091/api/v1/jsplugin/subsonic'),
        'subsonic',
      );
      expect(
        pluginEntryPathFromUrl('http://h:58091/api/v1/jsplugin/subsonic/'),
        'subsonic',
      );
      expect(
        pluginEntryPathFromUrl(
          'http://h:58091/base/api/v1/jsplugin/subsonic/index.html?theme=dark',
        ),
        'subsonic',
      );
    });

    test('非插件页 URL 返回 null（宿主按默认引擎渲染）', () {
      expect(pluginEntryPathFromUrl('http://h:58091/api/v1/songs'), isNull);
      expect(pluginEntryPathFromUrl('http://h:58091/api/v1/jsplugin'), isNull);
    });
  });
}
