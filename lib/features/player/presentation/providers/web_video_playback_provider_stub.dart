import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'web_video_playback_state.dart';

/// Web HLS 视频播放控制器（原生 stub）。
///
/// 原生平台视频走 media_kit/libmpv，不存在 HLS video primary 模式；所有调用点
/// 均有 `kIsWeb` 守卫，理论上不会到这。保留同名 API 仅为让 player_provider /
/// audio_track_provider 等跨平台代码通过编译（不牵入 package:web / dart:js_interop）。
class WebVideoPlaybackNotifier extends Notifier<WebVideoPlaybackState> {
  @override
  WebVideoPlaybackState build() {
    return const WebVideoPlaybackState();
  }

  /// 原生端恒为 null（无 video DOM 元素）。
  Object? get videoElement => null;

  void startPlayback(String url) {}

  void stopPlayback() {}

  void setAudioTrack(int index) {}

  void play() {}

  void pause() {}

  void seek(Duration position) {}
}

/// Web HLS 视频播放状态 Provider（原生 stub，状态恒为非激活）。
final webVideoPlaybackProvider =
    NotifierProvider<WebVideoPlaybackNotifier, WebVideoPlaybackState>(
      WebVideoPlaybackNotifier.new,
    );
