import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/features/player/player_controller.dart';
import 'package:snap/features/player/widgets/seek_bar.dart';
import 'package:snap/widgets/expressive_shapes.dart';
import 'package:snap/widgets/pin_press.dart';

Widget host(Widget child) => ProviderScope(child: MaterialApp(home: Scaffold(body: Center(child: child))));

void main() {
  test('every shape morphs into every other shape', () {
    const rect = Rect.fromLTWH(0, 0, 100, 100);
    for (final a in ExpressiveShape.values) {
      for (final b in ExpressiveShape.values) {
        for (final t in [0.0, 0.5, 1.0, 1.15]) {
          final bounds = morphPath(rect, a, b, t, rotation: 0.3).getBounds();
          expect(bounds.width, inInclusiveRange(20, 110), reason: '$a -> $b at $t');
          expect(rect.inflate(6).contains(bounds.center), isTrue);
        }
      }
    }
  });

  testWidgets('pin press squares the key off and eases it back', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(PinPressButton(
      width: 80,
      height: 80,
      tooltip: 'Play',
      onTap: () => taps++,
      color: Colors.blue,
      pressedColor: Colors.pink,
      child: const Icon(Icons.play_arrow),
    )));

    double radius() {
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(PinPressButton), matching: find.byType(Material)).first,
      );
      return ((material.shape! as RoundedRectangleBorder).borderRadius.resolve(TextDirection.ltr)).topLeft.x;
    }

    expect(radius(), closeTo(40, 0.01), reason: 'rests as a circle');

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PinPressButton)));
    await tester.pump(); // the press animation starts on the next frame
    await tester.pump(const Duration(milliseconds: 90));
    expect(radius(), closeTo(24, 1), reason: 'squares off to about 30% while held');

    // Held: it stays squared instead of drifting back.
    await tester.pump(const Duration(milliseconds: 400));
    expect(radius(), closeTo(24, 1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(radius(), closeTo(40, 0.01), reason: 'returns to a circle');
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a quick tap still shows the pressed state', (tester) async {
    await tester.pumpWidget(host(PinPressButton(
      width: 64,
      height: 64,
      tooltip: 'Next',
      onTap: () {},
      color: Colors.blue,
      pressedColor: Colors.pink,
      child: const Icon(Icons.skip_next),
    )));
    double radius() {
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(PinPressButton), matching: find.byType(Material)).first,
      );
      return ((material.shape! as RoundedRectangleBorder).borderRadius.resolve(TextDirection.ltr)).topLeft.x;
    }

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PinPressButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await gesture.up();
    // The press keeps running to the end before it eases back.
    await tester.pump(const Duration(milliseconds: 40));
    expect(radius(), lessThan(22), reason: 'reaches the squared look before releasing');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('seek track follows a drag and seeks where it is released', (tester) async {
    double? sought;
    final drag = ValueNotifier<double?>(null);
    addTearDown(drag.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        positionProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 30))),
        playingProvider.overrideWith((ref) => Stream.value(false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 32,
              child: SeekTrack(
                duration: const Duration(minutes: 2),
                color: Colors.purple,
                enabled: true,
                drag: drag,
                describe: (f) => '${(f * 100).round()}%',
                onSeek: (f) => sought = f,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final box = tester.getRect(find.byType(SeekTrack));
    final gesture = await tester.startGesture(box.centerLeft + const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(drag.value, closeTo(0.5, 0.05), reason: 'the line follows the finger');
    await gesture.up();
    await tester.pump();
    expect(sought, closeTo(0.5, 0.05));
    expect(drag.value, isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shape indicator grows in and out', (tester) async {
    Widget indicator(bool active) => host(ShapeIndicator(
          active: active,
          shape: ExpressiveShape.flower,
          color: Colors.pink,
          child: const Icon(Icons.favorite),
        ));
    await tester.pumpWidget(indicator(false));
    await tester.pumpWidget(indicator(true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(indicator(false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
