import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../../data/models/library_groups.dart';
import '../../data/models/track.dart';
import '../settings/settings_model.dart';

/// Pure functions for sorting, filtering and grouping. Kept free of Flutter so
/// they are easy to unit test.
class LibraryLogic {
  static List<Track> sortTracks(List<Track> tracks, SortSpec spec) {
    int cmpNullable<T extends Comparable<dynamic>>(T? a, T? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    int base(Track a, Track b) {
      switch (spec.field) {
        case SortField.title:
          return a.titleKey.compareTo(b.titleKey);
        case SortField.artist:
          final c = a.artistKey.compareTo(b.artistKey);
          return c != 0 ? c : albumOrder(a, b);
        case SortField.album:
          return albumOrder(a, b);
        case SortField.dateAdded:
          return a.dateAdded.compareTo(b.dateAdded);
        case SortField.dateModified:
          return a.fileModified.compareTo(b.fileModified);
        case SortField.duration:
          return a.durationMs.compareTo(b.durationMs);
        case SortField.playCount:
          return a.playCount.compareTo(b.playCount);
        case SortField.lastPlayed:
          return cmpNullable(a.lastPlayed, b.lastPlayed);
        case SortField.year:
          return cmpNullable(a.year, b.year);
      }
    }

    final sorted = List.of(tracks);
    final nullsLast = spec.field == SortField.lastPlayed || spec.field == SortField.year;
    sorted.sort((a, b) {
      var c = base(a, b);
      if (!spec.ascending) {
        // Keep "never played" / "no year" at the bottom in both directions.
        if (nullsLast) {
          final an = spec.field == SortField.year ? a.year == null : a.lastPlayed == null;
          final bn = spec.field == SortField.year ? b.year == null : b.lastPlayed == null;
          if (an != bn) return an ? 1 : -1;
        }
        c = -c;
      }
      return c != 0 ? c : a.titleKey.compareTo(b.titleKey);
    });
    return sorted;
  }

  /// Album order: album name, disc, track number, title.
  static int albumOrder(Track a, Track b) {
    var c = a.albumKeyLower.compareTo(b.albumKeyLower);
    if (c != 0) return c;
    c = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
    if (c != 0) return c;
    c = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
    if (c != 0) return c;
    return a.titleKey.compareTo(b.titleKey);
  }

  static int trackOrderInAlbum(Track a, Track b) {
    var c = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
    if (c != 0) return c;
    c = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
    if (c != 0) return c;
    return a.titleKey.compareTo(b.titleKey);
  }

  static List<Track> filterTracks(List<Track> tracks, LibraryFilter filter, {DateTime? now}) {
    if (filter.isEmpty) return tracks;
    final recentCutoff = (now ?? DateTime.now()).subtract(const Duration(days: 30));
    return tracks.where((t) {
      if (filter.favorites && !t.isFavorite) return false;
      if (filter.recentlyAdded && t.dateAdded.isBefore(recentCutoff)) return false;
      if (filter.played == true && t.playCount == 0) return false;
      if (filter.played == false && t.playCount > 0) return false;
      if (filter.genre != null && !t.genreNames.any((g) => g.toLowerCase() == filter.genre)) return false;
      if (filter.artist != null && !t.artistNames.any((a) => a.toLowerCase() == filter.artist)) return false;
      if (filter.albumKey != null && t.albumKey != filter.albumKey) return false;
      return true;
    }).toList();
  }

  static List<Album> groupAlbums(List<Track> tracks) {
    final groups = groupBy<Track, String>(tracks, (t) => t.albumKey);
    return groups.entries.map((e) {
      final list = e.value..sort(trackOrderInAlbum);
      final first = list.first;
      final artists = list.map((t) => t.displayArtist).toSet();
      final artist = first.albumArtist.trim().isNotEmpty
          ? first.albumArtist.trim()
          : artists.length == 1
              ? artists.first
              : 'Various artists';
      return Album(key: e.key, title: first.displayAlbum, artist: artist, tracks: list);
    }).toList()
      ..sort((a, b) => Track.sortKey(a.title).compareTo(Track.sortKey(b.title)));
  }

  static List<Artist> groupArtists(List<Track> tracks) {
    final map = <String, List<Track>>{};
    final names = <String, String>{};
    for (final t in tracks) {
      for (final name in t.artistNames) {
        final key = name.toLowerCase();
        names.putIfAbsent(key, () => name);
        (map[key] ??= []).add(t);
      }
    }
    return map.entries
        .map((e) => Artist(name: names[e.key]!, tracks: e.value..sort(albumOrder)))
        .toList()
      ..sort((a, b) => Track.sortKey(a.name).compareTo(Track.sortKey(b.name)));
  }

  static List<Genre> groupGenres(List<Track> tracks) {
    final map = <String, List<Track>>{};
    final names = <String, String>{};
    for (final t in tracks) {
      for (final name in t.genreNames) {
        final key = name.toLowerCase();
        names.putIfAbsent(key, () => name);
        (map[key] ??= []).add(t);
      }
    }
    return map.entries.map((e) => Genre(name: names[e.key]!, tracks: e.value)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  /// Builds the folder tree below each music root.
  static List<FolderNode> buildFolderTree(List<Track> tracks, List<String> roots) {
    final byFolder = groupBy<Track, String>(tracks, (t) => t.folder);
    final sortedRoots = roots.map(p.normalize).toList()..sort((a, b) => b.length.compareTo(a.length));
    final top = <String, _MutableFolder>{};

    for (final entry in byFolder.entries) {
      final folder = entry.key;
      // Longest matching root wins; folders outside every root (e.g. a removed
      // root that was not rescanned yet) become their own top-level entry.
      final root = sortedRoots.firstWhereOrNull((r) => p.equals(r, folder) || p.isWithin(r, folder)) ?? folder;
      var node = top.putIfAbsent(root, () => _MutableFolder(root));
      if (!p.equals(root, folder)) {
        for (final segment in p.split(p.relative(folder, from: root))) {
          node = node.children.putIfAbsent(segment, () => _MutableFolder(p.join(node.path, segment)));
        }
      }
      node.tracks.addAll(entry.value);
    }

    return top.values.map((n) => n.freeze()).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  static FolderNode? findFolder(List<FolderNode> nodes, String path) {
    for (final n in nodes) {
      if (p.equals(n.path, path)) return n;
      if (p.isWithin(n.path, path)) return findFolder(n.subfolders, path);
    }
    return null;
  }
}

class _MutableFolder {
  _MutableFolder(this.path);
  final String path;
  final Map<String, _MutableFolder> children = {};
  final List<Track> tracks = [];

  FolderNode freeze() {
    final subfolders = children.values.map((c) => c.freeze()).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    tracks.sort(LibraryLogic.albumOrder);
    final base = p.basename(path);
    return FolderNode(
      path: path,
      name: base.isEmpty ? path : base,
      subfolders: subfolders,
      tracks: tracks,
      totalTracks: tracks.length + subfolders.fold(0, (a, s) => a + s.totalTracks),
    );
  }
}

class LibraryFilter {
  const LibraryFilter({
    this.favorites = false,
    this.recentlyAdded = false,
    this.played,
    this.genre,
    this.artist,
    this.albumKey,
  });

  final bool favorites;
  final bool recentlyAdded;

  /// true = played only, false = unplayed only, null = both.
  final bool? played;
  final String? genre;
  final String? artist;
  final String? albumKey;

  bool get isEmpty =>
      !favorites && !recentlyAdded && played == null && genre == null && artist == null && albumKey == null;

  LibraryFilter copyWith({
    bool? favorites,
    bool? recentlyAdded,
    bool? Function()? played,
    String? Function()? genre,
    String? Function()? artist,
    String? Function()? albumKey,
  }) {
    return LibraryFilter(
      favorites: favorites ?? this.favorites,
      recentlyAdded: recentlyAdded ?? this.recentlyAdded,
      played: played != null ? played() : this.played,
      genre: genre != null ? genre() : this.genre,
      artist: artist != null ? artist() : this.artist,
      albumKey: albumKey != null ? albumKey() : this.albumKey,
    );
  }
}
