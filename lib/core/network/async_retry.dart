import 'dart:async';

/// 带「单次超时 + 有限重试」的异步加载兜底，用于**首屏关键请求**的韧性保护。
///
/// 背景（songloft-org/songloft#314）：Windows 端偶发「服务端已 200 快速返回、但某个
/// 首屏请求卡在连接上迟迟不完成」，导致首页无限骨架屏、用户只能反复退出重启 5、6 次。
/// dio 自带的 30s 超时既太长、又不重试，卡住的请求要么等满 30s，要么永不恢复。
///
/// 这里对每次尝试单独加 [attemptTimeout] 超时：超时或失败后短暂退避再重试，最多
/// [maxAttempts] 次。重试会重新发起请求（dart:io 会为其新开一条连接，因为卡住的连接
/// 仍被上一个未完成的请求占用），从而绕开卡住的坏连接自愈；全部尝试失败才抛出最后一次
/// 错误，交由上层显示错误态 + 手动重试按钮。
///
/// 注意：Dart 的 Future 不可取消，`.timeout()` 只是**放弃等待**，被放弃的请求仍会在后台
/// 跑完（无害，其结果被忽略）。故 [action] 每次调用都应发起一次**新的**请求，不要复用
/// 同一个 Future。
Future<T> loadWithRetry<T>(
  Future<T> Function() action, {
  Duration attemptTimeout = const Duration(seconds: 6),
  int maxAttempts = 4,
  Duration retryDelay = const Duration(milliseconds: 400),
  void Function(int attempt, Object error)? onRetry,
}) async {
  assert(maxAttempts >= 1);
  Object? lastError;
  StackTrace? lastStack;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await action().timeout(attemptTimeout);
    } catch (error, stack) {
      lastError = error;
      lastStack = stack;
      if (attempt < maxAttempts) {
        onRetry?.call(attempt, error);
        await Future.delayed(retryDelay);
      }
    }
  }
  Error.throwWithStackTrace(lastError!, lastStack!);
}
