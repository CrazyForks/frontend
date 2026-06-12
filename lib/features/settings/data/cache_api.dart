import 'package:dio/dio.dart';

import '../../../config/app_config.dart';

/// 缓存统计信息
class CacheStats {
  final int totalSize; // 字节
  final int fileCount;
  final int maxSize; // 字节，0 表示无限制

  CacheStats({
    required this.totalSize,
    required this.fileCount,
    required this.maxSize,
  });

  factory CacheStats.fromJson(Map<String, dynamic> json) {
    return CacheStats(
      totalSize: json['total_size'] as int? ?? 0,
      fileCount: json['file_count'] as int? ?? 0,
      maxSize: json['max_size'] as int? ?? 0,
    );
  }
}

/// 缓存配置
class CacheConfig {
  final int maxSize;
  final String cacheDir;
  final String defaultCacheDir;

  CacheConfig({
    required this.maxSize,
    this.cacheDir = '',
    this.defaultCacheDir = '',
  });

  factory CacheConfig.fromJson(Map<String, dynamic> json) {
    return CacheConfig(
      maxSize: json['max_size'] as int? ?? 0,
      cacheDir: json['cache_dir'] as String? ?? '',
      defaultCacheDir: json['default_cache_dir'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'max_size': maxSize,
      'cache_dir': cacheDir,
    };
  }
}

/// 目录验证结果
class DirValidateResult {
  final bool valid;
  final bool created;
  final int totalSize;
  final int freeSize;
  final String? error;

  DirValidateResult({
    required this.valid,
    required this.created,
    required this.totalSize,
    required this.freeSize,
    this.error,
  });

  factory DirValidateResult.fromJson(Map<String, dynamic> json) {
    return DirValidateResult(
      valid: json['valid'] as bool? ?? false,
      created: json['created'] as bool? ?? false,
      totalSize: json['total_size'] as int? ?? 0,
      freeSize: json['free_size'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }
}

/// 后端缓存管理 API 封装
class CacheApi {
  final Dio dio;

  CacheApi({required this.dio});

  /// 获取缓存统计信息
  Future<CacheStats> getCacheStats() async {
    final response = await dio.get('${AppConfig.apiPrefix}/cache-manage/stats');
    return CacheStats.fromJson(response.data as Map<String, dynamic>);
  }

  /// 清理全部缓存
  Future<void> cleanCache() async {
    await dio.post('${AppConfig.apiPrefix}/cache-manage/clean');
  }

  /// 获取缓存配置
  Future<CacheConfig> getCacheConfig() async {
    final response =
        await dio.get('${AppConfig.apiPrefix}/cache-manage/config');
    return CacheConfig.fromJson(response.data as Map<String, dynamic>);
  }

  /// 更新缓存配置
  Future<void> updateCacheConfig(CacheConfig config) async {
    await dio.put(
      '${AppConfig.apiPrefix}/cache-manage/config',
      data: config.toJson(),
    );
  }

  /// 验证缓存目录
  Future<DirValidateResult> validateCacheDir(String path) async {
    final response = await dio.post(
      '${AppConfig.apiPrefix}/cache-manage/validate-dir',
      data: {'path': path},
    );
    return DirValidateResult.fromJson(response.data as Map<String, dynamic>);
  }
}
