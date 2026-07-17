import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tv_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/song.dart';
import '../../../shared/widgets/cover_image.dart';
import '../../../shared/widgets/tv_focusable.dart';
import '../../../shared/widgets/tv_grid_view.dart';
import '../../../shared/widgets/tv_song_tile.dart';
import '../../../shared/widgets/tv_view_chip_row.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../../playlist/domain/playlist.dart';
import '../../playlist/presentation/providers/playlist_provider.dart';
import '../../settings/data/settings_api.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import 'providers/category_provider.dart';
import 'providers/songs_provider.dart';
import 'widgets/library_view_switcher.dart';

/// TV 曲库页
///
/// 单列焦点流：顶部横向焦点 chip 行切视图（歌曲/分类/歌单三组），下方为
/// 焦点歌曲列表 / facet 网格 / 歌单网格。顶部 Tab 导航与底部播放器由 shell 提供。
class TvLibraryPage extends ConsumerStatefulWidget {
  /// 进入时要选中的视图 key（来自路由 `?view=`）。
  final String? initialViewKey;

  const TvLibraryPage({super.key, this.initialViewKey});

  @override
  ConsumerState<TvLibraryPage> createState() => _TvLibraryPageState();
}

class _TvLibraryPageState extends ConsumerState<TvLibraryPage> {
  String? _selectedViewKey;

  @override
  void initState() {
    super.initState();
    final key = widget.initialViewKey;
    if (key != null && LibraryBrowseConfig.defaultOrder.contains(key)) {
      _selectedViewKey = key;
    }
  }

  void _selectView(String key) {
    if (key == _selectedViewKey) return;
    setState(() => _selectedViewKey = key);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config =
        ref.watch(libraryBrowseConfigProvider).value ??
        LibraryBrowseConfig.defaultConfig();
    final visibleKeys = config.visibleViews.map((v) => v.key).toList();

    var selected = _selectedViewKey;
    if (selected == null || !visibleKeys.contains(selected)) {
      selected = visibleKeys.isNotEmpty ? visibleKeys.first : null;
    }

    if (selected == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: Text(l10n.libraryViewsMinOne, style: TvTheme.titleStyle(context)),
        ),
      );
    }

    // chip 按分组顺序铺平（组间不加分隔，靠视觉间距区分）。
    final grouped = groupLibraryViewKeys(visibleKeys);
    final orderedKeys = [for (final g in grouped) ...g];
    final chips = [
      for (final key in orderedKeys)
        TvViewChip(
          key: key,
          label: libraryViewLabel(l10n, key),
          icon: libraryViewIcon(key),
        ),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: TvTheme.spacingMedium),
              child: TvViewChipRow(
                chips: chips,
                selectedKey: selected,
                onSelected: _selectView,
              ),
            ),
            Expanded(child: _buildContent(selected)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String selected) {
    if (isFlatLibraryView(selected)) {
      return _TvFlatSongList(
        key: ValueKey('flat-$selected'),
        typeFilter: flatViewType(selected),
      );
    }
    if (isPlaylistLibraryView(selected)) {
      return _TvPlaylistGrid(
        key: ValueKey('playlist-$selected'),
        typeFamily: playlistViewType(selected),
      );
    }
    return _TvFacetGrid(key: ValueKey('facet-$selected'), field: selected);
  }
}

// ============================================================
// 扁平歌曲列表（all/local/remote/radio）
// ============================================================

class _TvFlatSongList extends ConsumerStatefulWidget {
  /// 歌曲 type 过滤（null = 全部）
  final String? typeFilter;

  const _TvFlatSongList({super.key, required this.typeFilter});

  @override
  ConsumerState<_TvFlatSongList> createState() => _TvFlatSongListState();
}

class _TvFlatSongListState extends ConsumerState<_TvFlatSongList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 进入该视图时同步共享 songsListProvider 的 type 过滤（触发加载）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(songsListProvider.notifier).setTypeFilter(widget.typeFilter);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(songsListProvider.notifier).loadMore();
    }
  }

  void _onSongTap(SongsListState state, int index) {
    final notifier = ref.read(playerStateProvider.notifier);
    notifier.playPlaylist(state.songs, startIndex: index);
    if (state.hasMore) {
      notifier.loadRemainingSongsForCurrentPlaylist(
        keyword: state.keyword,
        type: state.type,
        loadedCount: state.songs.length,
        total: state.total,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(songsListProvider);
    final currentSong = ref.watch(currentSongProvider);

    // 首屏加载中（type 尚未同步或正在拉取）。
    if (state.isLoading && state.songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 80,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: TvTheme.spacingLarge),
            Text(l10n.libraryEmpty, style: TvTheme.titleStyle(context)),
          ],
        ),
      );
    }

    return FocusTraversalGroup(
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: TvTheme.contentPadding,
          vertical: TvTheme.spacingMedium,
        ),
        itemCount: state.songs.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: TvTheme.spacingSmall),
        itemBuilder: (context, index) {
          if (index >= state.songs.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(TvTheme.spacingLarge),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final song = state.songs[index];
          final isCurrent = currentSong?.id == song.id;
          return TvSongTile(
            song: song,
            index: index + 1,
            isCurrentSong: isCurrent,
            isPlaying: isCurrent && ref.watch(isPlayingProvider),
            autofocus: index == 0,
            onSelect: () => _onSongTap(state, index),
          );
        },
      ),
    );
  }
}

// ============================================================
// 分类 facet 网格（artist/album/genre/...）
// ============================================================

class _TvFacetGrid extends ConsumerStatefulWidget {
  final String field;

  const _TvFacetGrid({super.key, required this.field});

  @override
  ConsumerState<_TvFacetGrid> createState() => _TvFacetGridState();
}

class _TvFacetGridState extends ConsumerState<_TvFacetGrid> {
  final _scrollController = ScrollController();

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
      ref.read(facetListProvider(widget.field).notifier).loadMore();
    }
  }

  void _openFacet(SongFacet facet) {
    final uri = Uri(
      path: '/library/categories/${widget.field}',
      queryParameters: {
        'value': facet.value,
        if (facet.coverUrl.isNotEmpty) 'cover': facet.coverUrl,
      },
    );
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncState = ref.watch(facetListProvider(widget.field));

    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          '${l10n.commonLoadFailed}\n$error',
          style: TvTheme.captionStyle(context),
          textAlign: TextAlign.center,
        ),
      ),
      data: (state) {
        if (state.items.isEmpty) {
          return Center(
            child: Text(l10n.libraryEmpty, style: TvTheme.titleStyle(context)),
          );
        }
        final count = state.items.length + (state.isLoadingMore ? 1 : 0);
        return TvGridView(
          controller: _scrollController,
          crossAxisCount: 5,
          childAspectRatio: 0.82,
          itemCount: count,
          itemBuilder: (context, index) {
            if (index >= state.items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final facet = state.items[index];
            return _TvFacetCard(
              field: widget.field,
              facet: facet,
              autofocus: index == 0,
              onSelect: () => _openFacet(facet),
            );
          },
        );
      },
    );
  }
}

class _TvFacetCard extends StatelessWidget {
  final String field;
  final SongFacet facet;
  final bool autofocus;
  final VoidCallback onSelect;

  const _TvFacetCard({
    required this.field,
    required this.facet,
    required this.autofocus,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return TvFocusableContainer(
      autofocus: autofocus,
      onSelect: onSelect,
      borderRadius: BorderRadius.circular(TvTheme.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TvTheme.cardRadius),
              child: AspectRatio(
                aspectRatio: 1,
                child: CoverImage(
                  coverUrl: facet.coverUrl.isEmpty ? null : facet.coverUrl,
                  size: double.infinity,
                  borderRadius: TvTheme.cardRadius,
                  placeholderIcon: libraryViewIcon(field),
                ),
              ),
            ),
          ),
          const SizedBox(height: TvTheme.spacingSmall),
          Text(
            categoryValueLabel(l10n, field, facet.value),
            style: TvTheme.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            l10n.homeSongCount(facet.count),
            style: TvTheme.captionStyle(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 歌单网格（playlist / playlist_normal / playlist_radio）
// ============================================================

class _TvPlaylistGrid extends ConsumerStatefulWidget {
  /// 歌单 type family（null = 全部）
  final String? typeFamily;

  const _TvPlaylistGrid({super.key, required this.typeFamily});

  @override
  ConsumerState<_TvPlaylistGrid> createState() => _TvPlaylistGridState();
}

class _TvPlaylistGridState extends ConsumerState<_TvPlaylistGrid> {
  final _scrollController = ScrollController();

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
      ref.read(playlistListProvider(widget.typeFamily).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncState = ref.watch(playlistListProvider(widget.typeFamily));
    final currentPlaylistId = ref.watch(sourcePlaylistIdProvider);
    final isPlaying = ref.watch(isPlayingProvider);

    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          '${l10n.commonLoadFailed}\n$error',
          style: TvTheme.captionStyle(context),
          textAlign: TextAlign.center,
        ),
      ),
      data: (state) {
        if (state.items.isEmpty) {
          return Center(
            child: Text(
              l10n.homeEmptyPlaylists,
              style: TvTheme.titleStyle(context),
            ),
          );
        }
        final count = state.items.length + (state.isLoadingMore ? 1 : 0);
        return TvGridView(
          controller: _scrollController,
          crossAxisCount: TvTheme.gridColumns,
          childAspectRatio: 0.85,
          itemCount: count,
          itemBuilder: (context, index) {
            if (index >= state.items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final playlist = state.items[index];
            final isCurrent = playlist.id == currentPlaylistId;
            return _TvPlaylistCard(
              playlist: playlist,
              isCurrent: isCurrent,
              isPlaying: isPlaying && isCurrent,
              autofocus: index == 0,
              onSelect: () => context.push('/playlists/${playlist.id}'),
            );
          },
        );
      },
    );
  }
}

class _TvPlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final bool isCurrent;
  final bool isPlaying;
  final bool autofocus;
  final VoidCallback onSelect;

  const _TvPlaylistCard({
    required this.playlist,
    required this.isCurrent,
    required this.isPlaying,
    required this.autofocus,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final coverUrl = playlist.coverImageUrl;

    return TvFocusableContainer(
      autofocus: autofocus,
      onSelect: onSelect,
      borderRadius: BorderRadius.circular(TvTheme.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TvTheme.cardRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(
                    coverUrl: coverUrl,
                    size: double.infinity,
                    borderRadius: TvTheme.cardRadius,
                    placeholderIcon: playlist.type == 'radio'
                        ? Icons.radio_rounded
                        : Icons.queue_music_rounded,
                  ),
                  if (isPlaying)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Icon(
                          Icons.equalizer_rounded,
                          size: 48,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: TvTheme.spacingSmall),
          Text(
            playlist.name,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            l10n.homeSongCount(playlist.songCount),
            style: TvTheme.captionStyle(context),
          ),
        ],
      ),
    );
  }
}
