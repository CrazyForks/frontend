import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../home/domain/home_grid_config.dart';
import '../../../home/presentation/providers/home_grid_config_provider.dart';

/// 首页歌单网格行列选择器（设置 → 外观，songloft-org/songloft#332）。
///
/// 用 Wrap + ChoiceChip 而不是把 SegmentedButton 挂在 ListTile.trailing 上：
/// 两组各 5 个选项，设置详情栏在手机上只有 ~330px 宽，5 段的 SegmentedButton
/// 必然溢出；Wrap 会自动折行。
class HomeGridSelector extends ConsumerWidget {
  const HomeGridSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final config = ref.watch(homeGridConfigProvider);
    final notifier = ref.read(homeGridConfigProvider.notifier);

    final columnsLabel =
        config.isAutoColumns
            ? l10n.settingsHomeGridColumnsAuto
            : '${config.columns}';
    final rowsLabel =
        config.isAllRows ? l10n.settingsHomeGridRowsAll : '${config.rows}';
    final layout = '$columnsLabel × $rowsLabel';

    // 三种摘要写法，别对算不出来的数字撒谎：
    // - 「全部」行数会自动续拉分页，但有 kHomeAutoLoadAllMaxItems 硬上限，说清它
    // - 「自动」列数取决于窗口宽度，给不出确切个数
    final String summary;
    if (config.isAllRows) {
      summary = l10n.settingsHomeGridSummaryAllRows(
        layout,
        kHomeAutoLoadAllMaxItems,
      );
    } else if (config.isAutoColumns) {
      summary = l10n.settingsHomeGridSummaryAuto(layout);
    } else {
      summary = l10n.settingsHomeGridSummary(
        layout,
        config.columns * config.rows,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsHomeGridDesc,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ChipGroup(
          title: l10n.settingsHomeGridColumnsTitle,
          options: HomeGridConfig.columnOptions,
          selected: config.columns,
          labelBuilder:
              (value) =>
                  value == HomeGridConfig.autoColumns
                      ? l10n.settingsHomeGridColumnsAuto
                      : '$value',
          onPick: notifier.setColumns,
        ),
        const SizedBox(height: AppSpacing.md),
        _ChipGroup(
          title: l10n.settingsHomeGridRowsTitle,
          options: HomeGridConfig.rowOptions,
          selected: config.rows,
          labelBuilder:
              (value) =>
                  value == HomeGridConfig.allRows
                      ? l10n.settingsHomeGridRowsAll
                      : '$value',
          onPick: notifier.setRows,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          summary,
          style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.settingsHomeGridClampHint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        // 当前窗口根本走不到网格分支时明确告知，而不是让用户以为设置坏了。
        // 刻意不隐藏整个设置项：桌面/Web 窗口可任意缩放，时有时无更糟。
        if (!context.useWideLayout) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: colorScheme.tertiary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.settingsHomeGridNarrowHint,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.tertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 一组可折行的单选 chip
class _ChipGroup extends StatelessWidget {
  final String title;
  final List<int> options;
  final int selected;
  final String Function(int value) labelBuilder;
  final void Function(int value) onPick;

  const _ChipGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final value in options)
              ChoiceChip(
                label: Text(labelBuilder(value)),
                selected: selected == value,
                onSelected: (isSelected) {
                  if (isSelected) onPick(value);
                },
              ),
          ],
        ),
      ],
    );
  }
}
