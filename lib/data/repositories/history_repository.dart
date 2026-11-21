import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Aggregated listening behaviour for one track, used by smart playlists and
/// home recommendations.
class TrackHistoryStats {
  const TrackHistoryStats({
    required this.plays,
    required this.completedPlays,
    required this.nightPlays,
    required this.lastPlayed,
  });

  final int plays;
  final int completedPlays;
  final int nightPlays;
  final DateTime? lastPlayed;

  int get unfinishedPlays => plays - completedPlays;
}

class RecentPlay {
  const RecentPlay({required this.trackId, required this.playedAt, this.source});
  final int trackId;
  final DateTime playedAt;
  final String? source;
}

/// Everything here stays on the device. Nothing is uploaded anywhere.
class HistoryRepository {
  HistoryRepository(this._db);

  final AppDatabase _db;

  Future<int> insertEvent({
    required int trackId,
    required DateTime playedAt,
    required int listenedMs,
    required bool completed,
    String? source,
  }) {
    return _db.into(_db.playEvents).insert(PlayEventsCompanion.insert(
          trackId: trackId,
          playedAt: playedAt,
          listenedMs: Value(listenedMs),
          completed: Value(completed),
          source: Value(source),
        ));
  }

  Future<void> updateEvent(int id, {required int listenedMs, required bool completed}) {
    return (_db.update(_db.playEvents)..where((e) => e.id.equals(id))).write(
      PlayEventsCompanion(listenedMs: Value(listenedMs), completed: Value(completed)),
    );
  }

  /// Increments the play counter once a listen qualifies as a real play.
  Future<void> countPlay(int trackId, DateTime when) {
    return _db.customUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played = ? WHERE id = ?',
      variables: [Variable.withDateTime(when), Variable.withInt(trackId)],
      updates: {_db.tracks},
    );
  }

  /// Most recent distinct plays (one row per track), newest first.
  Stream<List<RecentPlay>> watchRecentPlays({int limit = 60}) {
    return _db
        .customSelect(
          'SELECT track_id, MAX(played_at) AS last, source FROM play_events '
          'GROUP BY track_id ORDER BY last DESC LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: {_db.playEvents},
        )
        .watch()
        .map((rows) => [
              for (final r in rows)
                RecentPlay(
                  trackId: r.read<int>('track_id'),
                  playedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('last') * 1000),
                  source: r.readNullable<String>('source'),
                ),
            ]);
  }

  /// Most recent play sources (albums, playlists...) for "Continue listening".
  Stream<List<RecentPlay>> watchRecentSources({int limit = 12}) {
    return _db
        .customSelect(
          'SELECT source, MAX(played_at) AS last, MAX(track_id) AS track_id FROM play_events '
          'WHERE source IS NOT NULL GROUP BY source ORDER BY last DESC LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: {_db.playEvents},
        )
        .watch()
        .map((rows) => [
              for (final r in rows)
                RecentPlay(
                  trackId: r.read<int>('track_id'),
                  playedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('last') * 1000),
                  source: r.read<String>('source'),
                ),
            ]);
  }

  Stream<Map<int, TrackHistoryStats>> watchTrackStats() {
    return _db
        .customSelect(
          'SELECT track_id, COUNT(*) AS plays, '
          'SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END) AS completed_plays, '
          "SUM(CASE WHEN CAST(strftime('%H', played_at, 'unixepoch', 'localtime') AS INTEGER) >= 22 "
          "OR CAST(strftime('%H', played_at, 'unixepoch', 'localtime') AS INTEGER) < 4 THEN 1 ELSE 0 END) AS night_plays, "
          'MAX(played_at) AS last '
          'FROM play_events GROUP BY track_id',
          readsFrom: {_db.playEvents},
        )
        .watch()
        .map((rows) => {
              for (final r in rows)
                r.read<int>('track_id'): TrackHistoryStats(
                  plays: r.read<int>('plays'),
                  completedPlays: r.read<int>('completed_plays'),
                  nightPlays: r.read<int>('night_plays'),
                  lastPlayed: DateTime.fromMillisecondsSinceEpoch(r.read<int>('last') * 1000),
                ),
            });
  }

  Stream<List<PlayEventRow>> watchEventsSince(DateTime since) {
    return (_db.select(_db.playEvents)
          ..where((e) => e.playedAt.isBiggerOrEqualValue(since))
          ..orderBy([(e) => OrderingTerm(expression: e.playedAt)]))
        .watch();
  }

  Stream<({int events, int listenedMs})> watchTotals() {
    return _db
        .customSelect(
          'SELECT COUNT(*) AS events, COALESCE(SUM(listened_ms), 0) AS listened FROM play_events',
          readsFrom: {_db.playEvents},
        )
        .watchSingle()
        .map((r) => (events: r.read<int>('events'), listenedMs: r.read<int>('listened')));
  }

  Future<void> resetStatistics() async {
    await _db.transaction(() async {
      await _db.delete(_db.playEvents).go();
      await _db.customUpdate(
        'UPDATE tracks SET play_count = 0, last_played = NULL',
        updates: {_db.tracks},
      );
    });
  }
}
