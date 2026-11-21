import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Extracts a Material seed color from album artwork.
///
/// The image is decoded at a tiny size by the engine, then quantized and
/// scored (the same algorithm Android uses for wallpaper colors) on a
/// background isolate so song changes never drop frames.
class PaletteService {
  static const _cacheSize = 300;
  final _cache = <String, Color?>{}; // insertion ordered, used as an LRU
  final _pending = <String, Future<Color?>>{};

  Color? cached(String path) => _cache[path];

  Future<Color?> seedFor(String path) {
    if (_cache.containsKey(path)) return SynchronousFuture(_cache[path]);
    return _pending.putIfAbsent(path, () async {
      Color? color;
      try {
        color = await _extract(path);
      } catch (_) {
        color = null;
      }
      _cache[path] = color;
      if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
      _pending.remove(path);
      return color;
    });
  }

  static Future<Color?> _extract(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec(targetWidth: 64, targetHeight: 64);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (data == null) return null;
    final argb = await compute(scoreArtwork, data.buffer.asUint8List());
    return argb == null ? null : Color(argb);
  }
}

/// Returns the best seed color for RGBA pixel data, or null for artwork that
/// has no usable color (e.g. black and white covers).
Future<int?> scoreArtwork(Uint8List rgba) async {
  final pixels = <int>[];
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 250) continue;
    pixels.add(0xFF000000 | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2]);
  }
  if (pixels.isEmpty) return null;
  final result = await QuantizerCelebi().quantize(pixels, 128);
  final ranked = Score.score(result.colorToCount, desired: 1, fallbackColorARGB: 0);
  if (ranked.isEmpty || ranked.first == 0) return null;
  return ranked.first;
}
