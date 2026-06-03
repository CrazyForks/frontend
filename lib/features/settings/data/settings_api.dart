import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_exceptions.dart';

/// 音乐路径与扫描排除配置（GET/PUT /settings/music-path）
class MusicPathSetting {
  final String path;
  final List<String> excludeDirs;
  final List<String> excludePaths;

  MusicPathSetting({
    required this.path,
    required this.excludeDirs,
    required this.excludePaths,
  });

  factory MusicPathSetting.fromJson(Map<String, dynamic> json) {
    return MusicPathSetting(
      path: json['path'] as String? ?? 'music',
      excludeDirs:
          (json['exclude_dirs'] as List?)?.map((e) => e as String).toList() ??
              <String>[],
      excludePaths:
          (json['exclude_paths'] as List?)?.map((e) => e as String).toList() ??
              <String>[],
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'exclude_dirs': excludeDirs,
        'exclude_paths': excludePaths,
      };

  MusicPathSetting copyWith({
    String? path,
    List<String>? excludeDirs,
    List<String>? excludePaths,
  }) =>
      MusicPathSetting(
        path: path ?? this.path,
        excludeDirs: excludeDirs ?? this.excludeDirs,
        excludePaths: excludePaths ?? this.excludePaths,
      );
}

/// 插件订阅源配置
class PluginRegistryConfig {
  final String url;
  final String name;
  final bool enabled;

  PluginRegistryConfig({
    required this.url,
    required this.name,
    this.enabled = true,
  });

  factory PluginRegistryConfig.fromJson(Map<String, dynamic> json) {
    return PluginRegistryConfig(
      url: json['url'] as String? ?? '',
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'enabled': enabled,
      };

  PluginRegistryConfig copyWith({String? url, String? name, bool? enabled}) =>
      PluginRegistryConfig(
        url: url ?? this.url,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
      );
}

/// 业务化设置 API 集合（/api/v1/settings/*）
///
/// 用户可见的功能开关一律走这里；通用 KV 配置仍走 ConfigApi（admin 入口）。
/// 详见后端 AGENTS.md「配置接口规范」。
class SettingsApi {
  final Dio dio;

  SettingsApi({required this.dio});

  // ---------- HLS 反向代理开关 ----------

  Future<bool> getHlsProxyEnabled() async {
    try {
      final response = await dio.get(
        '${AppConfig.apiPrefix}/settings/hls-proxy',
      );
      final data = response.data as Map<String, dynamic>;
      return data['enabled'] as bool? ?? false;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> setHlsProxyEnabled(bool enabled) async {
    try {
      await dio.put(
        '${AppConfig.apiPrefix}/settings/hls-proxy',
        data: {'enabled': enabled},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ---------- 扫描后自动创建歌单是否包含子目录 ----------

  Future<bool> getScanAutoCreateIncludeSubdirs() async {
    try {
      final response = await dio.get(
        '${AppConfig.apiPrefix}/settings/scan-auto-create-include-subdirs',
      );
      final data = response.data as Map<String, dynamic>;
      return data['enabled'] as bool? ?? false;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> setScanAutoCreateIncludeSubdirs(bool enabled) async {
    try {
      await dio.put(
        '${AppConfig.apiPrefix}/settings/scan-auto-create-include-subdirs',
        data: {'enabled': enabled},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ---------- 音乐路径与扫描排除 ----------

  Future<MusicPathSetting> getMusicPath() async {
    try {
      final response =
          await dio.get('${AppConfig.apiPrefix}/settings/music-path');
      return MusicPathSetting.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<MusicPathSetting> updateMusicPath(MusicPathSetting setting) async {
    try {
      final response = await dio.put(
        '${AppConfig.apiPrefix}/settings/music-path',
        data: setting.toJson(),
      );
      return MusicPathSetting.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ---------- 日志等级（debug / info / warn / error） ----------

  Future<String> getLogLevel() async {
    try {
      final response = await dio.get(
        '${AppConfig.apiPrefix}/settings/log-level',
      );
      final data = response.data as Map<String, dynamic>;
      return data['level'] as String? ?? 'info';
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> setLogLevel(String level) async {
    try {
      await dio.put(
        '${AppConfig.apiPrefix}/settings/log-level',
        data: {'level': level},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ---------- 插件订阅源 ----------

  Future<List<PluginRegistryConfig>> getPluginRegistries() async {
    try {
      final response = await dio.get(
        '${AppConfig.apiPrefix}/settings/plugin-registries',
      );
      final data = response.data as Map<String, dynamic>;
      final list = data['registries'] as List<dynamic>? ?? [];
      return list
          .map((e) =>
              PluginRegistryConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<PluginRegistryConfig>> updatePluginRegistries(
    List<PluginRegistryConfig> registries,
  ) async {
    try {
      final response = await dio.put(
        '${AppConfig.apiPrefix}/settings/plugin-registries',
        data: {'registries': registries.map((r) => r.toJson()).toList()},
      );
      final data = response.data as Map<String, dynamic>;
      final list = data['registries'] as List<dynamic>? ?? [];
      return list
          .map((e) =>
              PluginRegistryConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
