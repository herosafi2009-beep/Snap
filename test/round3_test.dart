import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/data/models/track.dart';
import 'package:snap/features/lyrics/lyrics_online.dart';
import 'package:snap/features/settings/appearance_widgets.dart';
import 'package:snap/features/settings/settings_model.dart';
import 'package:snap/features/shell/mini_player.dart';
import 'package:snap/widgets/artwork_shape.dart';
import 'package:snap/widgets/outline_morph.dart';

Track track({
  String title = 'Doomsday',
  String artist = 'MF DOOM',
  String album = 'Operation: Doomsday',
  int durationMs = 296000,
}) =>
    Track(
      id: 7,
      path: '/music/doomsday.mp3',
      folder: '/music',
      title: title,
      artist: artist,
      album: album,
      albumArtist: '',
      genre: '',
      durationMs: durationMs,
      fileSize: 1,
      fileModified: DateTime(2026),
      dateAdded: DateTime(2026),
      isFavorite: false,
      playCount: 0,
      excluded: false,
    );

Map<String, dynamic> record(String title, String artist, {String album = '', double? duration, bool synced = true}) => {
      'trackName': title,
      'artistName': artist,
      'albumName': album,
      'duration': duration,
      'syncedLyrics': synced ? '[00:01.00] line one\n[00:03.00] line two' : null,
      'plainLyrics': 'line one\nline two',
      'instrumental': false,
    };

void main() {
  group('lyrics matching', () {
    test('file-name titles and feat. credits are cleaned before searching', () {
      final q = LyricsQuery.of(track(title: 'MF DOOM - Doomsday (feat. Pebbles The Invisible Girl)'));
      expect(q.title, 'Doomsday');
      expect(q.artist, 'MF DOOM');
      expect(q.usable, isTrue);
      expect(LyricsQuery.of(track(title: 'Dance With Me')).title, 'Dance With Me');
      expect(LyricsQuery.of(track(title: 'Yesterday - Remastered 2009')).title, 'Yesterday');
    });

    test('accepts the same song, preferring synced lyrics and the closest length', () {
      final q = LyricsQuery.of(track());
      final best = LyricsMatcher.best(q, [
        record('Doomsday', 'MF DOOM', duration: 299, synced: false),
        record('Doomsday', 'MF DOOM', album: 'Operation: Doomsday', duration: 296),
      ]);
      expect(best?['albumName'], 'Operation: Doomsday');
    });

    test('rejects other versions, other artists and other lengths', () {
      final q = LyricsQuery.of(track());
      expect(LyricsMatcher.score(q, record('Doomsday (Remix)', 'MF DOOM', duration: 296)), isNull);
      expect(LyricsMatcher.score(q, record('Doomsday - Live', 'MF DOOM', duration: 296)), isNull);
      expect(LyricsMatcher.score(q, record('Doomsday', 'Someone Else', duration: 296)), isNull);
      expect(LyricsMatcher.score(q, record('Doomsday', 'MF DOOM', duration: 240)), isNull);
      expect(LyricsMatcher.score(q, record('Doomsday Part 2', 'MF DOOM', duration: 296)), isNull);
      // A live recording does match its own live record.
      final live = LyricsQuery.of(track(title: 'Doomsday (Live)'));
      expect(LyricsMatcher.score(live, record('Doomsday (Live)', 'MF DOOM', duration: 296)), isNotNull);
      expect(LyricsMatcher.score(live, record('Doomsday', 'MF DOOM', duration: 296)), isNull);
    });

    test('artist credits match any listed artist', () {
      final q = LyricsQuery.of(track(artist: 'Pebbles'));
      expect(LyricsMatcher.score(q, record('Doomsday', 'MF DOOM & Pebbles', duration: 296)), isNotNull);
      expect(LyricsQuery.of(track(artist: '')).usable, isFalse);
    });
  });

  group('settings', () {
    test('new player settings survive a restart', () {
      const s = AppSettings(tapToCollapse: false, onlineLyrics: false);
      final back = AppSettings.decode(s.encode());
      expect(back.tapToCollapse, isFalse);
      expect(back.onlineLyrics, isFalse);
      expect(const AppSettings().tapToCollapse, isTrue);
    });

    test('Material You and album colors are never both on', () {
      const both = AppSettings(accent: AccentChoice.dynamic, dynamicColors: true);
      expect(both.albumColors, isFalse, reason: 'Material You wins');
      final back = AppSettings.decode(both.encode());
      expect(back.materialYou, isTrue);
      expect(back.dynamicColors, isFalse, reason: 'older saved settings are cleaned up');
      const album = AppSettings(accent: AccentChoice.green, dynamicColors: true);
      expect(AppSettings.decode(album.encode()).albumColors, isTrue);
    });
  });

  group('player to pill morph', () {
    test('artwork outline starts as the chosen shape and ends as the cover', () {
      for (final shape in ArtworkShape.values) {
        const size = Size(300, 300);
        final morph = OutlineMorph(artworkBorder(shape, size), RoundedRectangleBorder(borderRadius: BorderRadius.circular(112)));
        final rect = Offset.zero & size;
        final start = morph.at(rect, 0).getBounds();
        final end = morph.at(rect, 1).getBounds();
        final shapeBounds = artworkBorder(shape, size).getOuterPath(rect).getBounds();
        expect(start.left, closeTo(shapeBounds.left, 6), reason: '$shape');
        expect(start.top, closeTo(shapeBounds.top, 6), reason: '$shape');
        expect(end.width, closeTo(300, 4), reason: '$shape');
        // Halfway it is still one closed, sensible outline.
        final mid = morph.at(rect, 0.5).getBounds();
        expect(mid.width, greaterThan(200), reason: '$shape');
        expect(mid.height, greaterThan(200), reason: '$shape');
      }
    });

    testWidgets('the pill copy has the same layout as the real pill', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(width: 380, child: PillFace(track: track())),
            ),
          ),
        ),
      ));
      final face = tester.getRect(find.byType(PillFace));
      expect(face.height, closeTo(74, 2));
      expect(find.text('Doomsday'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('colour swatches are solid colour all the way through', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark);
    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark)),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: PaletteSwatch(scheme: scheme, selected: false, label: 'Green', onTap: () {}),
            ),
          ),
        ),
      ),
    ));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late final List<int> pixels;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      pixels = data!.buffer.asUint8List().toList();
      image.dispose();
    });
    int alphaAt(int x, int y) => pixels[(y * 54 + x) * 4 + 3];
    // Fully opaque top, bottom left and bottom right: no see-through band.
    for (final (x, y) in [(27, 8), (27, 20), (16, 40), (38, 40), (27, 26)]) {
      expect(alphaAt(x, y), 255, reason: 'pixel $x,$y');
    }
  });
}
