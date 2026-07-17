import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tv_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/song.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import '../../../shared/widgets/tv_song_tile.dart';
import '../../../shared/widgets/tv_entity_detail_view.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../../playlist/presentation/providers/playlist_provider.dart'
    show PaginatedSongsState;
import 'providers/category_provider.dart';
import 'widgets/library_view_switcher.dart';

/// TV 版某分类（歌手 / 专辑 / 流派…）下的歌曲页。
///
/// 复用 [TvEntityDetailView]：大封面 header + 「播放全部」焦点按钮 + 焦点歌曲列表。
/// TV 精简掉多选/编辑，聚焦播放与浏览。
class TvCategorySongsPage extends ConsumerStatefulWidget {
  final String field;
  final String value;
  final String? coverUrl;

  const TvCategorySongsPage({
    super.key,
    required this.field,
    required this.value,
    this.coverUrl,
  });

  @override
  ConsumerState<TvCategorySongsPage> createState() =>
      _TvCategorySongsPageState();
}

class _TvCategorySongsPageState extends ConsumerState<TvCategorySongsPage> {
  final _scrollController = ScrollController();

  ({String field, String value}) get _key =>
      (field: widget.field, value: widget.value);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(categorySongsProvider(_key).notifier).loadMore();
    }
  }

  void _onSongTap(List<Song> songs, int index) {
    ref
        .read(playerStateProvider.notifier)
        .playPlaylist(songs, startIndex: index);
  }

  Future<void> _playAll() async {
    final l10n = AppLocalizations.of(context);
    await ref.read(categorySongsProvider(_key).notifier).loadAll();
    if (!mounted) return;
    final songs = ref.read(categorySongsProvider(_key)).value?.items ?? [];
    if (songs.isEmpty) {
      ResponsiveSnackBar.show(context, message: l10n.libraryNoPlayableSongs);
      return;
    }
    ref.read(playerStateProvider.notifier).playPlaylist(songs, startIndex: 0);
    if (!mounted) return;
    ResponsiveSnackBar.show(
      context,
      message: l10n.libraryPlayingAllSongs(songs.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final songsAsync = ref.watch(categorySongsProvider(_key));
    final state = songsAsync.value;
    final total = state?.total ?? state?.items.length ?? 0;

    return TvEntityDetailView(
      scrollController: _scrollController,
      coverUrl: widget.coverUrl,
      placeholderIcon: libraryViewIcon(widget.field),
      title: categoryValueLabel(l10n, widget.field, widget.value),
      subtitle:
          '${categoryFieldLabel(l10n, widget.field)} · '
          '${l10n.categorySongCount(total)}',
      onPlayAll: (state?.items.isEmpty ?? true) ? null : _playAll,
      playAllLabel: l10n.libraryPlayAll,
      bodySlivers: _buildBodySlivers(context, songsAsync),
    );
  }

  List<Widget> _buildBodySlivers(
    BuildContext context,
    AsyncValue<PaginatedSongsState> songsAsync,
  ) {
    final l10n = AppLocalizations.of(context);
    return songsAsync.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
      error: (error, _) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(TvTheme.contentPadding),
            child: Center(
              child: Text(
                '${l10n.commonLoadFailed}\n$error',
                style: TvTheme.captionStyle(context),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
      data: (state) {
        if (state.items.isEmpty) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(TvTheme.contentPadding),
                child: Center(
                  child: Text(
                    l10n.categorySongsEmpty,
                    style: TvTheme.titleStyle(context),
                  ),
                ),
              ),
            ),
          ];
        }
        final currentSong = ref.watch(currentSongProvider);
        final isPlaying = ref.watch(isPlayingProvider);
        final songs = state.items;
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: TvTheme.contentPadding,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final song = songs[index];
                final isCurrent = currentSong?.id == song.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: TvTheme.spacingSmall),
                  child: TvSongTile(
                    song: song,
                    index: index + 1,
                    isCurrentSong: isCurrent,
                    isPlaying: isCurrent && isPlaying,
                    onSelect: () => _onSongTap(songs, index),
                  ),
                );
              }, childCount: songs.length),
            ),
          ),
          if (state.isLoadingMore)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(TvTheme.spacingLarge),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ];
      },
    );
  }
}
