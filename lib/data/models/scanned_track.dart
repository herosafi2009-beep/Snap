/// Metadata read from a file by the scanner isolate, before it is stored.
class ScannedTrack {
  const ScannedTrack({
    required this.path,
    required this.folder,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    required this.durationMs,
    this.artPath,
    required this.fileSize,
    required this.fileModifiedMs,
  });

  final String path;
  final String folder;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int durationMs;
  final String? artPath;
  final int fileSize;
  final int fileModifiedMs;
}

/// What the database already knows about a file, used for incremental scans.
class IndexedFile {
  const IndexedFile({
    required this.id,
    required this.fileModifiedMs,
    required this.fileSize,
    required this.hasArt,
    required this.durationMs,
  });

  final int id;
  final int fileModifiedMs;
  final int fileSize;
  final bool hasArt;
  final int durationMs;
}
