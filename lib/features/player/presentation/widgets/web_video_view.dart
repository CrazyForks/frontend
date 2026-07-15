// Web 视频画面组件的条件导出（镜像 core/audio/web_audio_platform.dart 的写法）。
// 默认（web）用 _web.dart（package:web + HtmlElementView 渲染 <video>）；
// dart.library.io（原生）用 _stub.dart（直接回退），避免把 package:web / dart:js_interop
// 拉进原生构建。
export 'web_video_view_web.dart'
    if (dart.library.io) 'web_video_view_stub.dart';
