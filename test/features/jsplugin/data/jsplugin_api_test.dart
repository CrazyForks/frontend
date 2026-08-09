import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/jsplugin/data/jsplugin_api.dart';

class _RegistryAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '{"plugins":[],"total":0,"page":1,"page_size":20}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('注册表刷新使用独立的 60 秒接收超时', () async {
    final adapter = _RegistryAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost:58091',
        receiveTimeout: const Duration(seconds: 15),
      ),
    )..httpClientAdapter = adapter;
    final api = JSPluginApi(dio: dio);

    final response = await api.refreshRegistry(allSources: true);

    expect(response.plugins, isEmpty);
    expect(adapter.request?.path, '/api/v1/jsplugins/registry/refresh');
    expect(adapter.request?.receiveTimeout, const Duration(seconds: 60));
    expect(adapter.request?.data, containsPair('all_sources', true));
  });
}
