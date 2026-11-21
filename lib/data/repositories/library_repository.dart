import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/scanned_track.dart';
import '../models/track.dart';

class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  $TracksTable get _tracks => _db.tracks;

  Stream<List<Track>> watchTracks() {
    return (_db.select(_tracks)..where((t) => t.excluded.equals(false))).watch();
  }

  Future<List<Track>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = <Track>[];
    // SQLite limits the number of bound variables; query in chunks.
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      rows.addAll(await (_db.select(_tracks)..where((t) => t.id.isIn(chunk))).get());
    }
    final byId = {for (final t in rows) t.id: t};
    return [for (final id in ids) ?byId[id]];
  }

  Future<int> excludedCount() async {
    final count = _tracks.id.count();
    final query = _db.selectOnly(_tracks)
      ..addColumns([count])
      ..where(_tracks.excluded.equals(true));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Path -> index info for every known file (including excluded ones).
  Future<Map<String, IndexedFile>> loadIndex() async {
    final query = _db.selectOnly(_tracks)
      ..addColumns([
        _tracks.id,
        _tracks.path,
        _tracks.fileModified,
        _tracks.fileSize,
        _tracks.artPath,
        _tracks.durationMs,
      ]);
    final rows = await query.get();
    return {
      for (final r in rows)
        r.read(_tracks.path)!: IndexedFile(
          id: r.read(_tracks.id)!,
          fileModifiedMs: r.read(_tracks.fileModified)!.millisecondsSinceEpoch,
          fileSize: r.read(_tracks.fileSize)!,
          hasArt: r.read(_tracks.artPath) != null,
          durationMs: r.read(_tracks.durationMs)!,
        ),
    };
  }

  /// Every artwork file referenced by a track, scanned or custom (used to
  /// prune files nobody points at any more).
  Future<Set<String>> referencedArtPaths() async {
    final query = _db.selectOnly(_tracks)
      ..addColumns([_tracks.artPath, _tracks.customArtPath])
      ..where(_tracks.artPath.isNotNull() | _tracks.customArtPath.isNotNull());
    final rows = await query.get();
    return {
      for (final r in rows) ...[?r.read(_tracks.artPath), ?r.read(_tracks.customArtPath)],
    };
  }

  /// Inserts new files and refreshes metadata of changed ones while keeping
  /// user data (favorites, play counts, date added) intact.
  Future<void> upsertScanned(List<ScannedTrack> batch) async {
    if (batch.isEmpty) return;
    final now = DateTime.now();
    await _db.batch((b) {
      for (final s in batch) {
        final modified = DateTime.fromMillisecondsSinceEpoch(s.fileModifiedMs);
        final update = TracksCompanion(
          folder: Value(s.folder),
          title: Value(s.title),
          artist: Value(s.artist),
          album: Value(s.album),
          albumArtist: Value(s.albumArtist),
          genre: Value(s.genre),
          year: Value(s.year),
          trackNumber: Value(s.trackNumber),
          discNumber: Value(s.discNumber),
          durationMs: Value(s.durationMs),
          artPath: Value(s.artPath),
          fileSize: Value(s.fileSize),
          fileModified: Value(modified),
        );
        b.insert(
          _tracks,
          update.copyWith(path: Value(s.path), dateAdded: Value(now)),
          onConflict: DoUpdate((_) => update, target: [_tracks.path]),
        );
      }
    });
  }

  /// Sets (or with null, clears) a song's user-chosen artwork.
  Future<void> setCustomArt(int id, String? path) {
    return (_db.update(_tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(customArtPath: Value(path)));
  }

  Future<void> deleteByPaths(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;
    await _db.transaction(() async {
      for (var i = 0; i < list.length; i += 500) {
        final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
        await (_db.delete(_tracks)..where((t) => t.path.isIn(chunk))).go();
      }
    });
  }

  Future<void> deleteById(int id) =>
      (_db.delete(_tracks)..where((t) => t.id.equals(id))).go();

  Future<void> setFavorite(int id, bool favorite) {
    return (_db.update(_tracks)..where((t) => t.id.equals(id))).write(
      TracksCompanion(
        isFavorite: Value(favorite),
        favoritedAt: Value(favorite ? DateTime.now() : null),
      ),
    );
  }

  Future<void> setExcluded(List<int> ids, bool excluded) {
    return (_db.update(_tracks)..where((t) => t.id.isIn(ids)))
        .write(TracksCompanion(excluded: Value(excluded)));
  }

  Future<void> restoreAllExcluded() {
    return (_db.update(_tracks)..where((t) => t.excluded.equals(true)))
        .write(const TracksCompanion(excluded: Value(false)));
  }

  Future<void> updateDuration(int id, int durationMs) {
    return (_db.update(_tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(durationMs: Value(durationMs)));
  }

  /// Forces the next scan to re-read every file (used after clearing the
  /// artwork cache or when the user asks for a full rescan).
  Future<void> invalidateIndex({bool clearArt = false}) {
    return _db.update(_tracks).write(TracksCompanion(
          fileModified: Value(DateTime.fromMillisecondsSinceEpoch(0)),
          artPath: clearArt ? const Value(null) : const Value.absent(),
        ));
  }

  // Music folders ------------------------------------------------------------

  Stream<List<MusicFolderRow>> watchFolders() =>
      (_db.select(_db.musicFolders)..orderBy([(f) => OrderingTerm(expression: f.path)])).watch();

  Future<List<MusicFolderRow>> folders() => _db.select(_db.musicFolders).get();

  Future<void> addFolder(String path) {
    return _db.into(_db.musicFolders).insert(
          MusicFoldersCompanion.insert(path: path, addedAt: DateTime.now()),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> removeFolder(String path) =>
      (_db.delete(_db.musicFolders)..where((f) => f.path.equals(path))).go();
}
