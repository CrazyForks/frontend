import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../shared/models/song.dart';
import '../../data/playlist_api.dart';
import '../../data/playlist_repository.dart';
import '../../domain/playlist.dart';

/// Playlist API Provider
final playlistApiProvider = Provider<PlaylistApi>((ref) {
  final dio = ref.watch(dioProvider);
  return PlaylistApi(dio);
});

/// Playlist Repository Provider
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final playlistApi = ref.watch(playlistApiProvider);
  return PlaylistRepository(playlistApi);
});

/// 获取歌单列表 Provider（带类型筛选）
final playlistListProvider =
    FutureProvider.family<PlaylistListResponse, String?>((ref, type) async {
      final repository = ref.watch(playlistRepositoryProvider);
      return repository.getPlaylists(type: type, limit: 100);
    });

/// 获取歌单详情 Provider
final playlistDetailProvider = FutureProvider.family<Playlist, int>((
  ref,
  id,
) async {
  final repository = ref.watch(playlistRepositoryProvider);
  return repository.getPlaylist(id);
});

/// 获取歌单歌曲 Provider（自动分页，确保加载全部歌曲）
final playlistSongsProvider = FutureProvider.family<SongListResponse, int>((
  ref,
  id,
) async {
  final repository = ref.watch(playlistRepositoryProvider);
  const pageLimit = 500;

  // 第一页
  final firstPage = await repository.getPlaylistSongs(
    id,
    limit: pageLimit,
    offset: 0,
  );
  final total = firstPage.total;

  // 第一页已包含全部歌曲，直接返回
  if (firstPage.songs.length >= total) return firstPage;

  // 继续加载剩余页
  final allSongs = List<Song>.from(firstPage.songs);
  int offset = firstPage.songs.length;
  while (offset < total) {
    final page = await repository.getPlaylistSongs(
      id,
      limit: pageLimit,
      offset: offset,
    );
    if (page.songs.isEmpty) break;
    allSongs.addAll(page.songs);
    offset += page.songs.length;
  }

  return SongListResponse(songs: allSongs, total: total);
});

/// 歌单操作 Notifier
class PlaylistNotifier extends Notifier<AsyncValue<void>> {
  late PlaylistRepository _repository;

  @override
  AsyncValue<void> build() {
    _repository = ref.watch(playlistRepositoryProvider);
    return const AsyncValue.data(null);
  }

  /// 创建歌单
  Future<Playlist?> createPlaylist({
    required String type,
    required String name,
    String? description,
    String? coverPath,
  }) async {
    state = const AsyncValue.loading();
    try {
      final playlist = await _repository.createPlaylist(
        type: type,
        name: name,
        description: description,
        coverPath: coverPath,
      );
      state = const AsyncValue.data(null);
      // 刷新歌单列表
      ref.invalidate(playlistListProvider);
      return playlist;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// 更新歌单
  Future<Playlist?> updatePlaylist(
    int id, {
    String? name,
    String? description,
    String? coverPath,
  }) async {
    state = const AsyncValue.loading();
    try {
      final playlist = await _repository.updatePlaylist(
        id,
        name: name,
        description: description,
        coverPath: coverPath,
      );
      state = const AsyncValue.data(null);
      // 刷新歌单详情和列表
      ref.invalidate(playlistDetailProvider(id));
      ref.invalidate(playlistListProvider);
      return playlist;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// 删除歌单
  Future<bool> deletePlaylist(int id) async {
    state = const AsyncValue.loading();
    try {
      await _repository.deletePlaylist(id);
      state = const AsyncValue.data(null);
      // 刷新歌单列表
      ref.invalidate(playlistListProvider);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 自动创建歌单
  Future<bool> autoCreatePlaylists({bool includeSubdirs = false}) async {
    state = const AsyncValue.loading();
    try {
      await _repository.autoCreatePlaylists(includeSubdirs: includeSubdirs);
      state = const AsyncValue.data(null);
      // 刷新歌单列表
      ref.invalidate(playlistListProvider);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 向歌单添加歌曲
  Future<bool> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    state = const AsyncValue.loading();
    try {
      await _repository.addSongsToPlaylist(playlistId, songIds);
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 从歌单移除歌曲
  Future<bool> removeSongFromPlaylist(int playlistId, int songId) async {
    state = const AsyncValue.loading();
    try {
      await _repository.removeSongFromPlaylist(playlistId, songId);
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 重新排序歌单歌曲
  Future<bool> reorderPlaylistSongs(int playlistId, List<int> songIds) async {
    state = const AsyncValue.loading();
    try {
      await _repository.reorderPlaylistSongs(playlistId, songIds);
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 批量移除歌曲
  Future<bool> batchRemoveSongs(int playlistId, Set<int> songIds) async {
    state = const AsyncValue.loading();
    try {
      for (final songId in songIds) {
        await _repository.removeSongFromPlaylist(playlistId, songId);
      }
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 更新歌单最后访问时间
  Future<void> touchPlaylist(int id) async {
    try {
      await _repository.touchPlaylist(id);
    } catch (_) {
      // 忽略错误
    }
  }
}

/// 歌单操作 Provider
final playlistNotifierProvider =
    NotifierProvider<PlaylistNotifier, AsyncValue<void>>(PlaylistNotifier.new);
