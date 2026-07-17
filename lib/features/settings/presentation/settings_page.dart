import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/responsive.dart';
import 'widgets/settings_category_content.dart';
import 'widgets/settings_master_detail.dart';
import '../../../l10n/app_localizations.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int _selectedCategory = 0;
  int? _mobileDetailIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = buildSettingsCategories(l10n);
    // 与 SettingsMasterDetail 共用同一布局判断，避免漂移导致车机超宽比下渲染
    // 移动端列表却不响应点击的「按钮失效」(songloft-org/songloft#268)。
    final isMobile = !context.useWideLayout;

    if (isMobile && _mobileDetailIndex != null) {
      final category = categories[_mobileDetailIndex!];
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            setState(() => _mobileDetailIndex = null);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () => setState(() => _mobileDetailIndex = null),
            ),
            title: Text(category.title),
          ),
          body: SettingsCategoryContent(index: _mobileDetailIndex!),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: SettingsMasterDetail(
        categories: categories,
        selectedIndex: _selectedCategory,
        onCategorySelected: (i) {
          setState(() {
            _selectedCategory = i;
            if (isMobile) {
              _mobileDetailIndex = i;
            }
          });
        },
        contentBuilder: (_, index) => SettingsCategoryContent(index: index),
        header: const SettingsServerInfoCard(),
      ),
    );
  }
}
