import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/theme/app_theme.dart';
import 'package:snap/features/player/player_controller.dart';
import 'package:snap/features/settings/settings_model.dart';
import 'package:snap/widgets/volume_slider.dart';

Widget host(double volume) => ProviderScope(
      overrides: [volumeProvider.overrideWith((ref) => Stream.value(volume))],
      child: MaterialApp(
        theme: AppTheme.build(
          AppTheme.scheme(AppTheme.defaultSeed, Brightness.dark),
          compact: false,
          animationLevel: AnimationLevel.off,
        ),
        home: const Scaffold(
          body: Center(child: SizedBox(width: 300, child: VolumeSlider())),
        ),
      ),
    );

void main() {
  testWidgets('shows the current volume and reports it to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(0.4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSemantics(find.byType(VolumeSlider)),
      matchesSemantics(
        isSlider: true,
        label: 'Volume',
        value: '40%',
        increasedValue: '45%',
        decreasedValue: '35%',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        // Tapping and swiping the pill are how it is used by hand.
        hasTapAction: true,
        hasScrollLeftAction: true,
        hasScrollRightAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('dragging along the pill does not throw and keeps its size', (tester) async {
    await tester.pumpWidget(host(0.2));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(VolumeSlider));
    expect(box.width, 300);

    final gesture = await tester.startGesture(box.centerLeft + const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The control must not grow the sheet it sits in while it is used.
    expect(tester.getRect(find.byType(VolumeSlider)), box);
  });

  testWidgets('a silent player still paints', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
