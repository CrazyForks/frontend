import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/jsplugin/data/jsplugin_api.dart';

/// 插件商店条目的身份匹配。entryPath 会被不同作者的插件撞名
/// （songloft-org/songloft#339），故行标识与状态更新都必须带上 identity。
void main() {
  RegistryPluginEntry entry({
    String entryPath = 'demo',
    String? identity,
    String version = '1.0.0',
  }) {
    return RegistryPluginEntry(
      name: 'Demo',
      entryPath: entryPath,
      version: version,
      downloadUrl: 'https://example.com/demo.zip',
      identity: identity,
    );
  }

  group('rowKey', () {
    test('同 entryPath 不同作者产出不同的行标识', () {
      expect(
        entry(identity: 'alice').rowKey,
        isNot(entry(identity: 'bob').rowKey),
      );
    });

    test('identity 缺失时退化为 entryPath 维度', () {
      expect(entry().rowKey, entry().rowKey);
      expect(entry(entryPath: 'a').rowKey, isNot(entry(entryPath: 'b').rowKey));
    });
  });

  group('matches', () {
    test('entryPath 与 identity 同时相等才算同一条', () {
      final alice = entry(identity: 'alice');
      expect(alice.matches('demo', 'alice'), isTrue);
      expect(alice.matches('demo', 'bob'), isFalse);
      expect(alice.matches('other', 'alice'), isFalse);
    });

    test('identity 为 null 与空字符串视为等价', () {
      expect(entry().matches('demo', ''), isTrue);
      expect(entry(identity: '').matches('demo', null), isTrue);
    });

    test('identity 缺失的条目不会匹配上有身份的条目', () {
      expect(entry().matches('demo', 'alice'), isFalse);
    });
  });

  group('fromJson', () {
    test('解析身份与冲突字段', () {
      final e = RegistryPluginEntry.fromJson({
        'name': 'Demo by Bob',
        'entry_path': 'demo',
        'version': '2.0.0',
        'download_url': 'https://example.com/bob.zip',
        'identity': 'bob',
        'source_name': '社区聚合源',
        'conflict': true,
        'conflict_with': 'Demo by Alice（作者：Alice）v1.0.0',
      });
      expect(e.identity, 'bob');
      expect(e.sourceName, '社区聚合源');
      expect(e.conflict, isTrue);
      expect(e.conflictWith, contains('Alice'));
      // 冲突条目不是「已安装」——它是另一个插件
      expect(e.installed, isFalse);
      expect(e.hasUpdate, isFalse);
    });

    test('缺失字段时保持旧行为', () {
      final e = RegistryPluginEntry.fromJson({
        'name': 'Demo',
        'entry_path': 'demo',
        'version': '1.0.0',
        'download_url': 'https://example.com/demo.zip',
      });
      expect(e.identity, isNull);
      expect(e.conflict, isFalse);
      expect(e.rowKey, 'demo|');
    });
  });

  group('copyWith', () {
    test('保留身份与来源字段', () {
      final e = RegistryPluginEntry.fromJson({
        'name': 'Demo',
        'entry_path': 'demo',
        'version': '1.0.0',
        'download_url': 'https://example.com/demo.zip',
        'identity': 'alice',
        'source_name': '官方源',
        'source_url': 'https://example.com/registry.json',
      }).copyWith(installed: true, installedVersion: '1.0.0');
      expect(e.identity, 'alice');
      expect(e.sourceName, '官方源');
      expect(e.sourceUrl, 'https://example.com/registry.json');
      expect(e.installed, isTrue);
    });

    test('可以把冲突态清掉', () {
      final conflicted = RegistryPluginEntry.fromJson({
        'name': 'Demo',
        'entry_path': 'demo',
        'version': '1.0.0',
        'download_url': 'https://example.com/demo.zip',
        'conflict': true,
        'conflict_with': 'Demo by Alice v1.0.0',
      });
      final resolved = conflicted.copyWith(
        installed: true,
        conflict: false,
        conflictWith: '',
      );
      expect(resolved.conflict, isFalse);
      expect(resolved.conflictWith, isEmpty);
      expect(resolved.installed, isTrue);
    });
  });
}
