import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/theme_pack_api.dart';

/// ThemePackApi provider
final themePackApiProvider = Provider<ThemePackApi>((ref) {
  final dio = ref.watch(dioProvider);
  return ThemePackApi(dio: dio);
});

/// 已安装主题包列表
final themePackListProvider =
    AsyncNotifierProvider<ThemePackListNotifier, List<ThemePackListItem>>(
  ThemePackListNotifier.new,
);

class ThemePackListNotifier extends AsyncNotifier<List<ThemePackListItem>> {
  @override
  Future<List<ThemePackListItem>> build() async {
    final api = ref.watch(themePackApiProvider);
    return api.listThemePacks();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(themePackApiProvider);
      return api.listThemePacks();
    });
  }

  Future<ThemePack> importThemePack(String rawJson) async {
    final api = ref.read(themePackApiProvider);
    final result = await api.importThemePack(rawJson);
    // 导入后刷新列表
    ref.invalidateSelf();
    return result;
  }

  Future<void> deleteThemePack(String themeId) async {
    final api = ref.read(themePackApiProvider);
    await api.deleteThemePack(themeId);
    ref.invalidateSelf();
    // 如果删除的是激活主题，刷新激活状态
    ref.invalidate(activeThemePackProvider);
  }
}

/// 当前激活的主题包（null 表示使用默认主题）
final activeThemePackProvider =
    AsyncNotifierProvider<ActiveThemePackNotifier, ThemePack?>(
  ActiveThemePackNotifier.new,
);

class ActiveThemePackNotifier extends AsyncNotifier<ThemePack?> {
  @override
  Future<ThemePack?> build() async {
    final api = ref.watch(themePackApiProvider);
    try {
      return await api.getActiveThemePack();
    } catch (_) {
      // 获取失败时回退默认主题
      return null;
    }
  }

  Future<void> setActive(String themeId) async {
    final api = ref.read(themePackApiProvider);
    await api.setActiveThemePack(themeId);
    ref.invalidateSelf();
  }

  Future<void> clearActive() async {
    final api = ref.read(themePackApiProvider);
    await api.clearActiveThemePack();
    state = const AsyncData(null);
  }
}

/// 在线主题目录
final themeCatalogProvider =
    AsyncNotifierProvider<ThemeCatalogNotifier, List<ThemeCatalogEntry>>(
  ThemeCatalogNotifier.new,
);

class ThemeCatalogNotifier extends AsyncNotifier<List<ThemeCatalogEntry>> {
  @override
  Future<List<ThemeCatalogEntry>> build() async {
    return []; // 不自动加载，用户点击时手动 refresh
  }

  Future<void> refresh({bool force = false}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(themePackApiProvider);
      final proxy = ref.read(githubProxyProvider).value ?? '';
      final resp = await api.refreshCatalog(
        githubProxy: proxy.isNotEmpty ? proxy : null,
        force: force,
      );
      return resp.themes;
    });
  }

  Future<void> installTheme(ThemeCatalogEntry entry) async {
    final api = ref.read(themePackApiProvider);
    final proxy = ref.read(githubProxyProvider).value ?? '';
    await api.installFromCatalog(
      url: entry.url,
      githubProxy: proxy.isNotEmpty ? proxy : null,
      sha256: entry.sha256.isNotEmpty ? entry.sha256 : null,
    );
    // 刷新目录和本地列表
    ref.invalidate(themePackListProvider);
    ref.invalidate(activeThemePackProvider);
    await refresh();
  }
}
