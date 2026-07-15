import 'package:flutter/widgets.dart';

import '../../../../shared/models/song.dart';

/// 非 Web 平台的空实现：原生端视频画面由 media_kit 渲染（见 VideoStage），
/// 这里恒回退 [fallback]。运行时不会被调用（VideoStage 仅在 kIsWeb 时使用本组件），
/// 存在仅为原生构建可编译。
class WebVideoView extends StatelessWidget {
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
  Widget build(BuildContext context) => fallback;
}
