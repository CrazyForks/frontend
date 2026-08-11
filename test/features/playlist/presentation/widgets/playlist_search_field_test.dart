import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songloft_flutter/features/playlist/presentation/widgets/playlist_search_field.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late ValueNotifier<bool> visible;

  Widget buildHarness() {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder:
              (context, value, child) => PlaylistSearchField(
                visible: value,
                controller: controller,
                focusNode: focusNode,
                onChanged: (_) {},
                onClear: controller.clear,
              ),
        ),
      ),
    );
  }

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    visible = ValueNotifier(false);
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
    visible.dispose();
  });

  Future<void> pumpFocusRequest(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('隐藏时不渲染 TextField', (tester) async {
    await tester.pumpWidget(buildHarness());
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('打开搜索框后获得焦点', (tester) async {
    await tester.pumpWidget(buildHarness());
    expect(focusNode.hasFocus, isFalse);

    visible.value = true;
    await tester.pump();
    await pumpFocusRequest(tester);

    expect(focusNode.hasFocus, isTrue);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('关闭后 TextField 从 tree 移除', (tester) async {
    visible.value = true;
    await tester.pumpWidget(buildHarness());
    await pumpFocusRequest(tester);
    expect(find.byType(TextField), findsOneWidget);

    visible.value = false;
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('异步父级重建期间焦点保持不变', (tester) async {
    visible.value = true;
    await tester.pumpWidget(buildHarness());
    await pumpFocusRequest(tester);
    expect(focusNode.hasFocus, isTrue);

    controller.text = 'xie';
    await tester.pump();
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('输入文本后显示清除按钮', (tester) async {
    visible.value = true;
    await tester.pumpWidget(buildHarness());
    await pumpFocusRequest(tester);

    expect(find.byIcon(Icons.clear), findsNothing);

    controller.text = 'test';
    await tester.pump();

    expect(find.byIcon(Icons.clear), findsOneWidget);
  });
}
