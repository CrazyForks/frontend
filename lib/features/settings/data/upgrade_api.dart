import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_exceptions.dart';

/// 版本信息模型
class VersionInfo {
  final String version;
  final String? releaseNotes;
  final DateTime? releaseDate;

  VersionInfo({
    required this.version,
    this.releaseNotes,
    this.releaseDate,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      version: json['version'] as String,
      releaseNotes: json['release_notes'] as String?,
      releaseDate: json['release_date'] != null
          ? DateTime.parse(json['release_date'] as String)
          : null,
    );
  }

  @override
  String toString() => 'VersionInfo(version: $version)';
}

/// 更新检查结果模型
class UpgradeCheck {
  final bool hasUpdate;
  final String? latestVersion;
  final String? currentVersion;
  final String? releaseNotes;

  UpgradeCheck({
    required this.hasUpdate,
    this.latestVersion,
    this.currentVersion,
    this.releaseNotes,
  });

  factory UpgradeCheck.fromJson(Map<String, dynamic> json) {
    // 优先读取扁平字段，fallback 到嵌套结构
    String? currentVersion = json['current_version'] as String?;
    if (currentVersion == null || currentVersion.isEmpty) {
      final current = json['current'] as Map<String, dynamic>?;
      currentVersion = current?['version'] as String?;
    }

    String? latestVersion = json['latest_version'] as String?;
    String? releaseNotes = json['release_notes'] as String?;
    if (latestVersion == null || latestVersion.isEmpty) {
      final updates = json['updates'] as Map<String, dynamic>?;
      if (updates != null) {
        // 优先取 stable，其次 dev
        final stable = updates['stable'] as Map<String, dynamic>?;
        final dev = updates['dev'] as Map<String, dynamic>?;
        final preferred = stable ?? dev;
        if (preferred != null) {
          latestVersion ??= preferred['version'] as String?;
          releaseNotes ??= preferred['release_notes'] as String?;
        }
      }
    }

    return UpgradeCheck(
      hasUpdate: json['has_update'] as bool? ?? false,
      latestVersion: latestVersion,
      currentVersion: currentVersion,
      releaseNotes: releaseNotes,
    );
  }

  @override
  String toString() =>
      'UpgradeCheck(hasUpdate: $hasUpdate, current: $currentVersion, latest: $latestVersion)';
}

/// 升级进度模型
class UpgradeProgress {
  final String
      status; // 'idle', 'downloading', 'testing', 'replacing', 'restarting', 'completed', 'error'
  final int progress; // 0-100
  final String? message;

  UpgradeProgress({
    required this.status,
    required this.progress,
    this.message,
  });

  factory UpgradeProgress.fromJson(Map<String, dynamic> json) {
    return UpgradeProgress(
      status: json['status'] as String? ?? 'idle',
      progress: json['progress'] as int? ?? 0,
      message: json['message'] as String?,
    );
  }

  /// 默认空闲状态
  static UpgradeProgress get idle => UpgradeProgress(
        status: 'idle',
        progress: 0,
      );

  /// 是否正在升级
  bool get isUpgrading =>
      status == 'downloading' ||
      status == 'testing' ||
      status == 'replacing' ||
      status == 'restarting';

  /// 是否完成
  bool get isCompleted => status == 'completed';

  /// 是否出错
  bool get isError => status == 'error';

  /// 是否空闲
  bool get isIdle => status == 'idle';

  /// 状态显示文本
  String get statusText {
    switch (status) {
      case 'downloading':
        return '正在下载...';
      case 'testing':
        return '正在验证...';
      case 'replacing':
        return '正在替换...';
      case 'restarting':
        return '正在重启...';
      case 'completed':
        return '升级完成';
      case 'error':
        return '升级失败';
      default:
        return '空闲';
    }
  }

  @override
  String toString() =>
      'UpgradeProgress(status: $status, progress: $progress%)';
}

/// 升级 API 服务
class UpgradeApi {
  final Dio dio;

  UpgradeApi({required this.dio});

  /// 获取可用版本列表
  /// GET /api/v1/upgrade/versions
  Future<List<VersionInfo>> getVersions() async {
    try {
      final response = await dio.get('${AppConfig.apiPrefix}/upgrade/versions');
      final data = response.data as List<dynamic>;
      return data
          .map((e) => VersionInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 检查更新
  /// GET /api/v1/upgrade/check
  /// [githubProxy] 为 GitHub 代理前缀，为空则直连
  Future<UpgradeCheck> checkUpgrade({String? githubProxy}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (githubProxy != null && githubProxy.isNotEmpty) {
        queryParams['github_proxy'] = githubProxy;
      }
      final response = await dio.get(
        '${AppConfig.apiPrefix}/upgrade/check',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      return UpgradeCheck.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 开始升级
  /// POST /api/v1/upgrade/start
  /// [githubProxy] 为 GitHub 代理前缀，为空则直连
  Future<void> startUpgrade({String? githubProxy}) async {
    try {
      final data = <String, dynamic>{};
      if (githubProxy != null && githubProxy.isNotEmpty) {
        data['github_proxy'] = githubProxy;
      }
      await dio.post(
        '${AppConfig.apiPrefix}/upgrade/start',
        data: data.isNotEmpty ? data : null,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 获取升级进度
  /// GET /api/v1/upgrade/progress
  Future<UpgradeProgress> getProgress() async {
    try {
      final response = await dio.get('${AppConfig.apiPrefix}/upgrade/progress');
      return UpgradeProgress.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
