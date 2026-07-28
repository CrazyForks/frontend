import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/home_grid_config.dart';

/// 首页宽屏歌单网格行列配置（纯本地，不同步服务器，songloft-org/songloft#332）。
///
/// build() 同步返回默认值让首页首帧不闪，随后异步回读校正 —— 与
/// `MiniPlayerControlsNotifier` 同一模板。
class HomeGridConfigNotifier extends Notifier<HomeGridConfig> {
  /// 用户已经改过设置：此后 [_load] 的迟到结果不再覆盖，避免「刚点完选择就被
  /// 慢一步返回的读盘结果回滚」的竞态。
  bool _userTouched = false;

  @override
  HomeGridConfig build() {
    _load();
    return HomeGridConfig.defaults;
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      if (_userTouched) return;
      state = HomeGridConfig.fromStorage(
        columns: prefs.getHomeGridColumns(),
        rows: prefs.getHomeGridRows(),
      );
    } catch (e) {
      debugPrint('[HomeGrid] Failed to load grid preference: $e');
    }
  }

  Future<void> setColumns(int columns) =>
      _update(state.copyWith(columns: columns));

  Future<void> setRows(int rows) => _update(state.copyWith(rows: rows));

  Future<void> _update(HomeGridConfig next) async {
    _userTouched = true;
    if (next == state) return;
    state = next;
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      await prefs.setHomeGridColumns(next.columns);
      await prefs.setHomeGridRows(next.rows);
      // 注意：本地设置，刻意不调用 pushPreferencesToServer
    } catch (e) {
      debugPrint('[HomeGrid] Failed to save grid preference: $e');
    }
  }
}

/// 首页歌单网格行列配置 Provider
final homeGridConfigProvider =
    NotifierProvider<HomeGridConfigNotifier, HomeGridConfig>(
      HomeGridConfigNotifier.new,
    );
