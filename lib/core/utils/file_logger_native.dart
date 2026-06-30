import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import 'platform_utils.dart';

class FileLogger {
  FileLogger._();

  static IOSink? _sink;
  static String? _currentPath;
  static String? _currentDir;

  static const _maxAgeDays = 3;

  static Future<void> init() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final logsDir = Directory('${appDir.path}${Platform.pathSeparator}logs');
      if (!logsDir.existsSync()) {
        logsDir.createSync(recursive: true);
      }
      _currentDir = logsDir.path;

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
      final logFile = File(
        '${logsDir.path}${Platform.pathSeparator}songloft_$dateStr.log',
      );
      _currentPath = logFile.path;

      _sink = logFile.openWrite(mode: FileMode.append);

      const version = AppConfig.frontendVersion;
      final platform = PlatformUtils.platformName;
      final ts = _formatDateTime(now);
      _sink!.writeln(
        '========== Songloft v$version | $ts | $platform ==========',
      );

      _cleanOldLogs(logsDir, now);
    } catch (e) {
      debugPrint('[FileLogger] 初始化失败: $e');
    }
  }

  static void writeln(String line) {
    final sink = _sink;
    if (sink == null) return;
    final now = DateTime.now();
    final ts =
        '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}.${_pad3(now.millisecond)}';
    sink.writeln('[$ts] $line');
  }

  static Future<void> flush() async {
    await _sink?.flush();
  }

  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  static String? get logFilePath => _currentPath;

  static String? get logDir => _currentDir;

  static void _cleanOldLogs(Directory logsDir, DateTime now) {
    try {
      final cutoff = now.subtract(const Duration(days: _maxAgeDays));
      for (final entity in logsDir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('songloft_') || !name.endsWith('.log')) continue;
        final datePart = name.substring(9, name.length - 4);
        final fileDate = DateTime.tryParse(datePart);
        if (fileDate != null && fileDate.isBefore(cutoff)) {
          entity.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('[FileLogger] 清理旧日志失败: $e');
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _pad3(int n) => n.toString().padLeft(3, '0');

  static String _formatDateTime(DateTime dt) =>
      '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
      '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
}
