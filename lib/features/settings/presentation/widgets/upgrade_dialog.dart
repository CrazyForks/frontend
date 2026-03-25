import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exceptions.dart';
import '../../../../core/theme/responsive.dart';
import '../../data/upgrade_api.dart';
import '../providers/settings_provider.dart';

/// 升级对话框
class UpgradeDialog extends ConsumerStatefulWidget {
  const UpgradeDialog({super.key});

  /// 显示升级对话框
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const UpgradeDialog(),
    );
  }

  @override
  ConsumerState<UpgradeDialog> createState() => _UpgradeDialogState();
}

class _UpgradeDialogState extends ConsumerState<UpgradeDialog> {
  bool _isChecking = true;
  bool _isStarting = false;
  String? _error;
  UpgradeCheck? _checkResult;

  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 延迟调用，避免在 initState 中访问 inherited widget
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkUpgrade();
    });
  }

  Future<void> _checkUpgrade() async {
    setState(() {
      _isChecking = true;
      _error = null;
      _checkResult = null;
    });

    try {
      // 直接调用 API，避免 ref.invalidate + ref.read(.future) 的状态问题
      final upgradeApi = ref.read(upgradeApiProvider);
      final result = await upgradeApi.checkUpgrade().timeout(
        const Duration(seconds: 10),
      );
      if (mounted) setState(() => _checkResult = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TimeoutException {
      if (mounted) setState(() => _error = '检查更新超时，请稍后重试');
    } catch (e) {
      if (mounted) setState(() => _error = '检查更新失败: $e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _startUpgrade() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });

    try {
      await ref.read(upgradeProgressProvider.notifier).startUpgrade();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '启动升级失败: $e');
    } finally {
      setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final upgradeProgress = ref.watch(upgradeProgressProvider);

    return AlertDialog(
      title: const Row(
        children: [Icon(Icons.system_update), SizedBox(width: 8), Text('检查更新')],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.responsiveDialogMaxWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 错误信息
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),

              // 正在检查
              if (_isChecking)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在检查更新...'),
                    ],
                  ),
                )
              // 正在升级
              else if (upgradeProgress.isUpgrading)
                _buildUpgradeProgress(upgradeProgress)
              // 升级完成
              else if (upgradeProgress.isCompleted)
                _buildUpgradeCompleted()
              // 升级出错
              else if (upgradeProgress.isError)
                _buildUpgradeError(upgradeProgress)
              // 本地捕获的错误（如 API 返回 403）- 错误信息已在顶部显示
              else if (_error != null)
                const SizedBox.shrink()
              // 显示检查结果
              else if (_checkResult != null)
                _buildCheckResult(_checkResult!),
            ],
          ),
        ),
      ),
      actions: _buildActions(upgradeProgress),
    );
  }

  Widget _buildCheckResult(UpgradeCheck check) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!check.hasUpdate) {
      return Center(
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            const Text('已是最新版本'),
            const SizedBox(height: 8),
            Text(
              '当前版本: ${check.currentVersion ?? '未知'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 版本信息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.new_releases, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('发现新版本'),
                ],
              ),
              const SizedBox(height: 8),
              Text('当前版本: ${check.currentVersion ?? '未知'}'),
              Text('最新版本: ${check.latestVersion ?? '未知'}'),
            ],
          ),
        ),

        // 发布说明
        if (check.releaseNotes != null) ...[
          const SizedBox(height: 16),
          Text('更新说明:', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Text(
                check.releaseNotes!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUpgradeProgress(UpgradeProgress progress) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress.progress / 100,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 16),
        Text(progress.statusText),
        if (progress.message != null) ...[
          const SizedBox(height: 8),
          Text(progress.message!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _buildUpgradeCompleted() {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 16),
          const Text('升级完成'),
          const SizedBox(height: 8),
          Text('应用即将重启', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildUpgradeError(UpgradeProgress progress) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(Icons.error, color: colorScheme.error, size: 48),
        const SizedBox(height: 16),
        const Text('升级失败'),
        if (progress.message != null) ...[
          const SizedBox(height: 8),
          Text(
            progress.message!,
            style: TextStyle(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(UpgradeProgress upgradeProgress) {
    // 正在升级时不显示按钮
    if (upgradeProgress.isUpgrading) {
      return [];
    }

    // 升级完成
    if (upgradeProgress.isCompleted) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
      ];
    }

    // 升级出错
    if (upgradeProgress.isError) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () {
            ref.read(upgradeProgressProvider.notifier).reset();
            _checkUpgrade();
          },
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('重试'),
        ),
      ];
    }

    // 正在检查
    if (_isChecking) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('取消'),
        ),
      ];
    }

    // 检查时发生错误（已捕获）
    if (_error != null) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _checkUpgrade,
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('重试'),
        ),
      ];
    }

    // 检查结果
    if (_checkResult != null && _checkResult!.hasUpdate) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: _isStarting ? null : _startUpgrade,
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child:
              _isStarting
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('立即升级'),
        ),
      ];
    }

    if (_checkResult != null) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
      ];
    }

    return [];
  }
}
