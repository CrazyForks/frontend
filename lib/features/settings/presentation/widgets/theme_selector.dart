import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../providers/settings_provider.dart';

/// 主题选择器组件
class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        for (final option in _options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: _ThemeOptionCard(
                icon: option.icon,
                label: option.label,
                isSelected: themeMode == option.mode,
                colorScheme: colorScheme,
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(option.mode);
                },
              ),
            ),
          ),
      ],
    );
  }

  static const _options = [
    _ThemeOption(
      mode: ThemeMode.light,
      icon: Icons.light_mode_rounded,
      label: '浅色',
    ),
    _ThemeOption(
      mode: ThemeMode.dark,
      icon: Icons.dark_mode_rounded,
      label: '深色',
    ),
    _ThemeOption(
      mode: ThemeMode.system,
      icon: Icons.phone_android_rounded,
      label: '系统',
    ),
  ];
}

class _ThemeOption {
  final ThemeMode mode;
  final IconData icon;
  final String label;
  const _ThemeOption({
    required this.mode,
    required this.icon,
    required this.label,
  });
}

class _ThemeOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: 72,
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color:
                isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 0 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color:
                  isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color:
                    isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
