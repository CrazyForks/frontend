import 'dart:io';

import 'package:flutter/foundation.dart';

class AudioFormatHelper {
  AudioFormatHelper._();

  /// 判断视频格式是否为 Web 浏览器原生支持（可直接用 <video> 播放）。
  /// 不支持的格式需要后端 HLS 转码。
  static bool isWebCompatibleVideo(String? format, String? filePath) {
    return const {'mp4', 'webm', 'mov'}.contains(_videoExt(format, filePath));
  }

  /// 原生端（media_kit/libmpv）播放体验差、需改走后端 video-hls 转码的老旧视频容器：
  /// - MPEG-PS/TS 等无索引容器在 HTTP 上二分 seek，产生大量超大 range 请求；
  /// - MPEG-2/RV/VC-1/DivX 等老编码手机 MediaCodec 普遍无硬解，软解 1080P 卡顿。
  /// mp4/mkv/webm/mov/m4v/3gp 等现代容器仍直出（mkv 直出保 libmpv 多音轨切换；
  /// 后端 HLS 转码 -map 0:a:0 只保留首音轨）。黑名单口径：未知格式默认直出。
  static const Set<String> _legacyVideoContainers = {
    'mpg',
    'mpeg',
    'vob',
    'rmvb',
    'rm',
    'wmv',
    'asf',
    'avi',
    'flv',
    'ts',
    'm2ts',
    'mts',
  };

  /// 原生端视频是否应改走后端 video-hls 转码端点（老旧容器命中黑名单）。
  static bool needsNativeVideoHls(String? format, String? filePath) {
    return _legacyVideoContainers.contains(_videoExt(format, filePath));
  }

  static String _videoExt(String? format, String? filePath) {
    var ext = (format ?? '').toLowerCase();
    // 优先从文件路径取扩展名（更可靠）
    if (filePath != null && filePath.contains('.')) {
      ext = filePath.split('.').last.toLowerCase();
    }
    return ext;
  }

  static const _webFormats = {
    'mp3',
    'flac',
    'ogg',
    'm4a',
    'aac',
    'wav',
    'opus',
  };
  static const _iosFormats = {
    'mp3',
    'flac',
    'm4a',
    'aac',
    'wav',
    'alac',
    'aiff',
  };
  static const _androidFormats = {
    'mp3',
    'flac',
    'ogg',
    'm4a',
    'aac',
    'wav',
    'opus',
  };

  static String? getTranscodeFormat(String? songFormat) {
    if (songFormat == null || songFormat.isEmpty) return null;
    final fmt = _normalizeFormat(songFormat.toLowerCase());
    if (fmt == null) return null;
    // Matroska 音频容器（songloft-org/songloft#297）：libmpv 原生支持多音轨枚举与切换
    // （media_kit 的 Player.state.tracks.audio + setAudioTrack），所有原生平台（含
    // iOS/Android，均走 media_kit/libmpv 后端）不转码，直出原容器以保留多音轨（原唱/伴奏）。
    // 仅 Web（浏览器不支持 mka 容器、无法原生切轨）转码为 mp3 播放首条音轨，切轨在 Web 不可用。
    if (fmt == 'mka') {
      return kIsWeb ? 'mp3' : null;
    }
    // 视频容器（音频抽取场景，isVideo=false 才进入此路径）：所有原生平台统一使用
    // media_kit/libmpv 后端，可直接解码任意容器；仅 Web 浏览器不支持这些容器，转码为 mp3。
    if (const {
      'mpg',
      'flv',
      'wmv',
      'rmvb',
      'rm',
      '3gp',
      'm4v',
      'mkv',
      'matroska',
      'webm',
      'avi',
      'ts',
    }.contains(fmt)) {
      return kIsWeb ? 'mp3' : null;
    }
    final supported = _getPlatformFormats();
    if (supported.isEmpty) return null;
    if (supported.contains(fmt)) return null;
    return 'mp3';
  }

  /// 判断该格式在 Web 端是否为「可能含多音轨、需走后端抽轨播放」的容器
  /// （songloft-org/songloft#298）。当前即 mka（原唱/伴奏双音轨卡拉 OK 容器）：
  /// 浏览器不认 Matroska 容器、也无多轨枚举/切换 API，故 Web 统一走后端 ?track= 抽轨
  /// （AAC 无损 remux 成 m4a，否则转 mp3）。原生端由 libmpv 直接切轨，不走此路径，返回 false。
  static bool isWebMultiTrackContainer(String? songFormat) {
    if (!kIsWeb) return false;
    if (songFormat == null || songFormat.isEmpty) return false;
    return _normalizeFormat(songFormat.toLowerCase()) == 'mka';
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
      case 'm4b': // 有声书，与 m4a 同族容器/编码
      case 'mov': // QuickTime/ISO-BMFF 同族容器（如 bilibili 下载源），按 m4a 处理
        return 'm4a';
      case 'ogg':
      case 'vorbis':
      case 'oga': // OGG 音频变体扩展名
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
      case 'aif':
      case 'aiff':
        return 'aiff';
      // Matroska 音频容器（songloft-org/songloft#297）：原生平台由 libmpv 直接播放并支持
      // 多音轨切换，Web 转码为 mp3。分平台处理见 getTranscodeFormat 的 mka 分支。
      case 'mka':
        return 'mka';
      // 视频容器（音频抽取场景，isVideo=false 时才可能进入此路径）：
      // 原生平台由 libmpv 直接播放（_getPlatformFormats 返回空集 → 不转码）；
      // Web/iOS/Android 不原生支持 → 触发后端转码为 mp3。
      case 'mpg':
      case 'flv':
      case 'wmv':
      case 'rmvb':
      case 'rm':
      case '3gp':
      case 'm4v':
      case 'mkv':
      case 'matroska':
      case 'webm':
      case 'avi':
      case 'ts':
        return fmt; // 保持原格式名，不在任何平台支持集中 → 自动触发转码
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
