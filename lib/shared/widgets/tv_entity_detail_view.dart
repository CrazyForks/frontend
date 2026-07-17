import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tv_theme.dart';
import '../../core/utils/color_extraction.dart';
import 'cover_image.dart';
import 'tv_focusable.dart';

/// TV 版「实体详情」骨架：横向大封面 header（调色板渐变）+ 标题/副标题 +
/// 「播放全部」大焦点按钮 + 歌曲列表 sliver。
///
/// 对标窄屏 `EntityDetailScaffold`，但焦点优先、单列大图。歌曲列表由调用方以
/// [bodySlivers]（`TvSongTile` 组成的 SliverList + 加载更多 + 底部安全区）注入。
/// 顶部 Tab 导航与底部播放器由 shell 提供；返回键由 shell `PopScope` 处理。
class TvEntityDetailView extends ConsumerWidget {
  /// 标题（大字号）
  final String title;

  /// 聚合副标题（如「歌手 · 42 首」）
  final String? subtitle;

  /// 描述（歌单简介等）
  final String? description;

  /// 封面 URL（展示 + 调色板渐变）
  final String? coverUrl;
  final IconData placeholderIcon;

  /// 「播放全部」回调；为 null 时不显示该按钮
  final VoidCallback? onPlayAll;

  /// 「播放全部」按钮文案
  final String playAllLabel;

  /// 播放全部按钮右侧的额外焦点按钮（如「加入歌单」）
  final List<Widget> extraActions;

  /// 歌曲列表相关 sliver
  final List<Widget> bodySlivers;

  final ScrollController? scrollController;

  const TvEntityDetailView({
    super.key,
    required this.title,
    required this.bodySlivers,
    this.subtitle,
    this.description,
    this.coverUrl,
    this.placeholderIcon = Icons.music_note,
    this.onPlayAll,
    this.playAllLabel = '',
    this.extraActions = const [],
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1920),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, ref)),
                ...bodySlivers,
                const SliverToBoxAdapter(
                  child: SizedBox(height: TvTheme.spacingXLarge),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final palette = ref.watch(coverColorsProvider(coverUrl ?? '')).value;
    final bgColor =
        palette?.darkMutedColor ?? colorScheme.surfaceContainerHighest;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgColor.withValues(alpha: 0.6), colorScheme.surface],
        ),
      ),
      padding: const EdgeInsets.all(TvTheme.contentPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 大封面
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TvTheme.cardRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CoverImage(
              coverUrl: coverUrl,
              size: TvTheme.largeCoverSize,
              borderRadius: TvTheme.cardRadius,
              placeholderIcon: placeholderIcon,
            ),
          ),
          const SizedBox(width: TvTheme.spacingXLarge),
          // 标题 + 描述 + 操作
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: TvTheme.spacingMedium),
                  Text(subtitle!, style: TvTheme.bodyStyle(context)),
                ],
                if (description?.isNotEmpty == true) ...[
                  const SizedBox(height: TvTheme.spacingSmall),
                  Text(
                    description!,
                    style: TvTheme.captionStyle(context),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (onPlayAll != null || extraActions.isNotEmpty) ...[
                  const SizedBox(height: TvTheme.spacingXLarge),
                  Row(
                    children: [
                      if (onPlayAll != null)
                        TvButton(
                          label: playAllLabel,
                          icon: Icons.play_arrow_rounded,
                          autofocus: true,
                          onPressed: onPlayAll,
                        ),
                      for (final action in extraActions) ...[
                        const SizedBox(width: TvTheme.spacingMedium),
                        action,
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
