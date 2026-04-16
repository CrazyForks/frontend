import 'package:flutter/material.dart';

import '../../../../config/constants.dart';

/// 歌曲类型筛选栏
class SongFilterBar extends StatelessWidget {
  final String? currentType;
  final ValueChanged<String?> onTypeChanged;
  final int songCount;

  const SongFilterBar({
    super.key,
    this.currentType,
    required this.onTypeChanged,
    this.songCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 筛选 Chips（可滚动）
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: '全部',
                    isSelected: currentType == null,
                    onTap: () => onTypeChanged(null),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '本地',
                    isSelected: currentType == AppConstants.songTypeLocal,
                    onTap: () => onTypeChanged(AppConstants.songTypeLocal),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '网络',
                    isSelected: currentType == AppConstants.songTypeRemote,
                    onTap: () => onTypeChanged(AppConstants.songTypeRemote),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '电台',
                    isSelected: currentType == AppConstants.songTypeRadio,
                    onTap: () => onTypeChanged(AppConstants.songTypeRadio),
                  ),
                ],
              ),
            ),
          ),
          // 歌曲总数
          if (songCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '$songCount首',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: colorScheme.primaryContainer,
      checkmarkColor: colorScheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color: isSelected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface,
      ),
    );
  }
}
