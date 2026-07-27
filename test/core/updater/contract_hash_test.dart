import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/core/updater/version_compare.dart';

/// 原生契约哈希闸的核心判定（`contractHashBlocks`）测试。
///
/// checkPatch / NativeContractService 的完整链路受 `Platform.isAndroid` 守卫，
/// 无法在非 Android 测试宿主上跑通；故把闸的判定抽成纯函数在此覆盖三条路径：
/// 匹配放行、不匹配阻断、任一为空降级不阻断。
void main() {
  group('contractHashBlocks', () {
    const a = 'aaaa1111';
    const b = 'bbbb2222';

    test('两端非空且相同 → 不阻断（放行热更）', () {
      expect(contractHashBlocks(a, a), isFalse);
    });

    test('两端非空且不同 → 阻断（落整包）', () {
      expect(contractHashBlocks(a, b), isTrue);
    });

    test('manifest 哈希为空（老式 manifest）→ 降级不阻断', () {
      expect(contractHashBlocks('', b), isFalse);
    });

    test('设备哈希为空（老宿主无 contract channel / 本地开发无 asset）→ 降级不阻断', () {
      expect(contractHashBlocks(a, ''), isFalse);
    });

    test('两端都空 → 降级不阻断', () {
      expect(contractHashBlocks('', ''), isFalse);
    });
  });
}
