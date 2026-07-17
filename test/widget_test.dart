import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:songloft_flutter/config/app_config.dart';
import 'package:songloft_flutter/core/router/app_router.dart';
import 'package:songloft_flutter/main.dart';

void main() {
  // SongloftApp 的 _getScreenType 会读取 AppConfig.isTvMode（late final），
  // 测试不经过 main() 初始化，需在此显式赋值一次，避免 LateInitializationError。
  AppConfig.isTvMode = false;

  testWidgets('Songloft app smoke test', (WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => const Scaffold(
                body: Center(child: Text('Songloft app test')),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [routerProvider.overrideWithValue(router)],
        child: const SongloftApp(),
      ),
    );

    // Verify that our app shell can render with the test router.
    expect(find.text('Songloft app test'), findsOneWidget);
  });
}
