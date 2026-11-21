import 'track.dart';

/// Albums, artists, genres and folders are derived from the tracks table.
/// They are computed in memory from the (already loaded) track list, which is
/// cheap even for libraries with tens of thousands of songs and keeps them
/// perfectly in sync with scans without extra tables to maintain.

class Album {
  Album({
    required this.key,
    required this.title,
    required this.artist,
    required this.tracks,
  });

  final String key;
  final String title;
  final String artist;
  final List<Track> tracks;

  String? get artPath =>
      tracks.firstWhere((t) => t.artPath != null, orElse: () => tracks.first).artPath;
  int? get year => tracks.map((t) => t.year).whereType<int>().fold<int?>(
      null, (a, b) => a == null || b > a ? b : a);
  int get durationMs => tracks.fold(0, (a, t) => a + t.durationMs);
  int get playCount => tracks.fold(0, (a, t) => a + t.playCount);
  DateTime get dateAdded =>
      tracks.map((t) => t.dateAdded).reduce((a, b) => a.isAfter(b) ? a : b);
  DateTime? get lastPlayed => tracks
      .map((t) => t.lastPlayed)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
}

class Artist {
  Artist({required this.name, required this.tracks});

  final String name;
  final List<Track> tracks;

  String get key => name.toLowerCase();
  String? get artPath =>
      tracks.firstWhere((t) => t.artPath != null, orElse: () => tracks.first).artPath;
  int get albumCount => tracks.map((t) => t.albumKey).toSet().length;
  int get playCount => tracks.fold(0, (a, t) => a + t.playCount);
  int get durationMs => tracks.fold(0, (a, t) => a + t.durationMs);
}

class Genre {
  Genre({required this.name, required this.tracks});

  final String name;
  final List<Track> tracks;

  String get key => name.toLowerCase();
  List<String> get artPaths =>
      tracks.map((t) => t.artPath).whereType<String>().toSet().take(4).toList();
  int get playCount => tracks.fold(0, (a, t) => a + t.playCount);
}

class FolderNode {
  FolderNode({
    required this.path,
    required this.name,
    required this.subfolders,
    required this.tracks,
    required this.totalTracks,
  });

  final String path;
  final String name;
  final List<FolderNode> subfolders;
  final List<Track> tracks;
  final int totalTracks;

  /// Up to four songs for the cover collage: the first songs in folder order
  /// (then subfolders), one per album so the covers differ. Computed once.
  late final List<Track> coverTracks = _pickCoverTracks();

  List<Track> _pickCoverTracks() {
    final seenAlbums = <String>{};
    final picked = <Track>[];
    void walk(FolderNode node) {
      for (final track in node.tracks) {
        if (picked.length == 4) return;
        if (seenAlbums.add(track.albumKey)) picked.add(track);
      }
      for (final sub in node.subfolders) {
        if (picked.length == 4) return;
        walk(sub);
      }
    }

    walk(this);
    return picked;
  }
}
