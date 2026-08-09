import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/core/storage/playback_state_storage.dart';
import 'package:songloft_flutter/shared/models/song.dart';

Song _song(int id) {
  return Song(
    id: id,
    type: 'local',
    title: 'Song $id',
    artist: 'Artist',
    duration: 180,
    url: '/api/v1/songs/$id/play',
    addedAt: DateTime.utc(2026, 8, 9),
    updatedAt: DateTime.utc(2026, 8, 9),
  );
}

void main() {
  group('PlaybackQueueCodec', () {
    test('压缩快照往返保留歌曲和当前索引', () {
      final encoded = PlaybackQueueCodec.encodeWeb(
        PlaybackQueueSnapshot(songs: [_song(1), _song(2)], currentIndex: 1),
      );

      expect(encoded, startsWith('songloft-playback:gzip-v1:'));
      final decoded = PlaybackQueueCodec.decode(encoded);
      expect(decoded.songs.map((song) => song.id), [1, 2]);
      expect(decoded.currentIndex, 1);
    });

    test('兼容旧版原始 Song JSON 数组', () {
      final legacy = jsonEncode([_song(7).toJson(), _song(8).toJson()]);

      final decoded = PlaybackQueueCodec.decode(legacy);

      expect(decoded.songs.map((song) => song.id), [7, 8]);
      expect(decoded.currentIndex, isNull);
    });
  });

  group('PlaybackQueueWebPersistence', () {
    test('首次配额失败后删除旧值并重试完整快照', () async {
      var writes = 0;
      var removes = 0;
      final persistence = PlaybackQueueWebPersistence(
        write: (_) async {
          writes++;
          if (writes == 1) throw StateError('quota');
        },
        remove: () async => removes++,
      );

      final result = await persistence.save([_song(1), _song(2)], 1);

      expect(result.saved, isTrue);
      expect(result.truncated, isFalse);
      expect(result.persistedIndex, 1);
      expect(writes, 2);
      expect(removes, 1);
    });

    test('完整快照仍超额时保存当前歌曲附近的 200 首窗口', () async {
      var writes = 0;
      String? stored;
      final persistence = PlaybackQueueWebPersistence(
        write: (value) async {
          writes++;
          if (writes <= 2) throw StateError('quota');
          stored = value;
        },
        remove: () async {},
      );

      final result = await persistence.save(List.generate(300, _song), 250);

      expect(result.saved, isTrue);
      expect(result.truncated, isTrue);
      expect(result.persistedSongCount, 200);
      expect(result.persistedIndex, 150);
      final decoded = PlaybackQueueCodec.decode(stored!);
      expect(decoded.songs.first.id, 100);
      expect(decoded.songs.last.id, 299);
      expect(decoded.songs[decoded.currentIndex!].id, 250);
    });

    test('窗口仍不可写时降级为仅保存当前歌曲', () async {
      String? stored;
      final persistence = PlaybackQueueWebPersistence(
        write: (value) async {
          final snapshot = PlaybackQueueCodec.decode(value);
          if (snapshot.songs.length > 1) throw StateError('quota');
          stored = value;
        },
        remove: () async {},
      );

      final result = await persistence.save(List.generate(5, _song), 3);

      expect(result.saved, isTrue);
      expect(result.truncated, isTrue);
      expect(result.persistedSongCount, 1);
      expect(result.persistedIndex, 0);
      expect(PlaybackQueueCodec.decode(stored!).songs.single.id, 3);
    });

    test('浏览器完全不可写时返回失败并清理旧值', () async {
      var removes = 0;
      final persistence = PlaybackQueueWebPersistence(
        write: (_) async => throw StateError('storage disabled'),
        remove: () async => removes++,
      );

      final result = await persistence.save([_song(1), _song(2)], 0);

      expect(result.saved, isFalse);
      expect(result.error, isA<StateError>());
      expect(removes, 2);
    });
  });
}
