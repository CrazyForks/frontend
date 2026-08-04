import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/utils/responsive_snackbar.dart';
import '../../data/theme_pack_api.dart';
import '../providers/theme_pack_provider.dart';

class ThemeCatalog extends ConsumerStatefulWidget {
  const ThemeCatalog({super.key});

  @override
  ConsumerState<ThemeCatalog> createState() => _ThemeCatalogState();
}

class _ThemeCatalogState extends ConsumerState<ThemeCatalog> {
  final Set<String> _installing = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(themeCatalogProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(themeCatalogProvider);
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Text(
                l10n.themeCatalogTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: l10n.themeCatalogRefresh,
                onPressed:
                    catalog.isLoading
                        ? null
                        : () => ref
                            .read(themeCatalogProvider.notifier)
                            .refresh(force: true),
              ),
            ],
          ),
        ),
        catalog.when(
          data: (entries) {
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  l10n.themeCatalogEmpty,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children:
                  entries.map((entry) {
                    return _CatalogEntryTile(
                      entry: entry,
                      installing: _installing.contains(entry.id),
                      onInstall: () => _installTheme(entry),
                    );
                  }).toList(),
            );
          },
          loading:
              () => const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    Text(
                      l10n.themeCatalogLoadError,
                      style: TextStyle(color: colorScheme.error),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed:
                          () => ref
                              .read(themeCatalogProvider.notifier)
                              .refresh(force: true),
                      child: Text(l10n.themeCatalogRefresh),
                    ),
                  ],
                ),
              ),
        ),
      ],
    );
  }

  Future<void> _installTheme(ThemeCatalogEntry entry) async {
    setState(() => _installing.add(entry.id));
    try {
      await ref.read(themeCatalogProvider.notifier).installTheme(entry);
      if (!mounted) return;
      ResponsiveSnackBar.showSuccess(
        context,
        message: AppLocalizations.of(
          context,
        ).themeCatalogInstallSuccess(entry.name),
      );
    } catch (e) {
      if (!mounted) return;
      ResponsiveSnackBar.showError(
        context,
        message: '${AppLocalizations.of(context).themeCatalogInstallError}: $e',
      );
    } finally {
      if (mounted) setState(() => _installing.remove(entry.id));
    }
  }
}

class _CatalogEntryTile extends StatelessWidget {
  final ThemeCatalogEntry entry;
  final bool installing;
  final VoidCallback onInstall;

  const _CatalogEntryTile({
    required this.entry,
    required this.installing,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final isInstalled = entry.installState == 'installed';
    final hasUpdate = entry.installState == 'has_update';

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color:
              isInstalled
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(
          isInstalled ? Icons.check_circle_outline : Icons.palette_outlined,
          color:
              isInstalled
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(entry.name),
      subtitle: Text(
        [
          if (entry.author.isNotEmpty) entry.author,
          'v${entry.version}',
          if (entry.description.isNotEmpty) entry.description,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
      ),
      trailing:
          installing
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : isInstalled
              ? Text(
                l10n.themeCatalogInstalled,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              )
              : FilledButton.tonal(
                onPressed: onInstall,
                child: Text(
                  hasUpdate
                      ? l10n.themeCatalogUpdate
                      : l10n.themeCatalogInstall,
                ),
              ),
    );
  }
}
