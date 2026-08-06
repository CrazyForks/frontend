import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// GitHub 加速代理的统一套用与「失败降级直连」封装。
///
/// 背景：用户配置的加速代理可能整体失效（如 mirror.ghproxy.com 停服）或间歇
/// 抖动，若不降级，热更 manifest / 整包检查会静默失败。凡是「后端拉取」以外
/// 的前端直连 GitHub 请求都应走这里，代理失败时自动用原始 URL 直连重试一次。

/// 判断 URL 是否为 GitHub 相关域名（与后端 IsGitHubURL 保持一致）。
bool _isGitHubUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'github.com' ||
      host == 'raw.githubusercontent.com' ||
      host == 'objects.githubusercontent.com' ||
      host == 'api.github.com' ||
      host.endsWith('.github.io');
}

/// 给 URL 套 GitHub 加速代理前缀。仅对 GitHub 相关域名生效，非 GitHub
/// URL（如 gitee.com）原样返回，避免错误代理导致请求失败。
String applyGithubProxy(String rawUrl, String? proxy) {
  if (proxy == null || proxy.isEmpty) return rawUrl;
  if (!_isGitHubUrl(rawUrl)) return rawUrl;
  final prefix = proxy.endsWith('/') ? proxy : '$proxy/';
  return '$prefix$rawUrl';
}

/// 给 URL 追加一次性时间戳参数，击穿加速代理/CDN 对**滚动内容**（dev tag 的热更
/// manifest、/releases/latest）的缓存。GitHub 忽略未知查询参数；代理以完整 URL 为
/// 缓存键,参数每次不同 → 必然回源。**只用于小体积的滚动资源**,补丁包本体是带
/// commit 的不可变文件名,无需也不应击穿缓存。
String withCacheBuster(String rawUrl) {
  final sep = rawUrl.contains('?') ? '&' : '?';
  return '$rawUrl$sep'
      '_cb=${DateTime.now().millisecondsSinceEpoch}';
}

/// GET [rawUrl]（套 [proxy]）。设置了代理且请求失败（连接错/超时/非 2xx）时，
/// 打日志后改用原始 URL 直连重试一次；直连的结果/异常原样抛给调用方。
Future<Response<T>> githubGetWithProxyFallback<T>(
  Dio dio,
  String rawUrl, {
  String? proxy,
  Options? options,
}) async {
  final url = applyGithubProxy(rawUrl, proxy);
  if (url == rawUrl) {
    return dio.get<T>(rawUrl, options: options);
  }
  try {
    return await dio.get<T>(url, options: options);
  } on DioException catch (e) {
    debugPrint('[GithubProxy] 代理请求失败,降级直连重试: 失败URL=$url ($e)');
    return dio.get<T>(rawUrl, options: options);
  }
}

/// `dio.download` 版，语义同 [githubGetWithProxyFallback]。
/// 降级重试会从头下载并覆盖 [savePath]。
Future<void> githubDownloadWithProxyFallback(
  Dio dio,
  String rawUrl,
  String savePath, {
  String? proxy,
  ProgressCallback? onReceiveProgress,
}) async {
  final url = applyGithubProxy(rawUrl, proxy);
  if (url == rawUrl) {
    await dio.download(rawUrl, savePath, onReceiveProgress: onReceiveProgress);
    return;
  }
  try {
    await dio.download(url, savePath, onReceiveProgress: onReceiveProgress);
  } on DioException catch (e) {
    debugPrint('[GithubProxy] 代理下载失败,降级直连重试: 失败URL=$url ($e)');
    await dio.download(rawUrl, savePath, onReceiveProgress: onReceiveProgress);
  }
}
