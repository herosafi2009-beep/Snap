import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/theme/app_theme.dart';
import 'package:snap/core/theme/boot_colors.dart';
import 'package:snap/data/models/library_groups.dart';
import 'package:snap/features/library/folder_sort.dart';
import 'package:snap/widgets/artwork.dart';

import 'test_utils.dart';

void main() {
  group('folder covers', () {
    FolderNode folder(List<String> albums) => FolderNode(
          path: '/m',
          name: 'm',
          subfolders: const [],
          tracks: [for (final a in albums) makeTrack(album: a, folder: '/m')],
          totalTracks: albums.length,
        );

    test('picks the first four songs from different albums', () {
      final node = folder(['A', 'A', 'B', 'C', 'D', 'E']);
      expect(node.coverTracks.map((t) => t.album), ['A', 'B', 'C', 'D']);
      expect(folder(['A', 'B']).coverTracks.length, 2);
      expect(folder([]).coverTracks, isEmpty);
    });

    for (final count in [0, 1, 2, 3, 4]) {
      testWidgets('collage renders $count covers without errors', (tester) async {
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: Center(
              child: FolderCoverCollage(
                covers: [for (var i = 0; i < count; i++) (null, 'album$i')],
                size: 52,
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(find.byType(Artwork), findsNWidgets(count));
        if (count == 0) expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
      });
    }
  });

  group('folder sorting', () {
    final tracks = [
      makeTrack(title: 'b', artist: 'Zed', album: 'Y', durationMs: 300000, dateAdded: DateTime(2024, 1)),
      makeTrack(title: 'a', artist: 'Amy', album: 'X', durationMs: 100000, dateAdded: DateTime(2024, 3)),
      makeTrack(title: 'c', artist: 'Max', album: 'Z', durationMs: 200000, dateAdded: DateTime(2024, 2)),
    ];
    List<String> titles(FolderSortOption o) => o.apply(tracks).map((t) => t.title).toList();

    test('every option orders as labelled', () {
      expect(titles(FolderSortOption.nameAsc), ['a', 'b', 'c']);
      expect(titles(FolderSortOption.nameDesc), ['c', 'b', 'a']);
      expect(titles(FolderSortOption.addedNewest), ['a', 'c', 'b']);
      expect(titles(FolderSortOption.addedOldest), ['b', 'c', 'a']);
      expect(titles(FolderSortOption.artistAsc), ['a', 'c', 'b']);
      expect(titles(FolderSortOption.artistDesc), ['b', 'c', 'a']);
      expect(titles(FolderSortOption.albumAsc), ['a', 'b', 'c']);
      expect(titles(FolderSortOption.albumDesc), ['c', 'b', 'a']);
      expect(titles(FolderSortOption.durationShortest), ['a', 'c', 'b']);
      expect(titles(FolderSortOption.durationLongest), ['b', 'c', 'a']);
    });

    test('sorting never drops or duplicates songs, nor changes the source list', () {
      final before = tracks.map((t) => t.id).toList();
      for (final option in FolderSortOption.values) {
        expect(option.apply(tracks).map((t) => t.id).toSet(), before.toSet());
        expect(option.apply(tracks).length, tracks.length);
      }
      expect(tracks.map((t) => t.id).toList(), before);
    });
  });

  test('boot colors follow the theme seed and system appearance', () {
    final colors = BootColors.fromTheme(seed: AppTheme.defaultSeed, themeMode: ThemeMode.system);
    expect(colors.light.computeLuminance(), greaterThan(colors.dark.computeLuminance()));
    expect(colors.forBrightness(Brightness.dark), colors.dark);
    final forcedDark = BootColors.fromTheme(seed: AppTheme.defaultSeed, themeMode: ThemeMode.dark);
    expect(forcedDark.forBrightness(Brightness.light), forcedDark.dark);
    for (var b = 0; b < BootColors.hueBuckets; b++) {
      expect(BootColors.bucketFor(BootColors.presetSeed(b)), b);
    }
  });
}
