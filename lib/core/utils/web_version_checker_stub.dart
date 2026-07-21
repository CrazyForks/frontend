/// 原生平台空实现：版本检测仅 Web 端有意义（浏览器缓存过期问题）。
Future<({String version, String buildTime})?> fetchDeployedVersion() async =>
    null;

String? readReloadSentinel() => null;

void writeReloadSentinel(String buildTime) {}
