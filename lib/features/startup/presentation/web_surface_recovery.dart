// Web 端 CanvasKit WebGL context 丢失后的 surface 恢复(仅 Web 有意义)。
//
// 条件导出:Web 平台走 web_surface_recovery_web.dart(操作 DOM canvas),
// 其它平台走 web_surface_recovery_stub.dart(no-op,避免把 package:web 牵入
// 原生构建)。
export 'web_surface_recovery_stub.dart'
    if (dart.library.js_interop) 'web_surface_recovery_web.dart';
