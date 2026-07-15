import 'package:flutter/foundation.dart';

/// 音频后端选择（songloft-org/songloft#76 阶段三/四）。
///
/// 决定各原生平台的 just_audio 后端是否使用 media_kit(libmpv)：
/// - **Windows / Linux**：恒用 media_kit（EQ 依赖它），已含视频输出。
/// - **macOS / Android / iOS**：**默认也用 media_kit**，统一后端并直接支持应用内视频画面。
///   保留编译期开关作为 **kill-switch**：若某平台的 media_kit 后端出现问题（后台/锁屏/
///   控制中心/Live Activity/打断等系统集成回归），可传 `=false` 回退到各自的原生后端
///   （AVPlayer / ExoPlayer），无需改代码。
///
/// 回退方式（出问题时）：
/// ```
/// flutter run   -d macos   --dart-define=SONGLOFT_MEDIAKIT_MACOS=false
/// flutter build apk        --dart-define=SONGLOFT_MEDIAKIT_MOBILE=false
/// flutter build ipa        --dart-define=SONGLOFT_MEDIAKIT_MOBILE=false
/// ```
///
/// 视频画面能力与音频后端绑定：只有实际使用 media_kit 后端的平台才能派生
/// [VideoController] 渲染画面，故 [isInAppVideoSupported] 直接读 [usesMediaKit]。
class AudioBackend {
  AudioBackend._();

  /// macOS 是否用 media_kit 后端（默认 true；传 `=false` 回退原生 AVPlayer）。
  static const bool _macosMediaKit =
      bool.fromEnvironment('SONGLOFT_MEDIAKIT_MACOS', defaultValue: true);

  /// Android / iOS 是否用 media_kit 后端（默认 true；传 `=false` 回退原生
  /// ExoPlayer/AVPlayer）。这是移动端的 kill-switch，供 media_kit 出问题时快速回退。
  static const bool _mobileMediaKit =
      bool.fromEnvironment('SONGLOFT_MEDIAKIT_MOBILE', defaultValue: true);

  /// 当前平台是否使用 media_kit(libmpv) 作为 just_audio 音频后端。
  static bool get usesMediaKit {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.macOS:
        return _macosMediaKit;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return _mobileMediaKit;
      default:
        return false;
    }
  }
}
