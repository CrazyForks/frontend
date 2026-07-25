import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../../../core/utils/audio_format_helper.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../../shared/models/song.dart';
import '../../domain/player_state.dart';
import '../providers/player_provider.dart';
import '../providers/web_video_playback_provider.dart';

/// Web 平台视频画面组件。
///
/// **HLS 视频主控模式**（浏览器不原生支持的视频格式，通过后端 HLS 转码）：
/// - 复用 [WebVideoPlaybackNotifier] 管理的 `<video>` 元素渲染画面
/// - video 元素已在 Provider 中创建（即使 widget 未挂载也能播放音频）
/// - 本 widget 只负责把 video 元素的画面渲染到 Flutter widget 树中
///
/// **直出模式**（mp4/webm 等浏览器原生支持的格式）：
/// - 保持旧架构：静音 `<video>` 显示画面，`<audio>` 播放音频并驱动 PlayerState
/// - video 从 audio 的播放进度同步
class WebVideoView extends ConsumerStatefulWidget {
  const WebVideoView({
    super.key,
    required this.song,
    required this.fallback,
    this.width,
    this.height,
    this.borderRadius,
  });

  final Song song;
  final Widget fallback;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  ConsumerState<WebVideoView> createState() => _WebVideoViewState();
}

class _WebVideoViewState extends ConsumerState<WebVideoView> {
  static int _seq = 0;
  late final String _viewType;
  web.HTMLVideoElement? _directVideo; // 直出模式独立 video 元素

  /// 是否为 HLS 主控模式（video 元素接管音视频）
  bool get _isHlsPrimary =>
      !AudioFormatHelper.isWebCompatibleVideo(
        widget.song.format,
        widget.song.filePath,
      );

  @override
  void initState() {
    super.initState();
    _viewType = 'songloft-video-${_seq++}';

    if (_isHlsPrimary) {
      // HLS 主控模式：从 Provider 获取已存在的 video 元素，注册为 platform view 渲染画面
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final vp = ref.read(webVideoPlaybackProvider.notifier);
        final el = vp.videoElement;
        if (el != null) {
          // 将 video 元素从隐藏改为可见
          el.style
            ..position = ''
            ..width = '100%'
            ..height = '100%'
            ..opacity = '1'
            ..pointerEvents = ''
            ..zIndex = '';
          el.style.setProperty('object-fit', 'contain');
          return el;
        }
        // video 元素尚未创建（不应发生）：返回占位黑色 div
        final div = web.document.createElement('div') as web.HTMLDivElement;
        div.style
          ..width = '100%'
          ..height = '100%'
          ..backgroundColor = 'black';
        return div;
      });
    } else {
      // 直出模式：创建独立的 muted video 元素
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final el = web.document.createElement('video') as web.HTMLVideoElement;
        el
          ..muted = true
          ..autoplay = false
          ..controls = false;
        el.setAttribute('playsinline', 'true');
        el.style
          ..width = '100%'
          ..height = '100%'
          ..backgroundColor = 'black';
        el.style.setProperty('object-fit', 'contain');
        el.src = UrlHelper.buildVideoUrl(widget.song.url ?? '');
        _directVideo = el;
        return el;
      });
    }
  }

  @override
  void didUpdateWidget(covariant WebVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id && !_isHlsPrimary) {
      _directVideo?.src = UrlHelper.buildVideoUrl(widget.song.url ?? '');
    }
  }

  @override
  void dispose() {
    if (_isHlsPrimary) {
      // HLS 模式：将 video 元素改回隐藏（仍在 DOM 中播放音频）
      try {
        final vp = ref.read(webVideoPlaybackProvider.notifier);
        final el = vp.videoElement;
        if (el != null) {
          el.style
            ..position = 'fixed'
            ..width = '1px'
            ..height = '1px'
            ..opacity = '0'
            ..pointerEvents = 'none'
            ..zIndex = '-9999';
        }
      } catch (_) {
        // Provider 可能已 dispose，忽略
      }
    } else {
      // 直出模式：清理 video 元素
      final el = _directVideo;
      if (el != null) {
        el.pause();
        el.removeAttribute('src');
      }
      _directVideo = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isHlsPrimary) {
      // 直出模式：按播放状态同步 video
      final state = ref.watch(playerStateProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncFromAudio(state);
      });
    }

    final radius = widget.borderRadius ?? BorderRadius.circular(12);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: HtmlElementView(viewType: _viewType),
        ),
      ),
    );
  }

  /// 直出模式：从 audio 元素的播放状态同步 video 元素。
  void _syncFromAudio(PlayerState state) {
    final el = _directVideo;
    if (el == null || _isHlsPrimary) return;
    if (state.isPlaying && el.paused) {
      el.play();
    } else if (!state.isPlaying && !el.paused) {
      el.pause();
    }
    final target = state.currentTime.inMilliseconds / 1000.0;
    if ((el.currentTime - target).abs() > 0.5) {
      el.currentTime = target;
    }
  }
}
