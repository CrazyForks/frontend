// Web HLS 视频播放 Provider 的条件导出（镜像 web_video_view.dart 的写法）。
// 默认（web）用 _web.dart（package:web + hls.js 桥接管理 <video> 元素）；
// dart.library.io（原生）用 _stub.dart（全 no-op），避免把 package:web /
// dart:js_interop 拉进原生构建（会直接编译失败）。
//
// 跨平台消费方（player_provider / audio_track_provider）只 import 本文件，
// 调用点均有 kIsWeb 守卫；WebVideoPlaybackState 为共享纯 Dart 数据类。
export 'web_video_playback_state.dart';
export 'web_video_playback_provider_web.dart'
    if (dart.library.io) 'web_video_playback_provider_stub.dart';
