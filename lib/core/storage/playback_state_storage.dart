import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/song.dart';

class PlaybackQueueSnapshot {
  final List<Song> songs;

  /// 新版 Web 快照内嵌队列索引；null 表示旧版列表或原生文件，调用方回退偏好设置。
  final int? currentIndex;

  const PlaybackQueueSnapshot({required this.songs, this.currentIndex});

  static const empty = PlaybackQueueSnapshot(songs: []);
}

class PlaybackQueueSaveResult {
  final bool saved;
  final int persistedIndex;
  final int persistedSongCount;
  final bool truncated;
  final Object? error;

  const PlaybackQueueSaveResult._({
    required this.saved,
    required this.persistedIndex,
    required this.persistedSongCount,
    required this.truncated,
    this.error,
  });

  factory PlaybackQueueSaveResult.success(
    PlaybackQueueSnapshot snapshot, {
    required bool truncated,
  }) {
    return PlaybackQueueSaveResult._(
      saved: true,
      persistedIndex: snapshot.currentIndex ?? -1,
      persistedSongCount: snapshot.songs.length,
      truncated: truncated,
    );
  }

  factory PlaybackQueueSaveResult.failure(Object error) {
    return PlaybackQueueSaveResult._(
      saved: false,
      persistedIndex: -1,
      persistedSongCount: 0,
      truncated: false,
      error: error,
    );
  }
}

@visibleForTesting
class PlaybackQueueCodec {
  static const _prefix = 'songloft-playback:gzip-v1:';

  static String encodeWeb(PlaybackQueueSnapshot snapshot) {
    final jsonText = jsonEncode({
      'version': 1,
      'current_index': snapshot.currentIndex,
      'songs': snapshot.songs.map((song) => song.toJson()).toList(),
    });
    final compressed = GZipEncoder().encode(utf8.encode(jsonText));
    if (compressed == null) {
      throw StateError('播放队列压缩失败');
    }
    return '$_prefix${base64Encode(compressed)}';
  }

  static PlaybackQueueSnapshot decode(String value) {
    if (value.startsWith(_prefix)) {
      final compressed = base64Decode(value.substring(_prefix.length));
      final jsonText = utf8.decode(GZipDecoder().decodeBytes(compressed));
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('不支持的播放队列快照版本');
      }
      final rawSongs = decoded['songs'];
      if (rawSongs is! List<dynamic>) {
        throw const FormatException('播放队列快照缺少歌曲列表');
      }
      return PlaybackQueueSnapshot(
        songs:
            rawSongs
                .map((item) => Song.fromJson(item as Map<String, dynamic>))
                .toList(),
        currentIndex: decoded['current_index'] as int?,
      );
    }

    // 兼容 2.11.3 及更早版本直接存储的 Song JSON 数组。
    final decoded = jsonDecode(value);
    if (decoded is! List<dynamic>) {
      throw const FormatException('旧版播放队列不是 JSON 数组');
    }
    return PlaybackQueueSnapshot(
      songs:
          decoded
              .map((item) => Song.fromJson(item as Map<String, dynamic>))
              .toList(),
    );
  }
}

/// Web localStorage 的有界写入策略，回调注入让配额失败路径可在单测中稳定复现。
@visibleForTesting
class PlaybackQueueWebPersistence {
  static const maxFallbackSongs = 200;

  final Future<void> Function(String value) write;
  final Future<void> Function() remove;

  const PlaybackQueueWebPersistence({
    required this.write,
    required this.remove,
  });

  Future<PlaybackQueueSaveResult> save(
    List<Song> playlist,
    int currentIndex,
  ) async {
    final full = _snapshot(playlist, currentIndex);
    final fullValue = PlaybackQueueCodec.encodeWeb(full);
    Object? lastError;

    try {
      await write(fullValue);
      return PlaybackQueueSaveResult.success(full, truncated: false);
    } catch (error) {
      lastError = error;
    }

    // 替换已有 localStorage 值失败时先释放旧版大队列占用，再重试压缩后的完整快照。
    try {
      await remove();
    } catch (error) {
      lastError = error;
    }
    try {
      await write(fullValue);
      return PlaybackQueueSaveResult.success(full, truncated: false);
    } catch (error) {
      lastError = error;
    }

    final window = _fallbackWindow(playlist, currentIndex);
    if (window.songs.length < full.songs.length) {
      try {
        await write(PlaybackQueueCodec.encodeWeb(window));
        return PlaybackQueueSaveResult.success(window, truncated: true);
      } catch (error) {
        lastError = error;
      }
    }

    if (full.songs.length > 1) {
      final currentOnly = _currentSongOnly(playlist, currentIndex);
      try {
        await write(PlaybackQueueCodec.encodeWeb(currentOnly));
        return PlaybackQueueSaveResult.success(currentOnly, truncated: true);
      } catch (error) {
        lastError = error;
      }
    }

    // 完全不可写时至少清掉旧队列，给其他小型偏好项释放空间。
    try {
      await remove();
    } catch (error) {
      lastError = error;
    }
    return PlaybackQueueSaveResult.failure(lastError);
  }

  static PlaybackQueueSnapshot _snapshot(
    List<Song> playlist,
    int currentIndex,
  ) {
    if (playlist.isEmpty) return PlaybackQueueSnapshot.empty;
    final safeIndex = currentIndex.clamp(0, playlist.length - 1);
    return PlaybackQueueSnapshot(songs: playlist, currentIndex: safeIndex);
  }

  static PlaybackQueueSnapshot _fallbackWindow(
    List<Song> playlist,
    int currentIndex,
  ) {
    final full = _snapshot(playlist, currentIndex);
    if (playlist.length <= maxFallbackSongs) return full;

    final safeIndex = full.currentIndex!;
    final maxStart = playlist.length - maxFallbackSongs;
    final start = (safeIndex - maxFallbackSongs ~/ 2).clamp(0, maxStart);
    return PlaybackQueueSnapshot(
      songs: playlist.sublist(start, start + maxFallbackSongs),
      currentIndex: safeIndex - start,
    );
  }

  static PlaybackQueueSnapshot _currentSongOnly(
    List<Song> playlist,
    int currentIndex,
  ) {
    final full = _snapshot(playlist, currentIndex);
    if (full.songs.isEmpty) return full;
    return PlaybackQueueSnapshot(
      songs: [full.songs[full.currentIndex!]],
      currentIndex: 0,
    );
  }
}

class PlaybackStateStorage {
  static final PlaybackStateStorage _instance = PlaybackStateStorage._();
  factory PlaybackStateStorage() => _instance;
  PlaybackStateStorage._();

  static const _webFallbackKey = 'player_queue_json';
  static const _fileName = 'playback_queue.json';

  String? _filePath;

  Future<String> _getFilePath() async {
    if (_filePath != null) return _filePath!;
    final dir = await getApplicationDocumentsDirectory();
    _filePath = '${dir.path}/$_fileName';
    return _filePath!;
  }

  Future<PlaybackQueueSaveResult> saveQueue(
    List<Song> playlist, {
    required int currentIndex,
  }) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final persistence = PlaybackQueueWebPersistence(
          write: (value) async {
            if (!await prefs.setString(_webFallbackKey, value)) {
              throw StateError('浏览器播放队列写入失败');
            }
          },
          remove: () async {
            await prefs.remove(_webFallbackKey);
          },
        );
        final result = await persistence.save(playlist, currentIndex);
        if (result.truncated) {
          debugPrint(
            '[PlaybackStateStorage] Web queue exceeded quota; saved '
            '${result.persistedSongCount}-song recovery window',
          );
        } else if (!result.saved) {
          debugPrint(
            '[PlaybackStateStorage] Web queue persistence disabled: '
            '${result.error}',
          );
        }
        return result;
      }

      final jsonText = jsonEncode(
        playlist.map((song) => song.toJson()).toList(),
      );
      final path = await _getFilePath();
      await File(path).writeAsString(jsonText);
      final snapshot = PlaybackQueueWebPersistence._snapshot(
        playlist,
        currentIndex,
      );
      return PlaybackQueueSaveResult.success(snapshot, truncated: false);
    } catch (error) {
      debugPrint('[PlaybackStateStorage] saveQueue failed: $error');
      return PlaybackQueueSaveResult.failure(error);
    }
  }

  Future<PlaybackQueueSnapshot> loadQueue() async {
    try {
      String? jsonText;

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonText = prefs.getString(_webFallbackKey);
      } else {
        final path = await _getFilePath();
        final file = File(path);
        if (await file.exists()) {
          jsonText = await file.readAsString();
        }
      }

      if (jsonText == null || jsonText.isEmpty) {
        return PlaybackQueueSnapshot.empty;
      }
      return PlaybackQueueCodec.decode(jsonText);
    } catch (error) {
      debugPrint('[PlaybackStateStorage] loadQueue failed: $error');
      return PlaybackQueueSnapshot.empty;
    }
  }

  Future<void> clear() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_webFallbackKey);
      } else {
        final path = await _getFilePath();
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (error) {
      debugPrint('[PlaybackStateStorage] clear failed: $error');
    }
  }
}
