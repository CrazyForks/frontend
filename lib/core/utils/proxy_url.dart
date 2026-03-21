import 'package:flutter/foundation.dart' show kIsWeb;

import '../../config/app_config.dart';
import '../storage/secure_storage.dart';

/// 通用资源代理工具
/// 在 Web 平台上，外部 URL 会通过后端代理接口转发，解决浏览器 CORS 限制。
/// 在原生平台上，外部 URL 直接使用，无需代理。
class ProxyUrl {
  /// 将外部 URL 转换为代理 URL（仅 Web 平台生效）
  ///
  /// [externalUrl] 外部资源的完整 URL（如 https://y.gtimg.cn/...）
  /// 返回值：Web 平台返回代理 URL，原生平台返回原始 URL
  static String buildProxyUrl(String externalUrl) {
    if (!kIsWeb) {
      return externalUrl;
    }

    // 仅代理外部 http/https URL
    if (!externalUrl.startsWith('http://') &&
        !externalUrl.startsWith('https://')) {
      return externalUrl;
    }

    // 检查是否为同域请求（已经指向后端的 URL 无需代理）
    if (externalUrl.startsWith(AppConfig.baseUrl)) {
      return externalUrl;
    }

    final token = SecureStorageService.cachedAccessToken ?? '';
    final encodedUrl = Uri.encodeComponent(externalUrl);
    return '${AppConfig.baseUrl}${AppConfig.apiPrefix}/proxy?url=$encodedUrl&access_token=$token';
  }

  /// 判断 URL 是否为外部地址（非后端同域）
  static bool isExternalUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return false;
    }
    return !url.startsWith(AppConfig.baseUrl);
  }
}
