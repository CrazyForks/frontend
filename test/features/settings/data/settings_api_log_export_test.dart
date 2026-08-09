import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/settings/data/settings_api.dart';

class _LogExportAdapter implements HttpClientAdapter {
  _LogExportAdapter({this.failHealth = false});

  final bool failHealth;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/health')) {
      if (failHealth) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        );
      }
      return ResponseBody.fromString(
        '{"status":"ok"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromBytes(
      [1, 2, 3],
      200,
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('健康探测成功后下载后端日志并使用独立超时', () async {
    final adapter = _LogExportAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:58091'))
      ..httpClientAdapter = adapter;
    final api = SettingsApi(dio: dio);

    final bytes = await api.downloadBackendLogs();

    expect(bytes, [1, 2, 3]);
    expect(adapter.requests.map((request) => request.path), [
      '/api/v1/health',
      '/api/v1/logs/export',
    ]);
    expect(adapter.requests.first.connectTimeout, const Duration(seconds: 3));
    expect(adapter.requests.first.receiveTimeout, const Duration(seconds: 3));
    expect(adapter.requests.last.receiveTimeout, const Duration(seconds: 60));
    expect(adapter.requests.last.responseType, ResponseType.bytes);
  });

  test('健康探测失败时不再发起大日志请求', () async {
    final adapter = _LogExportAdapter(failHealth: true);
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:58091'))
      ..httpClientAdapter = adapter;
    final api = SettingsApi(dio: dio);

    await expectLater(api.downloadBackendLogs(), throwsA(isA<Exception>()));

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.path, '/api/v1/health');
  });
}
