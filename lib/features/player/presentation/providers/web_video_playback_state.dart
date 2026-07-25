import 'package:flutter/foundation.dart';

/// Web HLS 视频主控模式的播放状态。
///
/// 当 Web 端播放浏览器不原生支持的视频格式（通过后端 HLS 转码）时，
/// 使用单个非静音 `<video>` 元素作为唯一播放源，不经过 just_audio。
/// 由 WebVideoPlaybackNotifier 桥接 video 元素事件到 PlayerState。
///
/// 纯 Dart 数据类，被 web / stub 两个实现共享（原生构建不牵入 package:web）。
@immutable
class WebVideoPlaybackState {
  /// 是否处于 HLS video primary 模式（video 元素接管播放）。
  final bool isActive;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;

  const WebVideoPlaybackState({
    this.isActive = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  WebVideoPlaybackState copyWith({
    bool? isActive,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
  }) {
    return WebVideoPlaybackState(
      isActive: isActive ?? this.isActive,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}
