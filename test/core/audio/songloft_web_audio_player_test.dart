@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:songloft_flutter/core/audio/songloft_web_audio_player.dart';

class _RecordingHtml5AudioPlayer extends Html5AudioPlayer {
  _RecordingHtml5AudioPlayer() : super(id: 'test-player');

  final loadedUris = <Uri>[];

  @override
  Future<Duration?> loadUri(Uri uri, Duration? initialPosition) async {
    loadedUris.add(uri);
    return const Duration(minutes: 1);
  }
}

LoadRequest _request(String childId, String uri) {
  return LoadRequest(
    audioSourceMessage: ConcatenatingAudioSourceMessage(
      id: '',
      children: [ProgressiveAudioSourceMessage(id: childId, uri: uri)],
      useLazyPreparation: true,
      shuffleOrder: const [0],
    ),
    initialIndex: 0,
  );
}

void main() {
  test('完整 load 复用根 ID 时仍加载新子源 URI', () async {
    final player = _RecordingHtml5AudioPlayer();

    await player.load(_request('first-child', 'https://example.com/first.mp3'));
    await player.load(
      _request('second-child', 'https://example.com/second.mp3'),
    );

    expect(player.loadedUris, [
      Uri.parse('https://example.com/first.mp3'),
      Uri.parse('https://example.com/second.mp3'),
    ]);
  });
}
