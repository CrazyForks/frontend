import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/theme_pack_api.dart';
import '../providers/theme_pack_provider.dart';
import 'theme_catalog.dart';

/// 主题包管理组件：导入、列表、激活、删除
class ThemePackManager extends ConsumerWidget {
  const ThemePackManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePackList = ref.watch(themePackListProvider);
    final activeThemePack = ref.watch(activeThemePackProvider);
    final activeThemeId = activeThemePack.value?.themeId;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 导入按钮和恢复默认
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _importThemePack(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.themePackImport),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (activeThemeId != null && activeThemeId.isNotEmpty)
                OutlinedButton(
                  onPressed: () => _restoreDefault(context, ref),
                  child: Text(l10n.themePackRestoreDefault),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // 主题包列表
        themePackList.when(
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  l10n.themePackEmpty,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children: items.map((item) {
                final isActive = item.themeId == activeThemeId;
                return _ThemePackTile(
                  item: item,
                  isActive: isActive,
                  onTap: () => _activateThemePack(context, ref, item.themeId),
                  onDelete: () =>
                      _deleteThemePack(context, ref, item.themeId, item.name),
                );
              }).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              l10n.themePackLoadError,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        const ThemeCatalog(),
      ],
    );
  }

  Future<void> _importThemePack(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['songloft-theme', 'json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    final content = String.fromCharCodes(file.bytes!);
    if (!context.mounted) return;

    try {
      await ref.read(themePackListProvider.notifier).importThemePack(content);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).themePackImportSuccess)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context).themePackImportError}: $e')),
      );
    }
  }

  Future<void> _activateThemePack(
    BuildContext context,
    WidgetRef ref,
    String themeId,
  ) async {
    try {
      await ref.read(activeThemePackProvider.notifier).setActive(themeId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _restoreDefault(BuildContext context, WidgetRef ref) async {
    await ref.read(activeThemePackProvider.notifier).clearActive();
  }

  Future<void> _deleteThemePack(
    BuildContext context,
    WidgetRef ref,
    String themeId,
    String name,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.themePackDeleteConfirmTitle),
        content: Text(l10n.themePackDeleteConfirmContent(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(themePackListProvider.notifier).deleteThemePack(themeId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

class _ThemePackTile extends StatelessWidget {
  final ThemePackListItem item;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ThemePackTile({
    required this.item,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(
          isActive ? Icons.check_rounded : Icons.palette_outlined,
          color: isActive
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        item.name,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        [
          if (item.author.isNotEmpty) item.author,
          'v${item.version}',
        ].join(' · '),
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 20),
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }
}
