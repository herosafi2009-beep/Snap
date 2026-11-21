import 'package:snap/data/models/track.dart';

int _nextId = 1;

Track makeTrack({
  int? id,
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  String albumArtist = '',
  String genre = 'Rock',
  String folder = '/music/album',
  int? year,
  int? trackNumber,
  int? discNumber,
  int durationMs = 200000,
  int playCount = 0,
  DateTime? lastPlayed,
  DateTime? dateAdded,
  bool favorite = false,
  String? artPath,
}) {
  final i = id ?? _nextId++;
  return Track(
    id: i,
    path: '$folder/$i-$title.mp3',
    folder: folder,
    title: title,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    genre: genre,
    year: year,
    trackNumber: trackNumber,
    discNumber: discNumber,
    durationMs: durationMs,
    artPath: artPath,
    fileSize: 1000,
    fileModified: DateTime(2024),
    dateAdded: dateAdded ?? DateTime(2024),
    isFavorite: favorite,
    favoritedAt: favorite ? DateTime(2024, 2) : null,
    playCount: playCount,
    lastPlayed: lastPlayed,
    excluded: false,
  );
}
