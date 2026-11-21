import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/routing/app_nav.dart';
import 'package:snap/core/theme/app_theme.dart';
import 'package:snap/features/settings/appearance_widgets.dart';
import 'package:snap/features/settings/settings_model.dart';
import 'package:snap/features/shell/floating_nav_bar.dart';
import 'package:snap/widgets/player_buttons.dart';

Widget host(Widget child, {AppSettings settings = const AppSettings()}) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  group('appearance settings', () {
    test('AMOLED, contrast, font and last scheme survive a restart', () {
      const s = AppSettings(
        amoled: true,
        contrast: ContrastChoice.high,
        font: AppFont.rounded,
        accent: AccentChoice.dynamic,
        lastAccent: AccentChoice.green,
      );
      final back = AppSettings.decode(s.encode());
      expect(back.amoled, isTrue);
      expect(back.contrast, ContrastChoice.high);
      expect(back.font, AppFont.rounded);
      expect(back.materialYou, isTrue);
      expect(back.lastAccent, AccentChoice.green);

      final junk = AppSettings.decode('{"amoled":"yes","contrast":"ultra","font":"comic"}');
      expect(junk.amoled, isFalse);
      expect(junk.contrast, ContrastChoice.normal);
      expect(junk.font, AppFont.system);
    });

    test('AMOLED makes dark surfaces black and leaves light themes alone', () {
      const seed = Color(0xFF6750A4);
      final dark = AppTheme.scheme(seed, Brightness.dark, amoled: true);
      expect(dark.surface, const Color(0xFF000000));
      expect(dark.surfaceContainerLowest, const Color(0xFF000000));
      // Raised surfaces stay distinguishable and darker than normal.
      final normal = AppTheme.scheme(seed, Brightness.dark);
      expect(dark.surfaceContainerHigh.computeLuminance(), lessThan(normal.surfaceContainerHigh.computeLuminance()));
      expect(dark.surfaceContainerHigh, isNot(dark.surface));
      expect(dark.onSurface, normal.onSurface);

      final light = AppTheme.scheme(seed, Brightness.light, amoled: true);
      expect(light.surface, AppTheme.scheme(seed, Brightness.light).surface);
    });

    test('higher contrast pulls text further from the background', () {
      const seed = Color(0xFF3D8BE8);
      double ratio(ColorScheme s) {
        final a = s.onSurfaceVariant.computeLuminance() + 0.05;
        final b = s.surface.computeLuminance() + 0.05;
        return a > b ? a / b : b / a;
      }

      for (final b in Brightness.values) {
        final normal = ratio(AppTheme.scheme(seed, b, contrast: ContrastChoice.normal.level));
        final medium = ratio(AppTheme.scheme(seed, b, contrast: ContrastChoice.medium.level));
        final high = ratio(AppTheme.scheme(seed, b, contrast: ContrastChoice.high.level));
        expect(medium, greaterThan(normal), reason: '$b');
        expect(high, greaterThan(medium), reason: '$b');
      }
    });

    test('the chosen font reaches every text style and component', () {
      final scheme = AppTheme.scheme(AppTheme.defaultSeed, Brightness.light);
      for (final font in AppFont.values) {
        final theme = AppTheme.build(scheme, compact: false, animationLevel: AnimationLevel.full, font: font);
        final family = font.family;
        final t = theme.textTheme;
        for (final style in [t.displayLarge, t.headlineLarge, t.titleLarge, t.titleSmall, t.bodyMedium, t.labelSmall]) {
          if (family == null) {
            expect(style?.fontFamily, isNot(anyOf('Lexend', 'Nunito', 'Outfit', 'RobotoCondensed', 'Lora')));
          } else {
            expect(style?.fontFamily, family, reason: '$font');
          }
        }
        if (family != null) {
          expect(theme.primaryTextTheme.labelLarge?.fontFamily, family);
          expect(theme.appBarTheme.titleTextStyle?.fontFamily, family);
        }
      }
    });
  });

  group('play / pause label', () {
    testWidgets('old and new content are never visible together, even with rapid taps', (tester) async {
      var playing = false;
      late StateSetter update;
      await tester.pumpWidget(host(StatefulBuilder(builder: (context, setState) {
        update = setState;
        return PlayStateSwitcher(
          child: Row(
            key: ValueKey(playing),
            mainAxisSize: MainAxisSize.min,
            children: [Icon(playing ? Icons.pause : Icons.play_arrow), Text(playing ? 'Pause' : 'Play')],
          ),
        );
      })));

      int visible() => tester
          .widgetList<FadeTransition>(find.descendant(of: find.byType(PlayStateSwitcher), matching: find.byType(FadeTransition)))
          .where((f) => f.opacity.value > 0.01)
          .length;

      // Tap patterns: one tap, then a burst of quick taps.
      for (final gap in [600, 40, 40, 60, 30, 600]) {
        update(() => playing = !playing);
        for (var t = 0; t < gap; t += 8) {
          await tester.pump(const Duration(milliseconds: 8));
          expect(visible(), lessThanOrEqualTo(1), reason: 'two labels showed at once ${t}ms after a tap');
        }
      }
      await tester.pumpAndSettle();
      expect(visible(), 1);
      expect(find.text(playing ? 'Pause' : 'Play'), findsOneWidget);
      expect(find.text(playing ? 'Play' : 'Pause'), findsNothing);
    });
  });

  group('player sheet', () {
    test('the open state is shared with the pill', () {
      expect(AppNav.playerOpen.value, isFalse);
    });
  });

  group('floating navigation bar', () {
    const destinations = [
      NavDestinationSpec('Home', Icons.home_outlined, Icons.home_rounded),
      NavDestinationSpec('Library', Icons.library_music_outlined, Icons.library_music_rounded),
      NavDestinationSpec('Search', Icons.search_rounded, Icons.manage_search_rounded),
      NavDestinationSpec('Settings', Icons.settings_outlined, Icons.settings_rounded),
    ];

    testWidgets('every destination is reachable and the selected one is marked', (tester) async {
      var selected = 0;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: FloatingNavBar(
                destinations: destinations,
                selectedIndex: selected,
                onSelected: (i) => setState(() => selected = i),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < destinations.length; i++) {
        await tester.tap(find.text(destinations[i].label));
        await tester.pumpAndSettle();
        expect(selected, i);
        final data = tester.getSemantics(find.bySemanticsLabel(destinations[i].label));
        expect(data.flagsCollection.isSelected, Tristate.isTrue);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('floats clear of the gesture bar with rounded ends', (tester) async {
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingNavBar(destinations: destinations, selectedIndex: 1, onSelected: (_) {}),
          ),
        ),
      ));
      final bar = tester.getRect(find.descendant(of: find.byType(FloatingNavBar), matching: find.byType(Material)).first);
      expect(bar.left, 16);
      expect(bar.right, 412 - 16);
      expect(900 - bar.bottom, 24 + 12, reason: 'sits above the system gesture area');
      final material = tester.widget<Material>(find.descendant(of: find.byType(FloatingNavBar), matching: find.byType(Material)).first);
      expect(material.shape, isA<StadiumBorder>());
    });
  });

  testWidgets('connected button group selects with a full pill', (tester) async {
    var value = ContrastChoice.normal;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) => SizedBox(
        width: 360,
        child: ConnectedButtonGroup<ContrastChoice>(
          options: [for (final c in ContrastChoice.values) ConnectedOption(c, c.label)],
          selected: value,
          onSelected: (v) => setState(() => value = v),
        ),
      ),
    )));
    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(value, ContrastChoice.high);
    expect(tester.takeException(), isNull);
  });
}
