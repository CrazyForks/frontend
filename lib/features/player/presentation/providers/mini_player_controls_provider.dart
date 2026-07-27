import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/mini_player_controls.dart';

/// 迷你播放条按钮档位（纯本地，不同步服务器，songloft-org/songloft-player#25）。
/// build 同步返回默认值，随后异步回读校正。
class MiniPlayerControlsNotifier extends Notifier<MiniPlayerControls> {
  @override
  MiniPlayerControls build() {
    _load();
    return MiniPlayerControls.prevNext;
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      state = MiniPlayerControls.fromString(prefs.getMiniPlayerControls());
    } catch (e) {
      debugPrint('[MiniPlayer] Failed to load controls preference: $e');
    }
  }

  Future<void> setControls(MiniPlayerControls value) async {
    if (state == value) return;
    state = value;
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      await prefs.setMiniPlayerControls(value.name);
      // 注意：本地设置，刻意不调用 pushPreferencesToServer
    } catch (e) {
      debugPrint('[MiniPlayer] Failed to save controls preference: $e');
    }
  }
}

/// 迷你播放条按钮档位 Provider
final miniPlayerControlsProvider =
    NotifierProvider<MiniPlayerControlsNotifier, MiniPlayerControls>(
      MiniPlayerControlsNotifier.new,
    );
