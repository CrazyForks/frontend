import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tv_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/tv_focusable.dart';
import 'widgets/settings_category_content.dart';
import 'widgets/settings_master_detail.dart';

/// TV 设置页
///
/// 单列大类目行（[TvFocusableContainer] 焦点），Enter push 到 [_TvSettingsDetailPage]。
/// 设置项内容复用 [SettingsCategoryContent]（与桌面/移动同源）。顶部 Tab 导航与
/// 底部播放器由 shell 提供。
class TvSettingsPage extends ConsumerWidget {
  const TvSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = buildSettingsCategories(l10n);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: FocusTraversalGroup(
              child: ListView(
                padding: const EdgeInsets.all(TvTheme.contentPadding),
                children: [
                  const SettingsServerInfoCard(),
                  const SizedBox(height: TvTheme.spacingLarge),
                  for (var i = 0; i < categories.length; i++) ...[
                    _TvSettingsCategoryRow(
                      category: categories[i],
                      autofocus: i == 0,
                      onSelect: () => _openCategory(context, categories[i], i),
                    ),
                    if (i < categories.length - 1)
                      const SizedBox(height: TvTheme.spacingMedium),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openCategory(BuildContext context, SettingsCategory category, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _TvSettingsDetailPage(title: category.title, index: index),
      ),
    );
  }
}

/// TV 设置分类大行。
class _TvSettingsCategoryRow extends StatelessWidget {
  final SettingsCategory category;
  final bool autofocus;
  final VoidCallback onSelect;

  const _TvSettingsCategoryRow({
    required this.category,
    required this.autofocus,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TvFocusableContainer(
      autofocus: autofocus,
      onSelect: onSelect,
      borderRadius: BorderRadius.circular(TvTheme.cardRadius),
      padding: const EdgeInsets.symmetric(
        horizontal: TvTheme.spacingLarge,
        vertical: TvTheme.spacingMedium,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TvTheme.listItemMinHeight),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                category.icon,
                size: 28,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: TvTheme.spacingLarge),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    category.title,
                    style: TvTheme.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    category.subtitle,
                    style: TvTheme.captionStyle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// TV 设置详情子页：AppBar 标题 + [SettingsCategoryContent] 滚动区。
class _TvSettingsDetailPage extends StatelessWidget {
  final String title;
  final int index;

  const _TvSettingsDetailPage({required this.title, required this.index});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SettingsCategoryContent(index: index),
          ),
        ),
      ),
    );
  }
}
