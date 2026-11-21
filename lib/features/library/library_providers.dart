import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/library_groups.dart';
import '../../data/models/track.dart';
import '../../data/providers.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_model.dart';
import '../../core/utils/simple_notifier.dart';
import '../../core/utils/throttle.dart';
import 'library_logic.dart';

/// Every visible (non-excluded) track. Single source of truth for the UI:
/// albums, artists, genres, folders, favorites and search derive from it.
final tracksStreamProvider = StreamProvider<List<Track>>((ref) {
  return throttleLatest(ref.watch(libraryRepositoryProvider).watchTracks(), const Duration(milliseconds: 700));
});

final allTracksProvider = Provider<List<Track>>((ref) {
  return ref.watch(tracksStreamProvider).value ?? const [];
});

final libraryLoadedProvider = Provider<bool>((ref) => ref.watch(tracksStreamProvider).hasValue);

final trackByIdProvider = Provider<Map<int, Track>>((ref) {
  return {for (final t in ref.watch(allTracksProvider)) t.id: t};
});

final musicFoldersProvider = StreamProvider<List<MusicFolderRow>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchFolders();
});

final albumsProvider = Provider<List<Album>>((ref) {
  return LibraryLogic.groupAlbums(ref.watch(allTracksProvider));
});

final albumByKeyProvider = Provider<Map<String, Album>>((ref) {
  return {for (final a in ref.watch(albumsProvider)) a.key: a};
});

final artistsProvider = Provider<List<Artist>>((ref) {
  return LibraryLogic.groupArtists(ref.watch(allTracksProvider));
});

final artistByKeyProvider = Provider<Map<String, Artist>>((ref) {
  return {for (final a in ref.watch(artistsProvider)) a.key: a};
});

final genresProvider = Provider<List<Genre>>((ref) {
  return LibraryLogic.groupGenres(ref.watch(allTracksProvider));
});

final folderTreeProvider = Provider<List<FolderNode>>((ref) {
  final roots = (ref.watch(musicFoldersProvider).value ?? const []).map((f) => f.path).toList();
  return LibraryLogic.buildFolderTree(ref.watch(allTracksProvider), roots);
});

final favoriteTracksProvider = Provider<List<Track>>((ref) {
  final favorites = ref.watch(allTracksProvider).where((t) => t.isFavorite).toList();
  favorites.sort((a, b) => (b.favoritedAt ?? b.dateAdded).compareTo(a.favoritedAt ?? a.dateAdded));
  return favorites;
});

// Library screen state -----------------------------------------------------------

enum LibraryTab { folders, artists, songs, playlists, liked, queue }

final libraryTabProvider = NotifierProvider<SimpleNotifier<LibraryTab>, LibraryTab>(
  () => SimpleNotifier(LibraryTab.songs),
);

final songSortProvider = NotifierProvider<SimpleNotifier<SortSpec>, SortSpec>(
  () => _SettingsSeededSort(),
);

final albumSortProvider = NotifierProvider<SimpleNotifier<SortSpec>, SortSpec>(
  () => SimpleNotifier(const SortSpec(SortField.title, true)),
);

final artistSortProvider = NotifierProvider<SimpleNotifier<SortSpec>, SortSpec>(
  () => SimpleNotifier(const SortSpec(SortField.title, true)),
);

/// Order of the folder list itself (the songs inside a folder have their own
/// order, kept per folder in folder_sort.dart).
final folderListSortProvider = NotifierProvider<SimpleNotifier<SortSpec>, SortSpec>(
  () => SimpleNotifier(const SortSpec(SortField.title, true)),
);

final libraryFilterProvider = NotifierProvider<SimpleNotifier<LibraryFilter>, LibraryFilter>(
  () => SimpleNotifier(const LibraryFilter()),
);

final visibleFoldersProvider = Provider<List<FolderNode>>((ref) {
  final roots = ref.watch(folderTreeProvider);
  final spec = ref.watch(folderListSortProvider);
  int compare(FolderNode a, FolderNode b) {
    final c = switch (spec.field) {
      SortField.duration => a.totalTracks.compareTo(b.totalTracks),
      SortField.dateAdded => _folderAdded(a).compareTo(_folderAdded(b)),
      _ => Track.sortKey(a.name).compareTo(Track.sortKey(b.name)),
    };
    return spec.ascending ? c : -c;
  }

  return List.of(roots)..sort(compare);
});

/// Newest song in a folder, used to sort folders by when music arrived.
DateTime _folderAdded(FolderNode node) {
  var newest = DateTime.fromMillisecondsSinceEpoch(0);
  void walk(FolderNode n) {
    for (final t in n.tracks) {
      if (t.dateAdded.isAfter(newest)) newest = t.dateAdded;
    }
    for (final s in n.subfolders) {
      walk(s);
    }
  }

  walk(node);
  return newest;
}

final visibleTracksProvider = Provider<List<Track>>((ref) {
  final filtered = LibraryLogic.filterTracks(ref.watch(allTracksProvider), ref.watch(libraryFilterProvider));
  return LibraryLogic.sortTracks(filtered, ref.watch(songSortProvider));
});

final visibleAlbumsProvider = Provider<List<Album>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  final albums = filter.isEmpty
      ? ref.watch(albumsProvider)
      : LibraryLogic.groupAlbums(LibraryLogic.filterTracks(ref.watch(allTracksProvider), filter));
  final spec = ref.watch(albumSortProvider);
  int compare(Album a, Album b) {
    final c = switch (spec.field) {
      SortField.artist => Track.sortKey(a.artist).compareTo(Track.sortKey(b.artist)),
      SortField.year => (a.year ?? 0).compareTo(b.year ?? 0),
      SortField.dateAdded => a.dateAdded.compareTo(b.dateAdded),
      SortField.playCount => a.playCount.compareTo(b.playCount),
      SortField.duration => a.durationMs.compareTo(b.durationMs),
      SortField.lastPlayed => (a.lastPlayed ?? DateTime(0)).compareTo(b.lastPlayed ?? DateTime(0)),
      _ => Track.sortKey(a.title).compareTo(Track.sortKey(b.title)),
    };
    return spec.ascending ? c : -c;
  }

  return List.of(albums)..sort(compare);
});

final visibleArtistsProvider = Provider<List<Artist>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  final artists = filter.isEmpty
      ? ref.watch(artistsProvider)
      : LibraryLogic.groupArtists(LibraryLogic.filterTracks(ref.watch(allTracksProvider), filter));
  final spec = ref.watch(artistSortProvider);
  int compare(Artist a, Artist b) {
    final c = switch (spec.field) {
      SortField.playCount => a.playCount.compareTo(b.playCount),
      SortField.duration => a.tracks.length.compareTo(b.tracks.length),
      _ => Track.sortKey(a.name).compareTo(Track.sortKey(b.name)),
    };
    return spec.ascending ? c : -c;
  }

  return List.of(artists)..sort(compare);
});

final visibleGenresProvider = Provider<List<Genre>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  if (filter.isEmpty) return ref.watch(genresProvider);
  return LibraryLogic.groupGenres(LibraryLogic.filterTracks(ref.watch(allTracksProvider), filter));
});

/// Song order: starts from the saved default and writes changes back, so the
/// choice is still there the next time the app opens.
class _SettingsSeededSort extends SimpleNotifier<SortSpec> {
  _SettingsSeededSort() : super(const SortSpec(SortField.title, true));

  @override
  SortSpec build() => ref.read(settingsProvider).defaultSort;

  @override
  void set(SortSpec value) {
    super.set(value);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(defaultSort: value));
  }
}
