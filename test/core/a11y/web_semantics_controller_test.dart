import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/core/a11y/web_semantics_controller.dart';

void main() {
  group('WebSemanticsController.isMobileWebPlatform', () {
    test('移动端浏览器不常驻语义树（否则 iOS 软键盘弹不出来，#26）', () {
      expect(
        WebSemanticsController.isMobileWebPlatform(TargetPlatform.iOS),
        isTrue,
      );
      expect(
        WebSemanticsController.isMobileWebPlatform(TargetPlatform.android),
        isTrue,
      );
    });

    test('桌面浏览器继续常驻语义树（#186 无障碍）', () {
      for (final platform in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          WebSemanticsController.isMobileWebPlatform(platform),
          isFalse,
          reason: '$platform 应视为桌面',
        );
      }
    });
  });
}
