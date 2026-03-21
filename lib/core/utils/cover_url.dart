import '../../config/app_config.dart';
import '../storage/secure_storage.dart';
import 'encode.dart';
import 'proxy_url.dart';

class CoverUrl {
  /// 构建封面图片 URL
  /// 如果有 cover_url 直接返回（外部 URL 在 Web 平台自动走代理），
  /// 否则使用 cover_path 构建服务器 URL。
  /// iOS AVPlayer 不支持自定义 Header 认证，使用 URL query parameter
  static String? buildCoverUrl({
    String? coverUrl,
    String? coverPath,
  }) {
    if (coverUrl != null && coverUrl.isNotEmpty) {
      // 外部 URL 在 Web 平台通过后端代理转发，解决 CORS 限制
      if (ProxyUrl.isExternalUrl(coverUrl)) {
        return ProxyUrl.buildProxyUrl(coverUrl);
      }
      return coverUrl;
    }
    if (coverPath != null && coverPath.isNotEmpty) {
      // 分离路径和扩展名
      final pathWithoutExt = getPathWithoutExtension(coverPath);
      final ext = getExtension(coverPath);
      // Base62 编码路径（不含扩展名）
      final encodedPath = encodeBase62(pathWithoutExt);
      // 使用缓存的 access token
      final token = SecureStorageService.cachedAccessToken ?? '';
      // 格式: /cover/{base62编码的路径}{扩展名}?access_token=xxx
      return '${AppConfig.baseUrl}/cover/$encodedPath$ext?access_token=$token';
    }
    return null;
  }
}
