import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:snap/core/routing/app_nav.dart';
import 'package:snap/features/player/now_playing_screen.dart';
import 'package:snap/features/shell/mini_player.dart';
import 'package:snap/features/player/player_controller.dart';
import 'package:snap/features/settings/settings_controller.dart';
import 'package:snap/features/settings/settings_model.dart';
import 'package:snap/widgets/artwork_shape.dart';
import 'package:snap/widgets/pin_press.dart';
import 'package:snap/widgets/player_buttons.dart';

import 'test_utils.dart';

/// Queue state without a real audio player behind it.
class _IdlePlayer extends PlayerController {
  @override
  PlayerQueueState build() => const PlayerQueueState();
}

Future<void> pumpPlayer(WidgetTester tester, Size size, {AppSettings settings = const AppSettings()}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final track = makeTrack(title: 'Persona 3 Reload - It\'s Going Down Now (with Lyrics)', artist: 'Someone, Lyrics');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      initialSettingsProvider.overrideWithValue(settings),
      playerControllerProvider.overrideWith(_IdlePlayer.new),
      currentTrackProvider.overrideWithValue(track),
      playingProvider.overrideWith((ref) => Stream.value(true)),
      processingStateProvider.overrideWith((ref) => Stream.value(ProcessingState.ready)),
      durationProvider.overrideWith((ref) => Stream.value(const Duration(minutes: 3))),
      positionProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 40))),
    ],
    child: const MaterialApp(home: NowPlayingScreen()),
  ));
  // The progress line and background keep animating while music plays, so
  // step time forward rather than waiting for everything to settle.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final size in const [Size(320, 568), Size(360, 740), Size(412, 915), Size(900, 420), Size(1280, 800)]) {
    testWidgets('player lays out cleanly at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pumpPlayer(tester, size);
      expect(tester.takeException(), isNull);

      // Only the title is shown; the "playing from" header and the artist and
      // album lines are gone.
      expect(find.textContaining('Persona 3 Reload'), findsOneWidget);
      expect(find.text('PLAYING FROM'), findsNothing);
      expect(find.text('Someone, Lyrics'), findsNothing);
      expect(find.text('Album'), findsNothing);

      // The artwork stays on screen.
      final art = tester.getRect(find.byType(ShapedFrame));
      expect((Offset.zero & size).contains(art.center), isTrue);
      expect(art.bottom, lessThanOrEqualTo(size.height));
    });
  }

  testWidgets('shuffle, repeat and like are identical keys', (tester) async {
    await pumpPlayer(tester, const Size(412, 915));
    final keys = find.byType(ToggleKey);
    expect(keys, findsNWidgets(3));
    final rects = [for (var i = 0; i < 3; i++) tester.getRect(keys.at(i))];
    for (final r in rects) {
      expect(r.size, rects.first.size);
      expect(r.top, rects.first.top);
    }
    // Equal gaps between them.
    expect(rects[1].left - rects[0].right, closeTo(rects[2].left - rects[1].right, 0.01));

    Material surface(int i) => tester.widget<Material>(
          find.descendant(of: keys.at(i), matching: find.byType(Material)).first,
        );
    // All off: same colour, same shape.
    expect(surface(1).color, surface(0).color);
    expect(surface(2).color, surface(0).color);
    expect(surface(1).shape, surface(0).shape);
    expect(surface(2).shape, surface(0).shape);
  });

  testWidgets('a toggle key fills in when it turns on and springs back', (tester) async {
    Widget key(bool on) => ProviderScope(
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 100,
                height: 60,
                child: ToggleKey(active: on, tooltip: 'Shuffle', onTap: () {}, child: const Icon(Icons.shuffle)),
              ),
            ),
          ),
        );
    Color fill() => tester
        .widget<Material>(find.descendant(of: find.byType(PinPressButton), matching: find.byType(Material)).first)
        .color!;
    await tester.pumpWidget(key(false));
    final off = fill();
    await tester.pumpWidget(key(true));
    await tester.pumpAndSettle();
    final on = fill();
    expect(on, isNot(off));
    final scheme = Theme.of(tester.element(find.byType(ToggleKey))).colorScheme;
    expect(on, scheme.secondaryContainer);
    await tester.pumpWidget(key(false));
    await tester.pumpAndSettle();
    expect(fill(), off);
    expect(tester.takeException(), isNull);
  });

  for (final shape in ArtworkShape.values) {
    testWidgets('artwork shape ${shape.name} is used on the player', (tester) async {
      await pumpPlayer(tester, const Size(412, 915), settings: AppSettings(artworkShape: shape));
      expect(tester.takeException(), isNull);
      final frame = tester.widget<ShapedFrame>(find.byType(ShapedFrame));
      expect(frame.shape, shape);
      // Never stretched: the frame keeps the shape's own proportions.
      expect(frame.size.width / frame.size.height, closeTo(shape.aspectRatio, 0.001));
    });
  }

  testWidgets('spinning artwork is always round', (tester) async {
    await pumpPlayer(
      tester,
      const Size(412, 915),
      settings: const AppSettings(artworkShape: ArtworkShape.clover, rotateArtwork: true),
    );
    expect(tester.widget<ShapedFrame>(find.byType(ShapedFrame)).shape, ArtworkShape.circle);
  });

  test('every artwork outline fills its frame', () {
    for (final shape in ArtworkShape.values) {
      final size = Size(300, 300 / shape.aspectRatio);
      final bounds = artworkBorder(shape, size).getOuterPath(Offset.zero & size).getBounds();
      // Geometric shapes reach every edge; the scalloped ones touch the
      // circle inside the frame with their lobes, so they come close.
      final organic = shape == ArtworkShape.cookie || shape == ArtworkShape.clover;
      final tolerance = organic ? size.height * 0.08 : 2.0;
      expect(bounds.width, closeTo(size.width, tolerance), reason: shape.name);
      expect(bounds.height, closeTo(size.height, tolerance), reason: shape.name);
      expect((Offset.zero & size).inflate(1).contains(bounds.center), isTrue, reason: shape.name);
    }
  });

  testWidgets('the music pill hides and shows in place, with no motion of its own', (tester) async {
    final track = makeTrack(title: 'Pill song');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(const AppSettings()),
        playerControllerProvider.overrideWith(_IdlePlayer.new),
        currentTrackProvider.overrideWithValue(track),
        playingProvider.overrideWith((ref) => Stream.value(false)),
        durationProvider.overrideWith((ref) => Stream.value(const Duration(minutes: 3))),
        positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
      ],
      child: const MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer()))),
    ));
    await tester.pumpAndSettle();
    // At rest the pill draws without any opacity layer at all.
    double opacity() {
      final layers = find.ancestor(of: find.text('Pill song'), matching: find.byType(Opacity));
      return layers.evaluate().isEmpty ? 1 : tester.widget<Opacity>(layers.last).opacity;
    }

    final rest = tester.getRect(find.text('Pill song'));
    expect(opacity(), 1);

    // The player draws its own copy of the pill, so the real one simply
    // hides in the same frame, without moving.
    AppNav.playerOpen.value = true;
    await tester.pump();
    expect(opacity(), 0);
    expect(tester.getRect(find.text('Pill song')).top, closeTo(rest.top, 0.5));

    // And shows again in the same frame the copy goes, exactly in its slot.
    AppNav.playerOpen.value = false;
    await tester.pump();
    expect(opacity(), 1);
    expect(tester.getRect(find.text('Pill song')).top, closeTo(rest.top, 0.5));
    expect(tester.takeException(), isNull);
  });
}
