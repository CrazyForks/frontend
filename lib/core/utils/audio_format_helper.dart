import 'dart:io';

import 'package:flutter/foundation.dart';

class AudioFormatHelper {
  AudioFormatHelper._();

  static const _webFormats = {
    'mp3', 'flac', 'ogg', 'm4a', 'aac', 'wav', 'opus',
  };
  static const _iosFormats = {
    'mp3', 'flac', 'm4a', 'aac', 'wav', 'alac', 'aiff',
  };
  static const _androidFormats = {
    'mp3', 'flac', 'ogg', 'm4a', 'aac', 'wav', 'opus',
  };

  static String? getTranscodeFormat(String? songFormat) {
    if (songFormat == null || songFormat.isEmpty) return null;
    final fmt = _normalizeFormat(songFormat.toLowerCase());
    if (fmt == null) return null;
    final supported = _getPlatformFormats();
    if (supported.isEmpty) return null;
    if (supported.contains(fmt)) return null;
    return 'mp3';
  }

  /// 将服务端返回的 format 字段归一化为音频格式名。
  /// 兼容旧数据中可能存储的 tag 格式名（如 "ID3v2.3"）。
  static String? _normalizeFormat(String fmt) {
    if (fmt.startsWith('id3v')) return 'mp3';
    switch (fmt) {
      case 'mpeg':
      case 'mp3':
        return 'mp3';
      case 'mp4':
      case 'm4a':
      case 'aac':
      case 'mov': // QuickTime/ISO-BMFF 同族容器（如 bilibili 下载源），按 m4a 处理
        return 'm4a';
      case 'ogg':
      case 'vorbis':
        return 'ogg';
      case 'flac':
        return 'flac';
      case 'wav':
      case 'wave':
        return 'wav';
      case 'wma':
      case 'asf':
        return 'wma';
      case 'ape':
        return 'ape';
      case 'opus':
        return 'opus';
      default:
        return null;
    }
  }

  static Set<String> _getPlatformFormats() {
    if (kIsWeb) return _webFormats;
    if (Platform.isIOS) return _iosFormats;
    if (Platform.isAndroid) return _androidFormats;
    return {};
  }
}
