import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/theme/app_theme.dart';
import 'package:snap/features/library/library_providers.dart';
import 'package:snap/features/player/player_controller.dart';
import 'package:snap/features/settings/settings_model.dart';
import 'package:snap/data/models/library_groups.dart';
import 'package:snap/features/library/collection_screens.dart';
import 'package:snap/features/shell/mini_player.dart';
import 'package:snap/widgets/common.dart';
import 'package:snap/widgets/track_tile.dart';

import 'test_utils.dart';

Widget host(Widget child, {List overrides = const []}) {
  return ProviderScope(
    overrides: [
      playingProvider.overrideWith((ref) => Stream.value(false)),
      currentTrackProvider.overrideWithValue(null),
      trackByIdProvider.overrideWithValue(const {}),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppTheme.scheme(AppTheme.defaultSeed, Brightness.light),
          compact: false, animationLevel: AnimationLevel.off),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('empty state shows its message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(EmptyState(
      icon: Icons.library_music_rounded,
      title: 'No music yet',
      message: 'Choose a music folder to build your library.',
      action: FilledButton(onPressed: () => tapped = true, child: const Text('Add Music Folder')),
    )));
    expect(find.text('No music yet'), findsOneWidget);
    await tester.tap(find.text('Add Music Folder'));
    expect(tapped, isTrue);
  });

  testWidgets('track tile renders long metadata without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var tapped = false;
    final track = makeTrack(
      title: 'An extremely long song title that keeps going and going well past the edge',
      artist: 'An artist with a very long name as well',
      album: 'And an album name that is also far too long',
      favorite: true,
      playCount: 12,
    );
    await tester.pumpWidget(host(TrackTile(track: track, onTap: () => tapped = true)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(TrackTile));
    expect(tapped, isTrue);
  });

  testWidgets('folder tile sits in a container and shows what is inside', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final node = FolderNode(
      path: '/music/Live sets',
      name: 'Live sets',
      subfolders: [
        FolderNode(path: '/music/Live sets/2024', name: '2024', subfolders: const [], tracks: const [], totalTracks: 0),
      ],
      tracks: [makeTrack(title: 'one'), makeTrack(title: 'two')],
      totalTracks: 2,
    );
    var opened = false;
    await tester.pumpWidget(host(FolderTile(node: node, onTap: () => opened = true)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Live sets'), findsOneWidget);
    expect(find.text('1 folder · 2 songs'), findsOneWidget);
    // The container itself, not a bare row of text.
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(FolderTile), matching: find.byType(Material)).first,
    );
    expect(material.shape, isA<RoundedRectangleBorder>());
    await tester.tap(find.text('Live sets'));
    expect(opened, isTrue);
  });

  testWidgets('folder card fits a grid cell', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final node = FolderNode(
      path: '/music/Chill',
      name: 'A folder name long enough to need trimming in a narrow grid cell',
      subfolders: const [],
      tracks: [makeTrack(title: 'one')],
      totalTracks: 1,
    );
    await tester.pumpWidget(host(SizedBox(
      width: 170,
      height: 220,
      child: FolderCard(node: node, onTap: () {}),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('1 song'), findsOneWidget);
  });

  testWidgets('mini player is hidden when nothing is queued', (tester) async {
    await tester.pumpWidget(host(const Align(alignment: Alignment.bottomCenter, child: MiniPlayer())));
    await tester.pump();
    expect(find.byType(InkWell), findsNothing);
  });
}
