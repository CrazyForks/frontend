import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// 遍历页面(含 shadow root)上的所有 `<canvas>`,对「WebGL context 已丢失」的
/// 画布派发一个合成的 `webglcontextlost` 事件,促使 Flutter 引擎把该画布标记为
/// 需要重建(`Surface._forceNewContext = true`)。随后由 framework 强制产出的一帧
/// 会触发引擎 `createOrUpdateSurface` 用全新 canvas + GL context 重建 surface。
///
/// 背景:Android Chrome 冻结后台标签页时可能「静默」丢弃 GPU context 而**不**派发
/// `webglcontextlost` 事件,引擎因此从不置 `_forceNewContext`、从不重建;回前台后
/// 即便强制产帧,也只是往已死的 context 上绘制 → 画面空白(白屏)。这里主动补发
/// 该事件补齐这一步。
///
/// 仅对确实报告 `isContextLost() == true` 的 context 处理,健康画布不受影响,避免
/// 每次切前台都无谓重建/闪烁。
///
/// 返回补发了事件的画布数量,供调用方记录诊断。
int recoverLostWebGlContexts() {
  final canvases = <web.HTMLCanvasElement>[];
  _collectCanvases(web.document, canvases);

  var recovered = 0;
  for (final canvas in canvases) {
    if (_isContextLost(canvas)) {
      canvas.dispatchEvent(web.Event('webglcontextlost'));
      recovered++;
    }
  }

  if (recovered > 0) {
    debugPrint(
      '[WebSurfaceRecovery] 检测到 $recovered/${canvases.length} 个 canvas 的 '
      'WebGL context 已丢失,已补发 webglcontextlost 触发引擎重建',
    );
  }
  return recovered;
}

/// 同时具备 `querySelectorAll` 的根节点(Document / ShadowRoot 等)统一视图。
extension type _QueryRoot(JSObject _) implements JSObject {
  external web.NodeList querySelectorAll(String selectors);
}

/// 收集 [root] 下所有 `<canvas>`,并递归进入每个元素的(open)shadow root。
/// Flutter 视图在部分版本会把渲染 canvas 放进 shadow DOM,故需一并遍历。
void _collectCanvases(JSObject root, List<web.HTMLCanvasElement> out) {
  final q = root as _QueryRoot;

  final direct = q.querySelectorAll('canvas');
  for (var i = 0; i < direct.length; i++) {
    final node = direct.item(i);
    if (node != null && node.isA<web.HTMLCanvasElement>()) {
      out.add(node as web.HTMLCanvasElement);
    }
  }

  final all = q.querySelectorAll('*');
  for (var i = 0; i < all.length; i++) {
    final node = all.item(i);
    if (node != null && node.isA<web.Element>()) {
      final shadow = (node as web.Element).shadowRoot;
      if (shadow != null) {
        _collectCanvases(shadow, out);
      }
    }
  }
}

bool _isContextLost(web.HTMLCanvasElement canvas) {
  // getContext 会返回该画布已存在的同一个 context(不会新建),null 表示从未
  // 创建过 WebGL context(该 canvas 与我们无关)。
  final ctx = canvas.getContext('webgl2') ?? canvas.getContext('webgl');
  if (ctx == null) return false;
  // WebGLRenderingContext 与 WebGL2RenderingContext 都提供 isContextLost();
  // 扩展类型的 cast 是零成本重解释,底层 JS 对象具备该方法即可正常调用。
  return (ctx as web.WebGLRenderingContext).isContextLost();
}
