import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/theme/app_theme.dart';
import 'package:snap/features/settings/settings_model.dart';

void main() {
  group('AppSettings', () {
    test('round-trips through JSON', () {
      const original = AppSettings(
        themeMode: ThemeMode.dark,
        dynamicColors: false,
        accent: AccentChoice.custom,
        customAccent: 0xFF123456,
        animationLevel: AnimationLevel.reduced,
        compactMode: true,
        libraryLayout: LibraryLayout.list,
        defaultSort: SortSpec(SortField.playCount, false),
        startPage: StartPage.favorites,
        volume: 0.4,
        minTrackSeconds: 30,
        homeSections: [
          HomeSectionConfig(HomeSection.mostPlayed, false),
          HomeSectionConfig(HomeSection.quickPicks, true),
        ],
      );
      final decoded = AppSettings.decode(original.encode());
      expect(decoded.themeMode, ThemeMode.dark);
      expect(decoded.dynamicColors, isFalse);
      expect(decoded.accent, AccentChoice.custom);
      expect(decoded.customAccent, 0xFF123456);
      expect(decoded.animationLevel, AnimationLevel.reduced);
      expect(decoded.compactMode, isTrue);
      expect(decoded.libraryLayout, LibraryLayout.list);
      expect(decoded.defaultSort, const SortSpec(SortField.playCount, false));
      expect(decoded.startPage, StartPage.favorites);
      expect(decoded.volume, closeTo(0.4, 1e-9));
      expect(decoded.minTrackSeconds, 30);
      // Saved order is kept and sections missing from the save are appended.
      expect(decoded.homeSections.first.section, HomeSection.mostPlayed);
      expect(decoded.homeSections.first.visible, isFalse);
      expect(decoded.homeSections.length, HomeSection.values.length);
    });

    test('corrupted or partial data falls back to defaults', () {
      expect(AppSettings.decode('not json').themeMode, ThemeMode.system);
      expect(AppSettings.decode(null).accent, const AppSettings().accent);
      final partial = AppSettings.decode('{"themeMode":"banana","volume":7,"compactMode":"yes"}');
      expect(partial.themeMode, ThemeMode.system);
      expect(partial.volume, 1.0);
      expect(partial.compactMode, isFalse);
    });

    test('every accent builds light and dark themes', () {
      for (final accent in AccentChoice.values) {
        final seed = AppSettings(accent: accent).fixedSeed ?? AppTheme.defaultSeed;
        for (final b in Brightness.values) {
          final theme = AppTheme.build(AppTheme.scheme(seed, b), compact: false, animationLevel: AnimationLevel.off);
          expect(theme.colorScheme.brightness, b);
        }
      }
    });

    test('artwork shape is remembered and unknown shapes fall back to rounded', () {
      for (final shape in ArtworkShape.values) {
        final back = AppSettings.decode(AppSettings(artworkShape: shape).encode());
        expect(back.artworkShape, shape);
      }
      expect(AppSettings.decode('{"artworkShape":"hexagon"}').artworkShape, ArtworkShape.rounded);
      expect(const AppSettings().artworkShape, ArtworkShape.rounded);
    });
  });
}
