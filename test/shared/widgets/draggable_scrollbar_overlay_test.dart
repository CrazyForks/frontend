import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songloft_flutter/shared/widgets/draggable_scrollbar_overlay.dart';

void main() {
  testWidgets('多个 scroll position 过渡态不会抛出异常', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: MaterialApp(
          home: SizedBox(
            width: 320,
            height: 320,
            child: DraggableScrollbarOverlay(
              scrollController: controller,
              totalItemCount: 40,
              child: Stack(
                children: [
                  ListView.builder(
                    controller: controller,
                    itemCount: 40,
                    itemBuilder: (context, index) => Text('first $index'),
                  ),
                  ListView.builder(
                    controller: controller,
                    itemCount: 40,
                    itemBuilder: (context, index) => Text('second $index'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
