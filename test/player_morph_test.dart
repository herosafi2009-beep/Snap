import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/routing/app_nav.dart';
import 'package:snap/features/player/player_controller.dart';
import 'package:snap/features/player/player_route.dart';
import 'package:snap/features/settings/settings_controller.dart';
import 'package:snap/features/settings/settings_model.dart';

import 'test_utils.dart';

class _IdlePlayer extends PlayerController {
  @override
  PlayerQueueState build() => const PlayerQueueState();
}

const _sheet = ValueKey('sheet');
const _screen = Size(400, 800);
const _pill = Rect.fromLTWH(16, 640, 368, 74);

/// A page with a music pill slot at the bottom, and the player route on top
/// of it while [open]. Pages are managed like go_router does.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool open = false;

  void setOpen(bool value) => setState(() => open = value);

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: [
        MaterialPage(
          child: Stack(
            children: [
              const ColoredBox(color: Colors.white, child: SizedBox.expand()),
              Positioned.fromRect(rect: _pill, child: SizedBox(key: AppNav.pillKey)),
            ],
          ),
        ),
        if (open)
          const PlayerPage(
            key: ValueKey('player'),
            child: ColoredBox(key: _sheet, color: Colors.red, child: SizedBox.expand()),
          ),
      ],
      onDidRemovePage: (page) {
        if (page is PlayerPage) setState(() => open = false);
      },
    );
  }
}

Future<void Function(bool)> pumpHost(WidgetTester tester, {AppSettings settings = const AppSettings()}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      initialSettingsProvider.overrideWithValue(settings),
      playerControllerProvider.overrideWith(_IdlePlayer.new),
      currentTrackProvider.overrideWithValue(makeTrack(title: 'Morph song')),
      playingProvider.overrideWith((ref) => Stream.value(false)),
      durationProvider.overrideWith((ref) => Stream.value(const Duration(minutes: 3))),
      positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
    ],
    child: const MaterialApp(home: _Host()),
  ));
  final state = tester.state<_HostState>(find.byType(_Host));
  return state.setOpen;
}

/// The card the player is drawn in.
Rect card(WidgetTester tester) =>
    tester.getRect(find.ancestor(of: find.byKey(_sheet), matching: find.byType(ClipRRect)).first);

PlayerRoute route(WidgetTester tester) => PlayerRoute.of(tester.element(find.byKey(_sheet)))!;

/// Pumps 120Hz frames until nothing moves, recording the card each frame.
Future<List<Rect>> run(WidgetTester tester, {int frames = 150}) async {
  final seen = <Rect>[];
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(microseconds: 8333));
    if (find.byKey(_sheet).evaluate().isEmpty) break;
    seen.add(card(tester));
  }
  return seen;
}

/// Largest jump of the top edge between two frames.
double biggestStep(List<Rect> frames) {
  var most = 0.0;
  for (var i = 1; i < frames.length; i++) {
    most = most > (frames[i].top - frames[i - 1].top).abs() ? most : (frames[i].top - frames[i - 1].top).abs();
  }
  return most;
}

void main() {
  tearDown(() {
    AppNav.playerOpen.value = false;
    AppNav.playerCovers.value = false;
    playerArtInFlight.value = false;
  });

  testWidgets('opening grows out of the pill and settles with a small bounce', (tester) async {
    final setOpen = await pumpHost(tester);
    setOpen(true);
    await tester.pump();
    // The first frame is exactly the pill.
    expect(card(tester).top, closeTo(_pill.top, 1));
    expect(card(tester).height, closeTo(_pill.height, 1));
    await tester.pump();
    expect(AppNav.playerOpen.value, isTrue, reason: 'the real pill hides under its copy');
    expect(AppNav.playerCovers.value, isFalse);

    final frames = await run(tester);
    expect(frames.map((r) => r.top).reduce((a, b) => a < b ? a : b), lessThan(-1),
        reason: 'rises a touch past the top, a subtle bounce');
    expect(frames.map((r) => r.top).reduce((a, b) => a < b ? a : b), greaterThan(-40), reason: 'only a touch');
    expect(biggestStep(frames), lessThan(80), reason: 'no jumps at 120Hz');
    expect(card(tester), Offset.zero & _screen);
    expect(AppNav.playerCovers.value, isTrue, reason: 'the app behind stops drawing once covered');
    expect(playerArtInFlight.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing shrinks into the pill, lands with a small settle, then hands over', (tester) async {
    final setOpen = await pumpHost(tester);
    setOpen(true);
    await tester.pump();
    await run(tester);

    route(tester).close();
    await tester.pump();
    expect(AppNav.playerCovers.value, isFalse, reason: 'the app shows again before anything moves');
    final frames = await run(tester);
    expect(find.byKey(_sheet), findsNothing, reason: 'the route is gone at the end');
    expect(AppNav.playerOpen.value, isFalse, reason: 'and the real pill shows');
    expect(frames.last.top, closeTo(_pill.top, 1), reason: 'the last frame is exactly the pill');
    expect(frames.last.height, closeTo(_pill.height, 1));
    expect(frames.map((r) => r.top).reduce((a, b) => a > b ? a : b), greaterThan(_pill.top + 1),
        reason: 'dips a touch below the slot, a subtle bounce');
    expect(frames.map((r) => r.top).reduce((a, b) => a > b ? a : b), lessThan(_pill.top + 30));
    expect(biggestStep(frames), lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the back button shrinks into the pill too, with no slide', (tester) async {
    final setOpen = await pumpHost(tester);
    setOpen(true);
    await tester.pump();
    await run(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    navigator.maybePop();
    await tester.pump();
    final frames = await run(tester);
    expect(find.byKey(_sheet), findsNothing);
    expect(frames.last.top, closeTo(_pill.top, 1));
    for (final r in frames) {
      expect(r.width, lessThanOrEqualTo(_screen.width + 0.5), reason: 'it shrinks, never slides off');
    }
    expect(AppNav.playerOpen.value, isFalse);
  });

  testWidgets('the top edge follows the finger, and a short drag springs back', (tester) async {
    final setOpen = await pumpHost(tester);
    setOpen(true);
    await tester.pump();
    await run(tester);

    final r = route(tester);
    r.dragStart();
    await tester.pump();
    r.dragUpdate(60);
    r.dragUpdate(40);
    await tester.pump();
    expect(card(tester).top, closeTo(100, 0.01));
    expect(AppNav.playerCovers.value, isFalse);
    r.dragEnd(0);
    final frames = await run(tester);
    // A new spring's first frame is its start; it moves from the next one.
    expect(frames.first.top, closeTo(100, 0.01), reason: 'picks up from where the finger was');
    expect(frames[1].top, lessThan(100));
    expect(biggestStep([const Rect.fromLTWH(0, 100, 1, 1), ...frames]), lessThan(60));
    expect(card(tester), Offset.zero & _screen);
    expect(find.byKey(_sheet), findsOneWidget);
  });

  testWidgets('a flick down sends it into the pill at the flick speed', (tester) async {
    final setOpen = await pumpHost(tester);
    setOpen(true);
    await tester.pump();
    await run(tester);
    final r = route(tester);
    r.dragStart();
    r.dragUpdate(40);
    await tester.pump();
    r.dragEnd(2500);
    final frames = await run(tester);
    expect(find.byKey(_sheet), findsNothing);
    expect(frames[1].top - 40, greaterThan(10), reason: 'keeps the flick moving');
    expect(frames.last.top, closeTo(_pill.top, 1));
  });

  testWidgets('it can be caught mid-flight and sent back, with no jump', (tester) async {
    final setOpen = await pumpHost(tester);
    setOpen(true);
    await tester.pump();
    await run(tester);
    final r = route(tester);
    r.close();
    final closing = await run(tester, frames: 12);
    final caughtAt = closing.last.top;
    expect(caughtAt, greaterThan(20));
    // A tap on it while it shrinks brings it back.
    r.tapped(closeOnTap: true);
    final reopening = await run(tester);
    expect((reopening.first.top - caughtAt).abs(), lessThan(40), reason: 'continues from where it was');
    expect(card(tester), Offset.zero & _screen);
    expect(find.byKey(_sheet), findsOneWidget);
    expect(AppNav.playerOpen.value, isTrue);

    // Grabbing it while it opens works too.
    r.close();
    await run(tester, frames: 10);
    r.dragStart();
    final held = card(tester).top;
    r.dragUpdate(10);
    await tester.pump();
    expect(card(tester).top, closeTo(held + 10, 0.5));
    r.dragEnd(-1500);
    await run(tester);
    expect(card(tester), Offset.zero & _screen);
  });

  testWidgets('with animations off it opens and closes at once', (tester) async {
    final setOpen = await pumpHost(tester, settings: const AppSettings(animationLevel: AnimationLevel.off));
    setOpen(true);
    await tester.pump();
    await tester.pump();
    expect(card(tester), Offset.zero & _screen);
    route(tester).close();
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    expect(AppNav.playerOpen.value, isFalse);
  });
}
