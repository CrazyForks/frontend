import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'web_video_playback_state.dart';

// hls.js 桥接
@JS('SongloftHls.canUse')
external bool _hlsCanUse();

@JS('SongloftHls.attach')
external void _hlsAttach(
  web.HTMLVideoElement element,
  String url,
  JSFunction onError,
);

@JS('SongloftHls.destroy')
external void _hlsDestroy(web.HTMLVideoElement element);

// hls.js 音轨切换（操作 video 元素上的 hls.js 实例）
@JS('SongloftHls.setAudioTrack')
external void _hlsSetAudioTrack(web.HTMLVideoElement element, int index);

/// Web HLS 视频播放控制器（Web 实现）。
///
/// **独立于 widget 树管理 video 元素**：调用 [startPlayback] 时即创建 `<video>`
/// 元素并挂到 DOM（不可见，仅播放音视频），确保小播放器模式下也能出声。
/// [WebVideoView] widget 挂载时复用该 video 元素渲染画面。
class WebVideoPlaybackNotifier extends Notifier<WebVideoPlaybackState> {
  web.HTMLVideoElement? _video;
  bool _hlsAttached = false;
  bool _autoplayAttempted = false;

  @override
  WebVideoPlaybackState build() {
    return const WebVideoPlaybackState();
  }

  /// 获取 video 元素引用（供 widget 渲染画面等）。
  web.HTMLVideoElement? get videoElement => _video;

  /// 启动 HLS 视频播放：创建 video 元素、加载 hls.js、开始播放。
  /// 调用后 video 元素即存在于 DOM 中并播放音视频（无需 widget 挂载）。
  void startPlayback(String url) {
    // 清理旧实例
    _cleanup();
    _autoplayAttempted = false;

    // 创建 video 元素（不可见，追加到 document.body）
    final el = web.document.createElement('video') as web.HTMLVideoElement;
    el.muted = false; // 非静音：音频从 video 出
    el.autoplay = true;
    el.controls = false;
    el.setAttribute('playsinline', 'true');
    // 隐藏元素（不占位，但在 DOM 中存在可播放）
    el.style
      ..position = 'fixed'
      ..width = '1px'
      ..height = '1px'
      ..opacity = '0'
      ..pointerEvents = 'none'
      ..zIndex = '-9999';
    web.document.body?.append(el);
    _video = el;

    // 监听事件
    _setupEvents(el);

    // 加载 HLS
    if (_hlsCanUse()) {
      _hlsAttached = true;
      _hlsAttach(
        el,
        url,
        ((JSString message) {
          debugPrint('[WebVideoPlayback] HLS error: ${message.toDart}');
          _hlsAttached = false;
        }).toJS,
      );
    } else {
      el.src = url;
    }

    state = state.copyWith(isActive: true, isBuffering: true);
    debugPrint('[WebVideoPlayback] startPlayback: $url');
  }

  /// 停止播放并清理 video 元素（切歌或切到非 HLS 视频时调用）。
  void stopPlayback() {
    _cleanup();
    state = const WebVideoPlaybackState();
    debugPrint('[WebVideoPlayback] stopPlayback');
  }

  /// 通过 hls.js audioTrack API 即时切换音轨（无需重载）。
  /// video 元素不存在或未走 hls.js 时安全 no-op。
  void setAudioTrack(int index) {
    final el = _video;
    if (el == null || !_hlsAttached) return;
    _hlsSetAudioTrack(el, index);
  }

  void _cleanup() {
    final el = _video;
    if (el != null) {
      if (_hlsAttached) {
        _hlsDestroy(el);
        _hlsAttached = false;
      }
      el.pause();
      el.removeAttribute('src');
      el.remove(); // 从 DOM 移除
    }
    _video = null;
  }

  void _setupEvents(web.HTMLVideoElement el) {
    // 显式 play() 并捕获 rejection：非静音视频可能被浏览器 autoplay 策略拒绝
    // （NotAllowedError），仅靠 autoplay 属性会无声失败、永远停在 0 秒，
    // UI 表现为「缓冲充足但画面不动、持续转圈」。首帧就绪时若仍暂停则
    // 主动尝试一次 play()，被拒时退出 buffering 态让用户可手动点播。
    // 仅首次 canplay 尝试，避免用户暂停后 seek 触发的 canplay 意外恢复播放。
    el.addEventListener(
      'canplay',
      ((web.Event e) {
        if (!state.isActive || _autoplayAttempted) return;
        _autoplayAttempted = true;
        if (!el.paused) return;
        el.play().toDart.catchError((Object err) {
          debugPrint('[WebVideoPlayback] play() rejected: $err');
          if (state.isActive) {
            state = state.copyWith(isPlaying: false, isBuffering: false);
          }
          return null;
        });
      }).toJS,
    );
    // 诊断日志：缓冲中断 / 解码错误是「卡顿」排查的关键证据
    el.addEventListener(
      'stalled',
      ((web.Event e) {
        debugPrint(
          '[WebVideoPlayback] stalled: pos=${el.currentTime.toStringAsFixed(2)}s '
          'readyState=${el.readyState}',
        );
      }).toJS,
    );
    el.addEventListener(
      'error',
      ((web.Event e) {
        final err = el.error;
        debugPrint(
          '[WebVideoPlayback] media error: code=${err?.code} '
          'message=${err?.message}',
        );
        if (!state.isActive) return;
        state = state.copyWith(isPlaying: false, isBuffering: false);
      }).toJS,
    );
    el.addEventListener(
      'timeupdate',
      ((web.Event e) {
        if (!state.isActive) return;
        state = state.copyWith(
          position: Duration(milliseconds: (el.currentTime * 1000).toInt()),
        );
      }).toJS,
    );
    el.addEventListener(
      'durationchange',
      ((web.Event e) {
        if (!state.isActive) return;
        if (el.duration.isFinite && el.duration > 0) {
          state = state.copyWith(
            duration: Duration(milliseconds: (el.duration * 1000).toInt()),
          );
        }
      }).toJS,
    );
    el.addEventListener(
      'play',
      ((web.Event e) {
        if (!state.isActive) return;
        state = state.copyWith(isPlaying: true, isBuffering: false);
      }).toJS,
    );
    el.addEventListener(
      'pause',
      ((web.Event e) {
        if (!state.isActive) return;
        state = state.copyWith(isPlaying: false);
      }).toJS,
    );
    el.addEventListener(
      'waiting',
      ((web.Event e) {
        if (!state.isActive) return;
        state = state.copyWith(isBuffering: true);
      }).toJS,
    );
    el.addEventListener(
      'playing',
      ((web.Event e) {
        if (!state.isActive) return;
        state = state.copyWith(isBuffering: false);
      }).toJS,
    );
    el.addEventListener(
      'ended',
      ((web.Event e) {
        if (!state.isActive) return;
        state = state.copyWith(isPlaying: false, isBuffering: false);
      }).toJS,
    );
  }

  // ========== 播放控制 ==========

  void play() {
    _video?.play();
  }

  void pause() {
    _video?.pause();
  }

  void seek(Duration position) {
    final el = _video;
    if (el != null) {
      el.currentTime = position.inMilliseconds / 1000.0;
    }
  }
}

/// Web HLS 视频播放状态 Provider。
final webVideoPlaybackProvider =
    NotifierProvider<WebVideoPlaybackNotifier, WebVideoPlaybackState>(
      WebVideoPlaybackNotifier.new,
    );
