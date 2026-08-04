import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// native 平台：给 Dio 装上无条件接受任意证书的 HttpClient 适配器。
///
/// 不安全，仅在用户显式开启「忽略 SSL 证书校验」时调用，用于自签/内网证书场景。
void applyInsecureTls(Dio dio) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    },
  );
}

class _InsecureHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }
}

/// 设置全局 [HttpOverrides]，使所有 Dart [HttpClient] 实例（包括 just_audio 的
/// [LockCachingAudioSource] 内部 HTTP 客户端）在 [insecure] 为 true 时接受任意证书。
void applyGlobalInsecureHttpOverrides(bool insecure) {
  HttpOverrides.global = insecure ? _InsecureHttpOverrides() : null;
}

/// 给 Dio 配置短空闲超时的 HttpClient，可选忽略 SSL 证书。
///
/// Windows 冷启动时连接池中的空闲连接可能在休眠/网络切换后变为半开状态。
/// 将 idleTimeout 缩短到 5 秒可让 dart:io 更积极地丢弃空闲连接，减少复用到
/// 死连接的概率（songloft-org/songloft#314）。
void applyHttpClientConfig(Dio dio, {bool insecureTls = false}) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.idleTimeout = const Duration(seconds: 5);
      if (insecureTls) {
        client.badCertificateCallback = (cert, host, port) => true;
      }
      return client;
    },
  );
}
