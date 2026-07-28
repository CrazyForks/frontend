import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songloft_flutter/features/settings/data/scan_api.dart';
import 'package:songloft_flutter/features/settings/data/settings_api.dart';
import 'package:songloft_flutter/features/settings/presentation/duplicate_check_page.dart';
import 'package:songloft_flutter/features/settings/presentation/providers/settings_provider.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';

/// 可编排的 ScanApi 替身，覆盖指纹相关的四个端点。
class _FakeScanApi extends ScanApi {
  _FakeScanApi({required this.status, required this.progress})
    : super(dio: Dio());

  FingerprintStatus status;
  FingerprintProgress progress;
  int cancelCalls = 0;
  int startCalls = 0;
  bool? lastRecomputeAll;
  bool? lastRetryFailed;

  @override
  Future<FingerprintStatus> getFingerprintStatus() async => status;

  @override
  Future<FingerprintProgress> getFingerprintProgress() async => progress;

  @override
  Future<void> startFingerprintCompute({
    bool recomputeAll = false,
    bool retryFailed = false,
  }) async {
    startCalls++;
    lastRecomputeAll = recomputeAll;
    lastRetryFailed = retryFailed;
  }

  @override
  Future<bool> cancelFingerprintCompute() async {
    cancelCalls++;
    // 取消后回到「未在跑」状态，让页面能收敛到 status 阶段
    progress = FingerprintProgress(
      status: 'cancelled',
      computed: progress.computed,
      total: progress.total,
      failed: progress.failed,
    );
    return true;
  }

  @override
  Future<DuplicatesResult> getDuplicates() async =>
      DuplicatesResult(groups: const [], totalGroups: 0, totalDuplicates: 0);
}

/// 记录写入值的 SettingsApi 替身。
class _FakeSettingsApi extends SettingsApi {
  _FakeSettingsApi() : super(dio: Dio());

  bool autoFingerprint = false;
  final List<bool> writes = [];

  @override
  Future<bool> getScanAutoFingerprint() async => autoFingerprint;

  @override
  Future<void> setScanAutoFingerprint(bool enabled) async {
    writes.add(enabled);
    autoFingerprint = enabled;
  }
}

/// 把重复检测页挂在中文 locale 的 MaterialApp 下，并注入 ScanApi 替身。
Widget _wrapPage(_FakeScanApi api) {
  return ProviderScope(
    overrides: [scanApiProvider.overrideWithValue(api)],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('zh'),
      home: DuplicateCheckPage(),
    ),
  );
}

FingerprintStatus _status({
  int total = 10,
  int computed = 0,
  int missing = 10,
  int failed = 0,
  bool available = true,
  bool autoEnabled = false,
}) {
  return FingerprintStatus(
    chromaprintAvailable: available,
    total: total,
    computed: computed,
    missing: missing,
    failed: failed,
    autoEnabled: autoEnabled,
  );
}

void main() {
  testWidgets('计算中阶段显示「停止计算」按钮，点击后调用取消端点', (tester) async {
    final api = _FakeScanApi(
      status: _status(computed: 3, missing: 7),
      progress: FingerprintProgress(
        status: 'running',
        computed: 3,
        total: 10,
        failed: 0,
      ),
    );

    await tester.pumpWidget(_wrapPage(api));
    await tester.pumpAndSettle();

    // 页面初始化时探到任务在跑 → 直接进入 computing 阶段
    expect(find.text('停止计算'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('停止计算'));
    await tester.pumpAndSettle();

    expect(api.cancelCalls, 1);
    // 取消后确定性地回到状态阶段（轮询已先停，不会被抢去结果页）
    expect(find.text('停止计算'), findsNothing);
    expect(find.text('指纹统计'), findsOneWidget);
  });

  testWidgets('存在无法计算的歌曲时显示计数与不自动重试的说明', (tester) async {
    final api = _FakeScanApi(
      status: _status(total: 10, computed: 7, missing: 0, failed: 3),
      progress: FingerprintProgress(
        status: 'done',
        computed: 7,
        total: 10,
        failed: 3,
      ),
    );

    await tester.pumpWidget(_wrapPage(api));
    await tester.pumpAndSettle();

    expect(find.text('无法计算'), findsOneWidget);
    expect(
      find.textContaining('不会被自动重试'),
      findsOneWidget,
      reason: '必须告知用户失败项不会每次扫描都重跑（#323 的行为变化）',
    );
    // 全部待计算已清零，主按钮应变为「检测重复」
    expect(find.text('重新计算全部指纹'), findsOneWidget);
  });

  testWidgets('全部歌曲都失败时仍提供「重新计算全部指纹」入口', (tester) async {
    final api = _FakeScanApi(
      status: _status(total: 4, computed: 0, missing: 0, failed: 4),
      progress: FingerprintProgress(
        status: 'done',
        computed: 0,
        total: 4,
        failed: 4,
      ),
    );

    await tester.pumpWidget(_wrapPage(api));
    await tester.pumpAndSettle();

    expect(find.text('重新计算全部指纹'), findsOneWidget);
    await tester.tap(find.text('重新计算全部指纹'));
    await tester.pumpAndSettle();
    expect(api.lastRecomputeAll, isTrue);
  });

  testWidgets('存在失败项时提供「仅重试失败项」入口，只带 retry_failed 参数', (tester) async {
    final api = _FakeScanApi(
      status: _status(total: 10, computed: 7, missing: 0, failed: 3),
      progress: FingerprintProgress(
        status: 'done',
        computed: 7,
        total: 10,
        failed: 3,
      ),
    );

    await tester.pumpWidget(_wrapPage(api));
    await tester.pumpAndSettle();

    // 失败项入口：保留已算好的指纹，只重试失败歌曲（ffmpeg 升级后的恢复路径）
    expect(find.text('仅重试失败项'), findsOneWidget);
    await tester.tap(find.text('仅重试失败项'));
    await tester.pumpAndSettle();
    expect(api.lastRetryFailed, isTrue);
    expect(api.lastRecomputeAll, isFalse);
  });

  testWidgets('无失败项时不显示「仅重试失败项」按钮', (tester) async {
    final api = _FakeScanApi(
      status: _status(total: 10, computed: 10, missing: 0, failed: 0),
      progress: FingerprintProgress(
        status: 'done',
        computed: 10,
        total: 10,
        failed: 0,
      ),
    );

    await tester.pumpWidget(_wrapPage(api));
    await tester.pumpAndSettle();

    expect(find.text('仅重试失败项'), findsNothing);
  });

  test('scanAutoFingerprintProvider 默认关闭，setValue 写入业务端点', () async {
    final api = _FakeSettingsApi();
    final container = ProviderContainer(
      overrides: [settingsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    expect(await container.read(scanAutoFingerprintProvider.future), isFalse);

    await container.read(scanAutoFingerprintProvider.notifier).setValue(true);
    expect(api.writes, [true]);
    expect(container.read(scanAutoFingerprintProvider).value, isTrue);
  });

  test('读取开关失败时回落为关闭（不误开自动指纹）', () async {
    final container = ProviderContainer(
      overrides: [
        settingsApiProvider.overrideWithValue(_ThrowingSettingsApi()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(scanAutoFingerprintProvider.future), isFalse);
  });
}

class _ThrowingSettingsApi extends SettingsApi {
  _ThrowingSettingsApi() : super(dio: Dio());

  @override
  Future<bool> getScanAutoFingerprint() async => throw Exception('boom');
}
