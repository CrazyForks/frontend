/// 非 Web 平台的 no-op 实现:原生端不存在 WebGL context 丢失问题。
///
/// 返回被判定为「context 已丢失」并已补发 `webglcontextlost` 的画布数量,原生端
/// 恒为 0。
int recoverLostWebGlContexts() => 0;
