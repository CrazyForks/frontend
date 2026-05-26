import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../storage/secure_storage.dart';

/// URL 构建工具类
///
/// 统一处理歌曲、封面、歌词等资源的 URL 拼接逻辑：
/// - 相对路径（/api/v1/...）：自动拼接 baseUrl + access_token
/// - 外部完整 URL（http/https）：直接返回
///
/// 所有客户端资源访问都应使用此类，确保认证 token 正确传递。
class UrlHelper {
  /// 构建完整的资源 URL
  ///
  /// [url] 资源 URL，可能是相对路径或完整 URL
  /// 返回：带有 baseUrl 和 access_token 的完整 URL
  static String buildResourceUrl(String url) {
    if (url.isEmpty) return '';

    // 外部 URL 直接返回
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    // 相对路径：拼接 baseUrl + access_token
    final token = SecureStorageService.cachedAccessToken ?? '';
    final separator = url.contains('?') ? '&' : '?';
    final fullUrl = '${AppConfig.baseUrl}$url${separator}access_token=$token';

    debugPrint('[UrlHelper] Built resource URL: $fullUrl');
    return fullUrl;
  }

  /// 构建歌曲播放 URL（兼容旧接口，内部调用 buildResourceUrl）
  static String buildSongUrl(String url) {
    return buildResourceUrl(url);
  }

  /// 构建封面图片 URL（兼容旧接口，内部调用 buildResourceUrl）
  static String buildCoverUrl(String coverUrl) {
    return buildResourceUrl(coverUrl);
  }

  /// 构建歌词 URL（兼容旧接口，内部调用 buildResourceUrl）
  static String buildLyricUrl(String lyricUrl) {
    return buildResourceUrl(lyricUrl);
  }
}
