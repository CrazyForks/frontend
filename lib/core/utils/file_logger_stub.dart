class FileLogger {
  FileLogger._();

  static Future<void> init() async {}

  static void writeln(String line) {}

  static Future<void> flush() async {}

  static Future<void> close() async {}

  static String? get logFilePath => null;

  static String? get logDir => null;
}
