/// 迷你播放条（手机底部小条）显示哪些控制按钮（songloft-org/songloft-player#25）。
///
/// 单行播放条的横向余量全在标题列里，按钮越多标题越早省略，所以做成偏好项由用户自选：
/// - [playOnly]：仅播放/暂停（改动前的行为）
/// - [prevNext]：上一首 / 播放 / 下一首（默认）
/// - [prevNextMode]：再加播放模式按钮
enum MiniPlayerControls {
  playOnly,
  prevNext,
  prevNextMode;

  static MiniPlayerControls fromString(String value) {
    return MiniPlayerControls.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MiniPlayerControls.prevNext,
    );
  }

  /// 是否显示上一首 / 下一首
  bool get hasPrevNext => this != MiniPlayerControls.playOnly;

  /// 是否显示播放模式按钮
  bool get hasPlayMode => this == MiniPlayerControls.prevNextMode;
}
