import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tv_theme.dart';

/// TV 端横向焦点 chip 行
///
/// 替代窄屏的 `LibraryViewSwitcher`/`FilterPill` 横条，用于页内视图切换。
/// 每个 chip 是可聚焦大号药丸，选中态走 primary；D-pad 左右遍历。
class TvViewChipRow extends StatelessWidget {
  /// chip 数据（key → 显示文案）
  final List<TvViewChip> chips;

  /// 当前选中的 key
  final String selectedKey;

  /// 选中回调
  final ValueChanged<String> onSelected;

  /// 是否让选中项自动获取焦点
  final bool autofocusSelected;

  const TvViewChipRow({
    super.key,
    required this.chips,
    required this.selectedKey,
    required this.onSelected,
    this.autofocusSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TvTheme.tabItemMinHeight + TvTheme.spacingMedium,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: TvTheme.contentPadding,
            vertical: TvTheme.spacingSmall,
          ),
          itemCount: chips.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: TvTheme.spacingMedium),
          itemBuilder: (context, index) {
            final chip = chips[index];
            final isSelected = chip.key == selectedKey;
            return _TvViewChip(
              label: chip.label,
              icon: chip.icon,
              isSelected: isSelected,
              autofocus: autofocusSelected && isSelected,
              onSelect: () => onSelected(chip.key),
            );
          },
        ),
      ),
    );
  }
}

/// 单个视图 chip 的数据
class TvViewChip {
  final String key;
  final String label;
  final IconData? icon;

  const TvViewChip({required this.key, required this.label, this.icon});
}

class _TvViewChip extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onSelect;

  const _TvViewChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.autofocus,
    required this.onSelect,
  });

  @override
  State<_TvViewChip> createState() => _TvViewChipState();
}

class _TvViewChipState extends State<_TvViewChip> {
  bool _hasFocus = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 背景：选中 → secondaryContainer；否则 surfaceContainerHighest。
    final bgColor =
        widget.isSelected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHighest;
    final fgColor =
        widget.isSelected
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurfaceVariant;

    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: TvTheme.focusAnimationDuration,
          curve: TvTheme.focusAnimationCurve,
          constraints: const BoxConstraints(
            minHeight: TvTheme.tabItemMinHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: TvTheme.spacingLarge,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(TvTheme.tabItemMinHeight / 2),
            border: Border.all(
              color: _hasFocus ? colorScheme.primary : Colors.transparent,
              width: TvTheme.focusBorderWidth,
            ),
            boxShadow:
                _hasFocus
                    ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: TvTheme.focusShadowBlurRadius,
                        spreadRadius: TvTheme.focusGlowSpreadRadius,
                      ),
                    ]
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 24, color: fgColor),
                const SizedBox(width: TvTheme.spacingSmall),
              ],
              Text(
                widget.label,
                style: TvTheme.buttonStyle(context).copyWith(color: fgColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
