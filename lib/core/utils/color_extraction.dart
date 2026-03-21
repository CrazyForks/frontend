import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

/// 封面颜色调色板
class CoverPalette {
  /// 主色调
  final Color dominantColor;

  /// 鲜艳色（适合强调元素）
  final Color? vibrantColor;

  /// 亮鲜艳色
  final Color? lightVibrantColor;

  /// 暗柔和色（适合背景渐变）
  final Color? darkMutedColor;

  /// 柔和色
  final Color? mutedColor;

  const CoverPalette({
    required this.dominantColor,
    this.vibrantColor,
    this.lightVibrantColor,
    this.darkMutedColor,
    this.mutedColor,
  });
}

/// LRU 缓存（最多 20 条）
class _LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  _LruCache({this.maxSize = 20});

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value; // 移到末尾（最近使用）
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }

  bool containsKey(K key) => _map.containsKey(key);
}

/// 全局颜色缓存
final _colorCache = _LruCache<String, CoverPalette>(maxSize: 20);

/// 从封面 URL 提取颜色的 Provider
///
/// 使用方式：
/// ```dart
/// final palette = ref.watch(coverColorsProvider(coverUrl));
/// palette.when(
///   data: (colors) => ... ,
///   loading: () => ... ,
///   error: (e, s) => ... ,
/// );
/// ```
final coverColorsProvider = FutureProvider.family<CoverPalette?, String?>((
  ref,
  coverUrl,
) async {
  if (coverUrl == null || coverUrl.isEmpty) return null;

  // 检查缓存
  final cached = _colorCache.get(coverUrl);
  if (cached != null) return cached;

  try {
    final paletteGenerator = await PaletteGenerator.fromImageProvider(
      NetworkImage(coverUrl),
      size: const Size(100, 100), // 缩小尺寸加速提取
      maximumColorCount: 16,
    );

    final palette = CoverPalette(
      dominantColor: paletteGenerator.dominantColor?.color ?? Colors.grey,
      vibrantColor: paletteGenerator.vibrantColor?.color,
      lightVibrantColor: paletteGenerator.lightVibrantColor?.color,
      darkMutedColor: paletteGenerator.darkMutedColor?.color,
      mutedColor: paletteGenerator.mutedColor?.color,
    );

    // 写入缓存
    _colorCache.put(coverUrl, palette);
    return palette;
  } catch (e) {
    debugPrint('[ColorExtraction] Failed to extract colors from $coverUrl: $e');
    return null;
  }
});
