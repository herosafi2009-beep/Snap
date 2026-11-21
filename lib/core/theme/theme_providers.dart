import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../features/settings/settings_model.dart';
import 'app_theme.dart';
import 'palette_service.dart';

/// Wallpaper color on Android 12+, read at startup.
final systemSeedProvider = Provider<Color?>((ref) => null);

final paletteServiceProvider = Provider((ref) => PaletteService());

/// Seed color extracted from the artwork of the song that is playing.
final artworkSeedProvider = FutureProvider<Color?>((ref) async {
  final artPath = ref.watch(currentTrackProvider.select((t) => t?.artPath));
  if (artPath == null) return null;
  return ref.read(paletteServiceProvider).seedFor(artPath);
});

/// Seed used when album colors are off or unavailable.
final baseSeedProvider = Provider<Color>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.fixedSeed ?? ref.watch(systemSeedProvider) ?? AppTheme.defaultSeed;
});

final themeSeedProvider = Provider<Color>((ref) {
  final base = ref.watch(baseSeedProvider);
  final dynamicColors = ref.watch(settingsProvider.select((s) => s.albumColors));
  if (!dynamicColors) return base;
  final hasTrack = ref.watch(currentTrackProvider.select((t) => t != null));
  if (!hasTrack) return base;
  return ref.watch(artworkSeedProvider).value ?? base;
});

/// The seed the app's theme uses. Follows [themeSeedProvider], except that
/// an album colour change (same settings, new song) waits until the song
/// change animations have played, so the one-frame recolour never lands in
/// the middle of them. Changes made in settings apply at once.
final appSeedProvider = NotifierProvider<AppSeed, Color>(AppSeed.new);

class AppSeed extends Notifier<Color> {
  static const settle = Duration(milliseconds: 650);
  Timer? _timer;
  Color? _base;

  @override
  Color build() {
    _base = ref.read(baseSeedProvider);
    ref.onDispose(() => _timer?.cancel());
    ref.listen(themeSeedProvider, (_, next) {
      _timer?.cancel();
      final base = ref.read(baseSeedProvider);
      if (base != _base) {
        _base = base;
        state = next;
        return;
      }
      _timer = Timer(settle, () => state = next);
    });
    return ref.read(themeSeedProvider);
  }
}

final lightThemeProvider = Provider<ThemeData>((ref) => _theme(ref, Brightness.light));
final darkThemeProvider = Provider<ThemeData>((ref) => _theme(ref, Brightness.dark));

/// Contrast level and AMOLED black, which shape every scheme in the app.
final schemeOptionsProvider = Provider<({double contrast, bool amoled})>((ref) {
  final contrast = ref.watch(settingsProvider.select((s) => s.contrast));
  final amoled = ref.watch(settingsProvider.select((s) => s.amoled));
  return (contrast: contrast.level, amoled: amoled);
});

ThemeData _theme(Ref ref, Brightness brightness) {
  final seed = ref.watch(appSeedProvider);
  final options = ref.watch(schemeOptionsProvider);
  final compact = ref.watch(settingsProvider.select((s) => s.compactMode));
  final animation = ref.watch(settingsProvider.select((s) => s.animationLevel));
  final font = ref.watch(settingsProvider.select((s) => s.font));
  return AppTheme.build(
    AppTheme.scheme(seed, brightness, contrast: options.contrast, amoled: options.amoled),
    compact: compact,
    animationLevel: animation,
    font: font,
  );
}

/// A more saturated scheme for the immersive Now Playing screen.
final nowPlayingSchemeProvider = Provider.family<ColorScheme, Brightness>((ref, brightness) {
  final seed = ref.watch(themeSeedProvider);
  final options = ref.watch(schemeOptionsProvider);
  return AppTheme.scheme(
    seed,
    brightness,
    variant: DynamicSchemeVariant.vibrant,
    contrast: options.contrast,
    amoled: options.amoled,
  );
});
