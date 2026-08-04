import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// 插件页的 `files` 命名空间 —— 把 `input[type=file]` 下沉到宿主原生选择器
/// （songloft-org/songloft#341 Step 6）。
///
/// ## 为什么需要它
///
/// WebF 的 `<input>` 实现里没有 file 分支（`html/form/input.dart:250-266` 的
/// `build()` switch 落到 `default`）→ `type=file` 变成一个 Flutter `TextField`，
/// 点了什么都不会发生。验证容器还实测到 **WebF 里 `FileReader` / `FileList`
/// 都不存在**，所以「在 JS 里伪造 `input.files` + `FileReader`」这条路是死的
/// —— 只能由宿主弹选择器、把内容经桥送回页面。
///
/// ## 为什么不放进 `PluginHostDispatcher`
///
/// 那个文件刻意是 **web-safe** 的（不 import `dart:io`），被 Web 平台的 iframe
/// 页面直接引用。本文件要 `File(path).readAsBytes()` 兜底，必然带 `dart:io`。
/// 而这个缺口**只存在于 WebF**（浏览器与系统 WebView 的原生 file input 正常工作，
/// `common.js` 的垫片也关在 `isWebFEngine()` 里、压根不会发起这个调用），
/// 所以只挂在 WebF 渲染面上是正确的作用域，不是权宜。
///
/// ## 契约（与 `common.js` 的 `filePickerShim` 一一对应）
///
/// 请求 `{ns:'files', method:'pickFile', params:{accept, multiple, as}}`：
/// - `accept`：原样透传 `<input accept>`。**扩展名形式与 MIME 形式都可能出现**
///   （radio 写的是 `'.m3u,.m3u8,.json,.txt'`），见 [_parseAccept]。
/// - `multiple`：`<input multiple>` 是否存在。
/// - `as`：`'text'`（默认）/ `'bytes'` / `'none'`，决定载荷形态。
///
/// 应答 `{files:[{name, size, text?, bytesBase64?, encoding?, textLossy?}]}`，
/// 用户取消时 `{files:[], canceled:true}`。
///
/// ### 刻意不返回 `path`
///
/// 三条理由：① 桌面端 `file_picker` 给的是真实路径、Android SAF 给的是 content
/// URI，**跨平台语义不一致**；② path 对页面侧 JS **毫无用处**（它读不了文件
/// 系统）；③ 把宿主文件系统路径交给插件 JS 是不必要的信息泄露。
/// 将来若真有「把用户选的文件交给后端处理」的需求，那应该走后端上传端点。
class PluginFileBridge {
  /// 单文件最大读取字节数。
  ///
  /// 载荷要跨两次序列化（Dart → C++ → QuickJS），base64 还会再放大 4/3。
  /// 32 MB 是「radio 那类导入文件（m3u/json，通常几十 KB～几 MB）绰绰有余」
  /// 与「不至于让一次误选把 QuickJS 堆撑爆」之间的取舍。超限时**返回元信息 +
  /// 明确错误**而不是静默截断 —— 截断后的 m3u 解析出来是「导入成功但少了一半」，
  /// 那比报错难查得多。
  static const int maxFileBytes = 32 * 1024 * 1024;

  /// 处理一次 `files.*` 调用。返回值是 `data` 字段的内容（不含 `{ok:…}` 信封，
  /// 信封由调用方统一加）。
  static Future<dynamic> handle(
    String? method,
    Map<String, dynamic> params,
  ) async {
    if (method != 'pickFile') {
      throw Exception('unknown files method: $method');
    }
    return _pickFile(params);
  }

  static Future<Map<String, dynamic>> _pickFile(
    Map<String, dynamic> params,
  ) async {
    final bool multiple = params['multiple'] == true;
    final String as = (params['as'] as String?)?.toLowerCase() ?? 'text';
    final List<String>? extensions = _parseAccept(params['accept'] as String?);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: multiple,
        // 有可用的扩展名白名单才切 custom：`FileType.custom` 要求
        // `allowedExtensions` 非空，否则 file_picker 自己会抛。
        type: extensions == null ? FileType.any : FileType.custom,
        allowedExtensions: extensions,
        // 让 file_picker 直接把字节读进内存。
        //
        // 不这么做的话 Android SAF 只给 content URI，`File(uri)` 读不了。
        // 但**不能只依赖它**：某些平台/大文件下仍可能只给 path 不给 bytes，
        // 所以下面 [_readBytes] 还有一条 path 兜底。
        withData: as != 'none',
      );
    } catch (e) {
      debugPrint('[plugin][files] pickFiles failed: $e');
      // 抛出去由外层包成 {ok:false,error}：JS 侧的垫片会 console.warn 并
      // **不派发 change**，页面维持原状。
      throw Exception('file picker unavailable: $e');
    }

    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) {
      // 用户取消。刻意不当成错误：JS 侧据此静默返回，不弹「读取失败」。
      return {'files': const <Map<String, dynamic>>[], 'canceled': true};
    }

    final out = <Map<String, dynamic>>[];
    for (final f in files) {
      out.add(await _describe(f, as));
      // multiple=false 时理论上只会有一项，这里仍然设一道上限：
      // 某些平台的选择器在 allowMultiple=false 下也可能返回多项。
      if (!multiple) break;
    }
    return {'files': out};
  }

  static Future<Map<String, dynamic>> _describe(
    PlatformFile f,
    String as,
  ) async {
    final Map<String, dynamic> item = {'name': f.name, 'size': f.size};
    if (as == 'none') return item;

    if (f.size > maxFileBytes) {
      item['error'] = 'too_large';
      item['limit'] = maxFileBytes;
      return item;
    }

    final Uint8List? bytes = await _readBytes(f);
    if (bytes == null) {
      item['error'] = 'read_failed';
      return item;
    }

    if (as == 'bytes') {
      item['bytesBase64'] = base64Encode(bytes);
      return item;
    }

    final _Decoded decoded = _decodeText(bytes);
    item['text'] = decoded.text;
    item['encoding'] = decoded.encoding;
    if (decoded.lossy) item['textLossy'] = true;
    return item;
  }

  /// 两条路都要走：`withData: true` 通常已经把字节读好（Android SAF 只有这条路
  /// 能读），但**不能假定它一定有** —— 某些平台/大文件下 `bytes` 为 null 而
  /// 只给 `path`。
  static Future<Uint8List?> _readBytes(PlatformFile f) async {
    if (f.bytes != null) return f.bytes;
    final path = f.path;
    if (path == null || path.isEmpty) return null;
    try {
      return await File(path).readAsBytes();
    } catch (e) {
      debugPrint('[plugin][files] read $path failed: $e');
      return null;
    }
  }

  /// 文本解码。**只按 BOM + 严格 UTF-8 判定，不猜 GBK。**
  ///
  /// 判定顺序与后端 `ReadSidecarLyric`（`internal/services`）刻意一致：
  /// UTF-16 LE/BE 按 BOM → UTF-8（含 BOM 剥离）。
  ///
  /// ⚠️ **与后端的差异要如实说**：后端还有一层 `tag.FixEncoding` 做 GBK 系修正，
  /// 这里**没有** —— Dart 没有内建 GBK 编解码器，补上它要新增一个 pub 依赖，
  /// 而**新增依赖会改动 Android 原生契约哈希**（`## plugin-versions` 段把插件
  /// 版本号也纳入 sha256），代价是整包发版、热更被阻断。为一个「非 UTF-8 的
  /// m3u」场景付这个代价不值得。
  ///
  /// 所以 GBK 文件走的是 `allowMalformed: true` + `textLossy: true` 标记：
  /// 插件能看出「这份文本不可信」，需要精确处理时改用 `as: 'bytes'` 自己解码。
  static _Decoded _decodeText(Uint8List bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _Decoded(_decodeUtf16(bytes, 2, littleEndian: true), 'utf-16le');
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _Decoded(
          _decodeUtf16(bytes, 2, littleEndian: false),
          'utf-16be',
        );
      }
    }
    // UTF-8 BOM：留着会变成正文开头一个不可见的 U+FEFF，插件解析 m3u 时
    // 首行 `#EXTM3U` 就匹配不上（后端 ReadSidecarLyric 同样剥它）。
    var body = bytes;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      body = Uint8List.sublistView(bytes, 3);
    }
    try {
      return _Decoded(utf8.decode(body), 'utf-8');
    } catch (_) {
      return _Decoded(
        utf8.decode(body, allowMalformed: true),
        'utf-8-lossy',
        lossy: true,
      );
    }
  }

  static String _decodeUtf16(
    Uint8List bytes,
    int offset, {
    required bool littleEndian,
  }) {
    final units = <int>[];
    for (var i = offset; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  /// `<input accept>` → `file_picker` 的 `allowedExtensions`。
  ///
  /// 返回 null 表示「不加过滤」（`FileType.any`）。**只认 `.ext` 这一种形式**
  /// （HTML 规范里的扩展名写法）：`file_picker` 的 `allowedExtensions` 要的就是
  /// 不带点的扩展名，而 MIME 形式（`text/plain`、`image/*`）无法可靠地反推成
  /// 扩展名集合。
  ///
  /// 混写时（`accept=".m3u,text/plain"`）刻意**整体放弃过滤**而不是只取能认的
  /// 那部分：只过滤一半会让用户看不到本来允许的 `.txt`，而「过滤器比声明宽」
  /// 只是多几个可选项、插件自己还会校验，前者才是真的挡住用户。
  static List<String>? _parseAccept(String? accept) {
    if (accept == null) return null;
    final raw = accept.split(',');
    final exts = <String>[];
    for (final part in raw) {
      final token = part.trim();
      if (token.isEmpty) continue;
      if (token.startsWith('.')) {
        final ext = token.substring(1).toLowerCase();
        if (ext.isEmpty || ext.contains('/') || ext.contains('*')) return null;
        exts.add(ext);
        continue;
      }
      // MIME 形式 / 通配符 → 放弃过滤（见上面的取舍说明）
      return null;
    }
    return exts.isEmpty ? null : exts;
  }
}

class _Decoded {
  const _Decoded(this.text, this.encoding, {this.lossy = false});

  final String text;
  final String encoding;
  final bool lossy;
}
