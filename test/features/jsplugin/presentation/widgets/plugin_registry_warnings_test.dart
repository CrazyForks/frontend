import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/jsplugin/presentation/widgets/plugin_registry.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';

void main() {
  testWidgets('警告默认保持紧凑并可查看完整详情', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const rawWarning =
        'failed to fetch plugin.json https://example.com/a-very-long-path';
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PluginRegistryWarningsBanner(
            warnings: [rawWarning, 'second warning'],
          ),
        ),
      ),
    );

    expect(find.text('部分插件信息未能加载（2 条警告）'), findsOneWidget);
    expect(find.text(rawWarning), findsNothing);
    expect(
      tester.getSize(find.byType(PluginRegistryWarningsBanner)).height,
      lessThan(80),
    );

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('加载警告'), findsOneWidget);
    expect(find.textContaining(rawWarning), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('警告详情在横屏窄高视口内可滚动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PluginRegistryWarningsBanner(
            warnings: List.generate(20, (index) => 'warning $index details'),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('加载警告'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
