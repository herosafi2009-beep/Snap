import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';

part 'app_database.g.dart';

@UseRowClass(Track)
@TableIndex(name: 'idx_tracks_folder', columns: {#folder})
@TableIndex(name: 'idx_tracks_album', columns: {#album})
@TableIndex(name: 'idx_tracks_artist', columns: {#artist})
@TableIndex(name: 'idx_tracks_excluded', columns: {#excluded})
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  TextColumn get folder => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant(''))();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get albumArtist => text().withDefault(const Constant(''))();
  TextColumn get genre => text().withDefault(const Constant(''))();
  IntColumn get year => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get artPath => text().nullable()();

  /// User-chosen artwork ("Change album art"); never touched by scans.
  TextColumn get customArtPath => text().nullable()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  DateTimeColumn get fileModified => dateTime()();
  DateTimeColumn get dateAdded => dateTime()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get favoritedAt => dateTime().nullable()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayed => dateTime().nullable()();

  /// "Remove from library" hides the song without touching the file, and keeps
  /// later rescans from adding it back.
  BoolColumn get excluded => boolean().withDefault(const Constant(false))();
}

@DataClassName('MusicFolderRow')
class MusicFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  DateTimeColumn get addedAt => dateTime()();
}

@UseRowClass(Playlist)
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('PlaylistEntryRow')
@TableIndex(name: 'idx_entries_playlist', columns: {#playlistId, #position})
class PlaylistEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime()();
}

@DataClassName('PlayEventRow')
@TableIndex(name: 'idx_events_played_at', columns: {#playedAt})
@TableIndex(name: 'idx_events_track', columns: {#trackId})
class PlayEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get playedAt => dateTime()();
  IntColumn get listenedMs => integer().withDefault(const Constant(0))();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  /// Where playback was started from, e.g. `album:<key>` or `playlist:<id>`.
  TextColumn get source => text().nullable()();
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('SearchHistoryRow')
class SearchHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text().unique()();
  DateTimeColumn get searchedAt => dateTime()();
}

@DataClassName('QueueItemRow')
class QueueItems extends Table {
  IntColumn get position => integer()();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {position};
}

/// Lyrics saved for a song: pasted / imported by the user, or cached from the
/// file. One row per song.
@DataClassName('LyricsRow')
class SongLyrics extends Table {
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();

  /// `user` (pasted or imported) — the only kind stored for now.
  TextColumn get source => text().withDefault(const Constant('user'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}

@DriftDatabase(
  tables: [
    Tracks,
    MusicFolders,
    Playlists,
    PlaylistEntries,
    PlayEvents,
    Settings,
    SearchHistory,
    QueueItems,
    SongLyrics,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// Bump this and add a step in [migration] whenever the schema changes.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Version 2: per-song custom artwork.
          if (from < 2) await m.addColumn(tracks, tracks.customArtPath);
          // Version 3: user lyrics.
          if (from < 3) await m.createTable(songLyrics);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'snap_library',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
