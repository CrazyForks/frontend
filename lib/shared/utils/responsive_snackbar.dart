import 'package:flutter/material.dart';
import '../../core/theme/responsive.dart';

/// 响应式 SnackBar 辅助工具
///
/// 根据屏幕类型自动调整 SnackBar 的字体大小、内边距和宽度，
/// 确保在 TV 和大屏幕设备上具有良好的可读性。
class ResponsiveSnackBar {
  ResponsiveSnackBar._();

  /// 显示响应式 SnackBar
  ///
  /// 自动根据屏幕类型调整显示效果：
  /// - TV 模式: 大字体(20sp)、宽显示(600px)、大内边距
  /// - Desktop 模式: 中等字体(16sp)、中等宽度(480px)
  /// - 其他模式: 使用默认配置
  static void show(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    final screenType = context.screenType;
    final isTv = screenType == ScreenType.tv;
    final isDesktop = screenType == ScreenType.desktop;

    final snackBar = SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize:
              isTv
                  ? 20
                  : isDesktop
                  ? 16
                  : null,
          // 显式设置颜色确保对比度
          // 自定义背景色时用白色，默认背景使用 Material 3 的 onInverseSurface
          color:
              backgroundColor != null
                  ? Colors.white
                  : Theme.of(context).colorScheme.onInverseSurface,
        ),
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      width:
          isTv
              ? 600
              : isDesktop
              ? 480
              : null,
      padding:
          isTv
              ? const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
              : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isTv ? 12 : 8),
      ),
      action: action,
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  /// 显示错误类型的响应式 SnackBar
  static void showError(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    show(
      context,
      message: message,
      backgroundColor: colorScheme.error,
      duration: duration,
    );
  }

  /// 显示成功类型的响应式 SnackBar
  static void showSuccess(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    show(
      context,
      message: message,
      backgroundColor: colorScheme.primary,
      duration: duration,
    );
  }
}
