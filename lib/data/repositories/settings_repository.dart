import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Key/value storage for settings, persisted queue state and search history.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<Map<String, String>> loadAll() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final r in rows) r.key: r.value};
  }

  Future<String?> read(String key) async {
    final row = await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) {
    return _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  }

  Future<void> remove(String key) => (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go();

  Future<void> removeAll(Iterable<String> keys) =>
      (_db.delete(_db.settings)..where((s) => s.key.isIn(keys))).go();

  // Queue ----------------------------------------------------------------------

  Future<void> saveQueue(List<int> trackIds) async {
    await _db.transaction(() async {
      await _db.delete(_db.queueItems).go();
      await _db.batch((b) {
        for (var i = 0; i < trackIds.length; i++) {
          b.insert(_db.queueItems, QueueItemsCompanion.insert(position: Value(i), trackId: trackIds[i]));
        }
      });
    });
  }

  Future<List<int>> loadQueue() async {
    final rows = await (_db.select(_db.queueItems)..orderBy([(q) => OrderingTerm(expression: q.position)])).get();
    return rows.map((r) => r.trackId).toList();
  }

  // Search history -------------------------------------------------------------

  Stream<List<String>> watchSearchHistory({int limit = 12}) {
    return (_db.select(_db.searchHistory)
          ..orderBy([(s) => OrderingTerm(expression: s.searchedAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch()
        .map((rows) => rows.map((r) => r.query).toList());
  }

  Future<void> addSearch(String query) {
    return _db.into(_db.searchHistory).insert(
          SearchHistoryCompanion.insert(query: query, searchedAt: DateTime.now()),
          onConflict: DoUpdate((_) => SearchHistoryCompanion(searchedAt: Value(DateTime.now())),
              target: [_db.searchHistory.query]),
        );
  }

  Future<void> removeSearch(String query) =>
      (_db.delete(_db.searchHistory)..where((s) => s.query.equals(query))).go();

  Future<void> clearSearchHistory() => _db.delete(_db.searchHistory).go();
}
