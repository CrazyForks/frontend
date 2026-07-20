import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/widgets.dart';

/// 封面网络图统一封装：web 走 `HttpGet` 字节解码 + `memCacheWidth` 缩略。
///
/// 用于 [CoverImage] 覆盖不到的、直接用 `CachedNetworkImage` 渲染封面的场景
/// （专辑/歌手网格、首页歌单轮播、hero 卡片、歌单详情、播放队列等）。
///
/// 为什么必须缩略：web 默认 `ImageRenderMethodForWeb.HtmlImage` 路径按**原图全
/// 分辨率**（实测 ~1.5MB/张）上传为 GPU 纹理，且 `memCacheWidth` 在该路径不生效。
/// 大量大封面（网格/轮播/卡片）纹理累积挤爆移动端 GPU 显存预算 → CanvasKit 的
/// WebGL context 被浏览器丢弃 → 已上传纹理失效（封面变黑）、新解码
/// `MakeLazyImageFromTextureSourceWithInfo` 返回 null 抛 `ImageCodecException`
/// （封面变默认图标）。改走 `HttpGet` 后 `memCacheWidth` 生效，封面缩到显示尺寸
/// 解码（数十 KB），大幅降低 GPU 显存压力；且字节可在 context 恢复后重解码。
class NetworkCoverImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  /// 解码目标宽度（物理像素）。封面卡片一般显示 <200 逻辑像素，400 物理像素在高
  /// DPR 屏也足够清晰，同时远小于原图，显著降低 GPU 纹理与解码开销。
  final int decodeWidth;

  const NetworkCoverImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.decodeWidth = 400,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      memCacheWidth: decodeWidth,
      maxWidthDiskCache: decodeWidth,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}
