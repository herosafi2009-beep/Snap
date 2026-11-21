import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/playlist.dart';

class AddToPlaylistResult {
  const AddToPlaylistResult(this.added, this.skipped);
  final int added;
  final int skipped;
}

class PlaylistRepository {
  PlaylistRepository(this._db);

  final AppDatabase _db;

  Stream<List<Playlist>> watchPlaylists() {
    return (_db.select(_db.playlists)
          ..orderBy([(p) => OrderingTerm(expression: p.updatedAt, mode: OrderingMode.desc)]))
        .watch();
  }

  /// All entries of all playlists, ordered. Used to build playlist summaries.
  Stream<List<PlaylistEntryRow>> watchAllEntries() {
    return (_db.select(_db.playlistEntries)
          ..orderBy([
            (e) => OrderingTerm(expression: e.playlistId),
            (e) => OrderingTerm(expression: e.position),
          ]))
        .watch();
  }

  Future<int> create(String name, {List<int> trackIds = const []}) async {
    final now = DateTime.now();
    return _db.transaction(() async {
      final id = await _db.into(_db.playlists).insert(
            PlaylistsCompanion.insert(name: name.trim(), createdAt: now, updatedAt: now),
          );
      if (trackIds.isNotEmpty) await _append(id, trackIds, allowDuplicates: true);
      return id;
    });
  }

  Future<void> rename(int id, String name) => _touch(id, PlaylistsCompanion(name: Value(name.trim())));

  Future<void> setCover(int id, String? coverPath) =>
      _touch(id, PlaylistsCompanion(coverPath: Value(coverPath)));

  Future<void> delete(int id) => (_db.delete(_db.playlists)..where((p) => p.id.equals(id))).go();

  Future<AddToPlaylistResult> addTracks(int playlistId, List<int> trackIds) {
    return _db.transaction(() async {
      final result = await _append(playlistId, trackIds, allowDuplicates: false);
      await _touch(playlistId, const PlaylistsCompanion());
      return result;
    });
  }

  Future<AddToPlaylistResult> _append(int playlistId, List<int> trackIds,
      {required bool allowDuplicates}) async {
    final existing = await (_db.select(_db.playlistEntries)
          ..where((e) => e.playlistId.equals(playlistId)))
        .get();
    final present = existing.map((e) => e.trackId).toSet();
    var position = existing.fold<int>(-1, (m, e) => e.position > m ? e.position : m) + 1;
    var added = 0;
    var skipped = 0;
    final now = DateTime.now();
    await _db.batch((b) {
      for (final trackId in trackIds) {
        if (!allowDuplicates && present.contains(trackId)) {
          skipped++;
          continue;
        }
        present.add(trackId);
        b.insert(
          _db.playlistEntries,
          PlaylistEntriesCompanion.insert(
            playlistId: playlistId,
            trackId: trackId,
            position: position++,
            addedAt: now,
          ),
        );
        added++;
      }
    });
    return AddToPlaylistResult(added, skipped);
  }

  Future<void> removeEntries(int playlistId, List<int> entryIds) async {
    await _db.transaction(() async {
      await (_db.delete(_db.playlistEntries)..where((e) => e.id.isIn(entryIds))).go();
      await _reindex(playlistId);
      await _touch(playlistId, const PlaylistsCompanion());
    });
  }

  /// Re-inserts a previously removed entry at its old position (undo).
  Future<void> restoreEntry(PlaylistEntryRow entry) async {
    await _db.transaction(() async {
      final entries = await _entries(entry.playlistId);
      final ids = entries.map((e) => e.trackId).toList();
      final index = entry.position.clamp(0, ids.length);
      final newId = await _db.into(_db.playlistEntries).insert(PlaylistEntriesCompanion.insert(
            playlistId: entry.playlistId,
            trackId: entry.trackId,
            position: ids.length,
            addedAt: entry.addedAt,
          ));
      final order = entries.map((e) => e.id).toList()..insert(index, newId);
      await _writeOrder(order);
    });
  }

  Future<void> reorder(int playlistId, int oldIndex, int newIndex) async {
    await _db.transaction(() async {
      final entries = await _entries(playlistId);
      if (oldIndex < 0 || oldIndex >= entries.length) return;
      final ids = entries.map((e) => e.id).toList();
      final moved = ids.removeAt(oldIndex);
      ids.insert(newIndex.clamp(0, ids.length), moved);
      await _writeOrder(ids);
      await _touch(playlistId, const PlaylistsCompanion());
    });
  }

  Future<List<PlaylistEntryRow>> _entries(int playlistId) {
    return (_db.select(_db.playlistEntries)
          ..where((e) => e.playlistId.equals(playlistId))
          ..orderBy([(e) => OrderingTerm(expression: e.position)]))
        .get();
  }

  Future<void> _reindex(int playlistId) async {
    final entries = await _entries(playlistId);
    await _writeOrder(entries.map((e) => e.id).toList());
  }

  Future<void> _writeOrder(List<int> entryIds) async {
    await _db.batch((b) {
      for (var i = 0; i < entryIds.length; i++) {
        b.update(
          _db.playlistEntries,
          PlaylistEntriesCompanion(position: Value(i)),
          where: (e) => e.id.equals(entryIds[i]),
        );
      }
    });
  }

  Future<void> _touch(int id, PlaylistsCompanion changes) {
    return (_db.update(_db.playlists)..where((p) => p.id.equals(id)))
        .write(changes.copyWith(updatedAt: Value(DateTime.now())));
  }
}
