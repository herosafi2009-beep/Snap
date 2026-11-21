import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/data/models/library_groups.dart';
import 'package:snap/data/models/track.dart';
import 'package:snap/features/library/library_providers.dart';
import 'package:snap/features/settings/settings_model.dart';

import 'test_utils.dart';

FolderNode folder(String name, List<Track> tracks) => FolderNode(
      path: '/music/$name',
      name: name,
      subfolders: const [],
      tracks: tracks,
      totalTracks: tracks.length,
    );

void main() {
  group('per section layout', () {
    test('each section starts with a layout that suits it', () {
      const settings = AppSettings();
      expect(settings.layoutFor(LibraryCategory.songs), LibraryLayout.list);
      expect(settings.layoutFor(LibraryCategory.folders), LibraryLayout.list);
      expect(settings.layoutFor(LibraryCategory.artists), LibraryLayout.grid);
    });

    test('changing one section leaves the others alone', () {
      const settings = AppSettings();
      final artistsAsList = settings.withLayout(LibraryCategory.artists, LibraryLayout.list);
      expect(artistsAsList.layoutFor(LibraryCategory.artists), LibraryLayout.list);
      expect(artistsAsList.layoutFor(LibraryCategory.folders), LibraryLayout.list);

      final foldersAsGrid = artistsAsList.withLayout(LibraryCategory.folders, LibraryLayout.grid);
      expect(foldersAsGrid.layoutFor(LibraryCategory.folders), LibraryLayout.grid);
      // Switching folders to a grid must not drag artists back to one.
      expect(foldersAsGrid.layoutFor(LibraryCategory.artists), LibraryLayout.list);
    });

    test('layouts survive a save and reload', () {
      const settings = AppSettings();
      final chosen = settings
          .withLayout(LibraryCategory.artists, LibraryLayout.list)
          .withLayout(LibraryCategory.folders, LibraryLayout.grid);
      final restored = AppSettings.decode(chosen.encode());
      expect(restored.layoutFor(LibraryCategory.artists), LibraryLayout.list);
      expect(restored.layoutFor(LibraryCategory.folders), LibraryLayout.grid);
      expect(restored.layoutFor(LibraryCategory.songs), LibraryLayout.list);
    });

    test('a corrupted layout entry is ignored', () {
      final restored = AppSettings.decode('{"categoryLayouts":{"artists":"spiral","nonsense":"grid"}}');
      expect(restored.layoutFor(LibraryCategory.artists), const AppSettings().layoutFor(LibraryCategory.artists));
    });
  });

  group('folder order', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          folderTreeProvider.overrideWithValue([
            folder('Rock', [makeTrack(title: 'a'), makeTrack(title: 'b')]),
            folder('Ambient', [makeTrack(title: 'c', dateAdded: DateTime(2026, 5))]),
            folder('Jazz', [
              makeTrack(title: 'd'),
              makeTrack(title: 'e'),
              makeTrack(title: 'f'),
            ]),
          ]),
        ],
      );
      addTearDown(container.dispose);
    });

    List<String> names() => container.read(visibleFoldersProvider).map((f) => f.name).toList();

    test('sorts by name, both ways', () {
      container.read(folderListSortProvider.notifier).set(const SortSpec(SortField.title, true));
      expect(names(), ['Ambient', 'Jazz', 'Rock']);
      container.read(folderListSortProvider.notifier).set(const SortSpec(SortField.title, false));
      expect(names(), ['Rock', 'Jazz', 'Ambient']);
    });

    test('sorts by how much music is inside', () {
      container.read(folderListSortProvider.notifier).set(const SortSpec(SortField.duration, false));
      expect(names(), ['Jazz', 'Rock', 'Ambient']);
    });

    test('sorts by the newest music in each folder', () {
      container.read(folderListSortProvider.notifier).set(const SortSpec(SortField.dateAdded, false));
      expect(names().first, 'Ambient');
    });
  });
}
