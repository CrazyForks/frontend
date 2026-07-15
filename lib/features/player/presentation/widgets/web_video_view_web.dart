import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../../../core/utils/url_helper.dart';
import '../../../../shared/models/song.dart';
import '../../domain/player_state.dart';
import '../providers/player_provider.dart';

/// Web 平台视频画面：用原生 `<video>`（**静音**）显示画面，音频仍由 just_audio_web 的
/// `<audio>` 播放（含 hls.js 电台路径完全不受影响），二者按 [playerStateProvider] 的
/// 播放/暂停/进度保持同步。
///
/// 设计取舍：不替换 Web 的音频引擎，画面元素独立且静音，与音频按事件+漂移阈值同步。
/// 好处是**零回归**（不碰 hls.js / just_audio_web），代价是画面与音频可能有轻微漂移、
/// 视频容器被音视频两个元素各拉取一次。视频不可用/加载失败时回退 [fallback]（由外层
/// VideoStage 决定何时使用本组件）。
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
  /// 每个实例用唯一 viewType，避免 registerViewFactory 重复注册抛错。
  static int _seq = 0;

  late final String _viewType;
  web.HTMLVideoElement? _video;

  String _videoSrc() => UrlHelper.buildVideoUrl(widget.song.url ?? '');

  @override
  void initState() {
    super.initState();
    _viewType = 'songloft-video-${_seq++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final el = web.document.createElement('video') as web.HTMLVideoElement;
      el
        ..muted = true // 音频走 just_audio_web，视频仅出画面
        ..autoplay = false
        ..controls = false
        ..src = _videoSrc();
      el.setAttribute('playsinline', 'true');
      el.style
        ..width = '100%'
        ..height = '100%'
        ..backgroundColor = 'black';
      el.style.setProperty('object-fit', 'contain');
      _video = el;
      return el;
    });
  }

  @override
  void didUpdateWidget(covariant WebVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _video?.src = _videoSrc();
    }
  }

  @override
  void dispose() {
    final el = _video;
    if (el != null) {
      el.pause();
      el.removeAttribute('src');
    }
    _video = null;
    super.dispose();
  }

  /// 按播放状态同步 `<video>`：播放/暂停跟随，进度漂移超阈值才 seek（避免抖动）。
  void _sync(PlayerState state) {
    final el = _video;
    if (el == null) return;
    if (state.isPlaying && el.paused) {
      el.play(); // muted，浏览器允许自动播放
    } else if (!state.isPlaying && !el.paused) {
      el.pause();
    }
    final target = state.currentTime.inMilliseconds / 1000.0;
    if ((el.currentTime - target).abs() > 0.5) {
      el.currentTime = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerStateProvider);
    // 状态变化（含进度 tick）后在帧回调里同步，避免在 build 中触发副作用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(state);
    });

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
}
