import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../../data/repositories/settings_repository.dart';
import 'app_theme.dart';

/// Colors for the start-up (splash) background, derived from the current
/// theme so launching the app flows straight into its own colors.
class BootColors {
  const BootColors({required this.light, required this.dark, required this.bucket, required this.mode});

  /// Exact background for light and dark system appearance.
  final Color light;
  final Color dark;

  /// Hue bucket (0-11) selecting the closest precompiled Android splash theme.
  final int bucket;

  /// 0 = follow system, 1 = always light, 2 = always dark.
  final int mode;

  static const hueBuckets = 12;
  static const _storageKey = 'boot_colors';
  static const _channel = MethodChannel('snap/boot');

  /// Soft tonal surface tinted with the primary color.
  static Color backgroundFor(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return Color.alphaBlend(scheme.primary.withValues(alpha: dark ? 0.12 : 0.08), scheme.surfaceContainer);
  }

  static int bucketFor(Color seed) {
    final hue = Hct.fromInt(seed.toARGB32()).hue;
    return ((hue + 15) ~/ 30) % hueBuckets;
  }

  /// Representative seed for a bucket, used to precompile splash themes.
  static Color presetSeed(int bucket) => Color(Hct.from(bucket * 30.0, 48, 50).toInt());

  static int modeFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 0,
        ThemeMode.light => 1,
        ThemeMode.dark => 2,
      };

  static BootColors fromTheme({
    required Color seed,
    required ThemeMode themeMode,
    double contrast = 0,
    bool amoled = false,
  }) {
    return BootColors(
      light: backgroundFor(AppTheme.scheme(seed, Brightness.light, contrast: contrast)),
      // On AMOLED the app opens straight onto black.
      dark: amoled
          ? const Color(0xFF000000)
          : backgroundFor(AppTheme.scheme(seed, Brightness.dark, contrast: contrast)),
      bucket: bucketFor(seed),
      mode: modeFor(themeMode),
    );
  }

  Color forBrightness(Brightness brightness) => switch (mode) {
        1 => light,
        2 => dark,
        _ => brightness == Brightness.dark ? dark : light,
      };

  static Future<BootColors?> load(SettingsRepository repo) async {
    try {
      final raw = await repo.read(_storageKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return BootColors(
        light: Color(json['light'] as int),
        dark: Color(json['dark'] as int),
        bucket: json['bucket'] as int,
        mode: json['mode'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves for the in-app start curtain and hands the colors to Android for
  /// the system splash screen of the next launch.
  Future<void> save(SettingsRepository repo) async {
    try {
      await repo.write(
        _storageKey,
        jsonEncode({'light': light.toARGB32(), 'dark': dark.toARGB32(), 'bucket': bucket, 'mode': mode}),
      );
      await _channel.invokeMethod<void>('update', {
        'light': light.toARGB32(),
        'dark': dark.toARGB32(),
        'bucket': bucket,
        'mode': mode,
      });
    } catch (_) {
      // Not available on this platform; the in-app curtain still adapts.
    }
  }

  bool sameAs(BootColors other) =>
      other.light == light && other.dark == dark && other.bucket == bucket && other.mode == mode;
}
