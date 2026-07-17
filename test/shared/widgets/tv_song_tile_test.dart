import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/shared/models/song.dart';
import 'package:songloft_flutter/shared/widgets/tv_song_tile.dart';
import 'package:songloft_flutter/shared/widgets/tv_view_chip_row.dart';

Song _song() => Song(
  id: 1,
  type: 'local',
  title: '测试歌曲',
  artist: '测试艺术家',
  album: '测试专辑',
  duration: 200,
  addedAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets('TvSongTile 自动获取焦点且 Enter 触发 onSelect', (tester) async {
    var selected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvSongTile(
            song: _song(),
            index: 1,
            autofocus: true,
            onSelect: () => selected = true,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, isTrue);
    expect(find.text('测试歌曲'), findsOneWidget);
  });

  testWidgets('TvViewChipRow 选中项 Enter 回调对应 key', (tester) async {
    String? selectedKey;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvViewChipRow(
            chips: const [
              TvViewChip(key: 'all', label: '全部'),
              TvViewChip(key: 'local', label: '本地'),
            ],
            selectedKey: 'all',
            autofocusSelected: true,
            onSelected: (key) => selectedKey = key,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selectedKey, 'all');
  });
}
