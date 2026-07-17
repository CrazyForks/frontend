import 'package:flutter/material.dart';

import '../../core/theme/tv_theme.dart';
import '../../core/utils/formatters.dart';
import '../models/song.dart';
import 'cover_image.dart';
import 'tv_focusable.dart';

/// TV 端歌曲列表大行
///
/// 用 [TvFocusableContainer] 提供 D-pad 焦点，行高不小于 [TvTheme.listItemMinHeight]，
/// 字号走 [TvTheme]。供曲库扁平列表 / 歌单详情 / 分类下钻复用。
class TvSongTile extends StatelessWidget {
  /// 歌曲数据
  final Song song;

  /// 序号（1 基，用于列表前缀）
  final int index;

  /// 是否为当前正在播放的歌曲
  final bool isCurrentSong;

  /// 是否正在播放（配合 [isCurrentSong] 显示均衡器动画图标）
  final bool isPlaying;

  /// 是否自动获取焦点（每页仅一个为 true）
  final bool autofocus;

  /// Enter/Select 或点击触发
  final VoidCallback? onSelect;

  const TvSongTile({
    super.key,
    required this.song,
    required this.index,
    this.isCurrentSong = false,
    this.isPlaying = false,
    this.autofocus = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = _buildSubtitle();
    final titleColor =
        isCurrentSong ? colorScheme.primary : colorScheme.onSurface;

    return TvFocusableContainer(
      autofocus: autofocus,
      onSelect: onSelect,
      borderRadius: BorderRadius.circular(TvTheme.cardRadius),
      padding: const EdgeInsets.symmetric(
        horizontal: TvTheme.spacingMedium,
        vertical: TvTheme.spacingSmall,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TvTheme.listItemMinHeight),
        child: Row(
          children: [
            // 序号 / 正在播放指示
            SizedBox(
              width: 40,
              child: Center(
                child:
                    isCurrentSong && isPlaying
                        ? Icon(
                          Icons.equalizer_rounded,
                          color: colorScheme.primary,
                          size: 24,
                        )
                        : Text(
                          '$index',
                          style: TvTheme.captionStyle(context),
                          textAlign: TextAlign.center,
                        ),
              ),
            ),
            const SizedBox(width: TvTheme.spacingMedium),
            // 封面
            CoverImage(
              coverUrl: song.coverUrl,
              size: 56,
              borderRadius: 8,
              placeholderIcon: Icons.music_note,
            ),
            const SizedBox(width: TvTheme.spacingMedium),
            // 标题 + 副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    style: TvTheme.bodyStyle(context).copyWith(
                      color: titleColor,
                      fontWeight:
                          isCurrentSong ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TvTheme.captionStyle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: TvTheme.spacingMedium),
            // 时长
            if (song.duration > 0)
              Text(
                Formatters.formatDuration(song.duration),
                style: TvTheme.captionStyle(context),
              ),
          ],
        ),
      ),
    );
  }

  /// 副标题：艺术家 · 专辑（缺省项自动省略）
  String _buildSubtitle() {
    final parts = <String>[];
    final artist = song.artist;
    final album = song.album;
    if (artist != null && artist.isNotEmpty) parts.add(artist);
    if (album != null && album.isNotEmpty) parts.add(album);
    return parts.join(' · ');
  }
}
