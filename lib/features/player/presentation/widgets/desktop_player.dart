import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/cover_url.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/favorite_button.dart';
import '../../domain/player_state.dart';
import '../providers/player_provider.dart';
import 'lyrics_view.dart';
import 'play_controls.dart';
import 'progress_bar.dart';
import 'popup_controls.dart';
import 'volume_control.dart';

/// 桌面端底部播放器栏
class DesktopPlayer extends ConsumerWidget {
  const DesktopPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final theme = Theme.of(context);

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          // 顶部进度条（可点击）
          ClickableProgressBar(
            position: state.currentTime,
            duration: state.duration,
            onSeek: notifier.seek,
            height: 4,
          ),
          // 主内容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // 左侧：歌曲信息
                  Expanded(flex: 3, child: _buildSongInfo(context, state)),
                  // 中间：播放控制
                  Expanded(
                    flex: 4,
                    child: _buildPlayControls(context, state, notifier),
                  ),
                  // 右侧：工具栏
                  Expanded(
                    flex: 3,
                    child: _buildToolbar(context, state, notifier),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context, PlayerState state) {
    final theme = Theme.of(context);

    if (!state.hasSong) {
      return Row(
        children: [
          // 空封面
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              Icons.music_note_rounded,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '无播放内容',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      );
    }

    final song = state.currentSong!;
    final coverUrl = CoverUrl.buildCoverUrl(
      coverUrl: song.coverUrl,
      coverPath: song.coverPath,
    );

    return Row(
      children: [
        // 封面
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          clipBehavior: Clip.antiAlias,
          child:
              coverUrl != null
                  ? Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, _, _) => Icon(
                          Icons.music_note_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  )
                  : Icon(
                    Icons.music_note_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
        ),
        const SizedBox(width: 12),
        // 标题和艺术家
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                song.artist ?? '未知艺术家',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 收藏按钮
        FavoriteButton(songId: song.id, size: 20),
      ],
    );
  }

  Widget _buildPlayControls(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 控制按钮
        PlayControls(
          isPlaying: state.isPlaying,
          hasPrev: state.hasPrev,
          hasNext: state.hasNext,
          isBuffering: state.isBuffering,
          onPlay: notifier.togglePlay,
          onPause: notifier.togglePlay,
          onPrev: notifier.playPrev,
          onNext: notifier.playNext,
          size: 40,
        ),
        const SizedBox(height: 4),
        // 时间显示
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              Formatters.formatDuration(state.currentTime.inSeconds.toDouble()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              ' / ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              Formatters.formatDuration(state.duration.inSeconds.toDouble()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 播放模式
        _buildPlayModeButton(context, state, notifier, theme),
        // 音量控制：使用响应式组件自动适配
        Flexible(
          child: ResponsiveVolumeControl(
            volume: state.volume,
            onVolumeChanged: notifier.setVolume,
          ),
        ),
        // 睡眠定时
        _buildSleepTimerButton(context, state, notifier, theme),
        // 歌词按钮
        _buildLyricsButton(context, state, theme),
        // 播放列表
        IconButton(
          onPressed: notifier.togglePlaylistDrawer,
          icon: Icon(
            Icons.queue_music_rounded,
            size: 20,
            color: state.showPlaylistDrawer ? theme.colorScheme.primary : null,
          ),
          tooltip: '播放列表',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  /// 构建播放模式按钮（使用自定义弹出层）
  Widget _buildPlayModeButton(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
    ThemeData theme,
  ) {
    return PopupPlayModeControl(
      playMode: state.playMode,
      onPlayModeChanged: notifier.setPlayMode,
    );
  }

  /// 构建睡眠定时按钮（使用自定义弹出层）
  Widget _buildSleepTimerButton(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
    ThemeData theme,
  ) {
    return PopupSleepTimerControl(
      sleepTimerRemaining: state.sleepTimerRemaining,
      onSetTimer: notifier.setSleepTimer,
      onCancelTimer: notifier.cancelSleepTimer,
    );
  }

  /// 构建歌词按钮
  Widget _buildLyricsButton(
    BuildContext context,
    PlayerState state,
    ThemeData theme,
  ) {
    final hasSong = state.hasSong;
    final hasLyrics =
        hasSong &&
        state.currentSong?.lyric != null &&
        state.currentSong!.lyric!.isNotEmpty;

    return IconButton(
      onPressed: hasSong ? () => _showLyricsDialog(context, state) : null,
      icon: Icon(
        Icons.lyrics_rounded,
        size: 20,
        color:
            hasLyrics
                ? null
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      tooltip: '歌词',
      visualDensity: VisualDensity.compact,
    );
  }

  /// 显示歌词对话框
  void _showLyricsDialog(BuildContext context, PlayerState state) {
    final song = state.currentSong;
    if (song == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _LyricsDialog(song: song),
    );
  }
}

/// 歌词对话框组件
class _LyricsDialog extends ConsumerWidget {
  final dynamic song;

  const _LyricsDialog({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerStateProvider);
    final theme = Theme.of(context);
    final currentSong = state.currentSong;

    // 如果歌曲变化了，关闭对话框
    if (currentSong == null || currentSong.id != song.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      });
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 标题栏
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentSong?.title ?? song.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 歌词内容
            Expanded(
              child: LyricsView(
                lyricText: currentSong?.lyric ?? song.lyric,
                currentPosition: state.currentTime,
                onSeek: ref.read(playerStateProvider.notifier).seek,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
