import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/theme/app_theme.dart';
import 'package:snap/features/settings/settings_model.dart';

/// Building Material schemes and themes is the expensive part of a song
/// change: it runs on the UI thread, and at 120Hz a frame is 8ms in total.
/// These tests pin the caching that keeps it off the critical path.
void main() {
  /// Average microseconds per call, over enough runs that one-off costs
  /// (first compile of the closure, a stray scheduler tick) do not decide it.
  double perCall(void Function() body, {int runs = 200}) {
    body();
    final sw = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      body();
    }
    return sw.elapsedMicroseconds / runs;
  }

  test('a scheme is built once per seed and reused after that', () {
    const seed = Color(0xFF2E7D32);
    final first = AppTheme.scheme(seed, Brightness.dark);
    var nextSeed = 0xFF100000;
    final cold = perCall(() => AppTheme.scheme(Color(nextSeed++), Brightness.dark), runs: 20);
    final warm = perCall(() => AppTheme.scheme(seed, Brightness.dark));

    expect(identical(AppTheme.scheme(seed, Brightness.dark), first), isTrue);
    expect(warm * 20, lessThan(cold),
        reason: 'a cached scheme must be far cheaper than rebuilding the tonal palettes');
  });

  test('variants and brightnesses are cached separately', () {
    const seed = Color(0xFF00695C);
    final light = AppTheme.scheme(seed, Brightness.light);
    final dark = AppTheme.scheme(seed, Brightness.dark);
    final vibrant = AppTheme.scheme(seed, Brightness.dark, variant: DynamicSchemeVariant.vibrant);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(vibrant, isNot(dark));
    expect(identical(AppTheme.scheme(seed, Brightness.dark, variant: DynamicSchemeVariant.vibrant), vibrant), isTrue);
  });

  test('warming a seed makes the schemes a song needs free', () {
    const seed = Color(0xFFB71C1C);
    AppTheme.warm(seed, Brightness.dark);
    final elapsed = perCall(() {
      AppTheme.scheme(seed, Brightness.dark);
      AppTheme.scheme(seed, Brightness.dark, variant: DynamicSchemeVariant.vibrant);
    });
    expect(elapsed, lessThan(50), reason: 'pre-warmed colors must be a lookup, not a rebuild');
  });

  test('themes are reused for a scheme that has been seen', () {
    final scheme = AppTheme.scheme(const Color(0xFF4527A0), Brightness.dark);
    final theme = AppTheme.build(scheme, compact: false, animationLevel: AnimationLevel.full);
    final warm = perCall(() => AppTheme.build(scheme, compact: false, animationLevel: AnimationLevel.full));
    expect(identical(theme, AppTheme.build(scheme, compact: false, animationLevel: AnimationLevel.full)), isTrue);
    // Different settings are still their own theme.
    expect(
      identical(theme, AppTheme.build(scheme, compact: true, animationLevel: AnimationLevel.full)),
      isFalse,
    );

    // Measured last: building unseen themes evicts older entries.
    var nextSeed = 0xFF200000;
    final cold = perCall(
      () => AppTheme.build(AppTheme.scheme(Color(nextSeed++), Brightness.dark),
          compact: false, animationLevel: AnimationLevel.full),
      runs: 20,
    );
    expect(warm * 20, lessThan(cold), reason: 'a cached theme must not be reassembled');
  });
}
