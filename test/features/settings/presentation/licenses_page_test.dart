import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/settings/presentation/licenses_page.dart';

/// 许可合规回归（songloft-org/songloft#341）。
///
/// 客户端二进制链接 GPL-3.0-only 的 WebF，整体按 GPL-3.0 分发；GPLv3 §4/§5 要求
/// 分发时**随附**许可全文。我们靠 `pubspec.yaml` 的 `assets:` 声明把全文打进安装包
/// （这条路径在签名之前，故零签名风险且一次覆盖全部平台）。
///
/// 这两个用例守的就是那条 pubspec 声明：一旦有人删掉 `assets:` 里的
/// `LICENSES/GPL-3.0.txt` / `NOTICE`，`rootBundle.loadString` 会抛异常，测试立刻红。
/// 没有它，回归表现只是「App 里点开许可页显示加载失败」，极难在 review 里发现。
void main() {
  // rootBundle 走 ServicesBinding，必须先初始化 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled license assets', () {
    test('GPL-3.0 full text is bundled and complete', () async {
      final text = await rootBundle.loadString(LicensesPage.gplAsset);
      // 首尾与关键条款都在，确认不是被截断的占位文件。
      expect(text, contains('GNU GENERAL PUBLIC LICENSE'));
      expect(text, contains('Version 3, 29 June 2007'));
      expect(text, contains('6. Conveying Non-Source Forms.'));
      expect(text, contains('END OF TERMS AND CONDITIONS'));
      // 全文约 35 KB；明显短于此说明拿到的不是完整许可证。
      expect(text.length, greaterThan(30000));
    });

    test('NOTICE is bundled and names the GPL-triggering dependency', () async {
      final text = await rootBundle.loadString(LicensesPage.noticeAsset);
      expect(text, contains('DISTRIBUTION LICENSE'));
      expect(text, contains('WebF'));
      expect(text, contains('GPL-3.0-only'));
      expect(text, contains('THIRD-PARTY COMPONENTS'));
    });
  });
}
