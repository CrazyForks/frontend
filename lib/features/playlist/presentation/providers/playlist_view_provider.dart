import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

/// 歌单视图模式枚举
enum PlaylistViewMode {
  grid,
  list;

  static PlaylistViewMode fromString(String value) {
    return PlaylistViewMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PlaylistViewMode.grid,
    );
  }
}

/// 歌单视图模式 Provider
final playlistViewModeProvider =
    NotifierProvider<PlaylistViewModeNotifier, PlaylistViewMode>(
      PlaylistViewModeNotifier.new,
    );

class PlaylistViewModeNotifier extends Notifier<PlaylistViewMode> {
  @override
  PlaylistViewMode build() {
    _loadViewMode();
    return PlaylistViewMode.grid;
  }

  Future<void> _loadViewMode() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      final mode = prefs.getPlaylistViewMode();
      state = PlaylistViewMode.fromString(mode);
    } catch (e) {
      debugPrint('[PlaylistView] Failed to load view mode: $e');
    }
  }

  Future<void> toggleViewMode() async {
    final newMode =
        state == PlaylistViewMode.grid
            ? PlaylistViewMode.list
            : PlaylistViewMode.grid;
    state = newMode;
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      await prefs.setPlaylistViewMode(newMode.name);
      debugPrint('[PlaylistView] Saved view mode: ${newMode.name}');
    } catch (e) {
      debugPrint('[PlaylistView] Failed to save view mode: $e');
    }
  }

  Future<void> setViewMode(PlaylistViewMode mode) async {
    if (state == mode) return;
    state = mode;
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      await prefs.setPlaylistViewMode(mode.name);
      debugPrint('[PlaylistView] Saved view mode: ${mode.name}');
    } catch (e) {
      debugPrint('[PlaylistView] Failed to save view mode: $e');
    }
  }
}
