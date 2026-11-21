import 'package:flutter_test/flutter_test.dart';
import 'package:snap/data/repositories/history_repository.dart';
import 'package:snap/features/playlists/smart_playlists.dart';

import 'test_utils.dart';

void main() {
  final now = DateTime(2024, 6, 1, 12);

  test('most played is ordered by play count and excludes unplayed', () {
    final tracks = [makeTrack(title: 'a', playCount: 2), makeTrack(title: 'b', playCount: 9), makeTrack(title: 'c')];
    final list = SmartPlaylists.build(SmartPlaylistKind.mostPlayed, tracks, const {}, now: now);
    expect(list.map((t) => t.title), ['b', 'a']);
  });

  test('never finished uses listening history', () {
    final skipped = makeTrack(title: 'skipped');
    final finished = makeTrack(title: 'finished');
    final stats = {
      skipped.id: const TrackHistoryStats(plays: 3, completedPlays: 0, nightPlays: 0, lastPlayed: null),
      finished.id: const TrackHistoryStats(plays: 3, completedPlays: 2, nightPlays: 1, lastPlayed: null),
    };
    expect(SmartPlaylists.build(SmartPlaylistKind.neverFinished, [skipped, finished], stats, now: now).single.title,
        'skipped');
    expect(SmartPlaylists.build(SmartPlaylistKind.lateNight, [skipped, finished], stats, now: now).single.title,
        'finished');
  });

  test('forgotten gems are old favorites not heard recently', () {
    final gem = makeTrack(title: 'gem', playCount: 5, lastPlayed: DateTime(2024, 1, 1));
    final recent = makeTrack(title: 'recent', playCount: 5, lastPlayed: DateTime(2024, 5, 30));
    final list = SmartPlaylists.build(SmartPlaylistKind.forgottenGems, [gem, recent], const {}, now: now);
    expect(list.single.title, 'gem');
  });

  test('duration based playlists', () {
    final short = makeTrack(title: 'short', durationMs: 120000);
    final long = makeTrack(title: 'long', durationMs: 420000);
    expect(SmartPlaylists.build(SmartPlaylistKind.shortSongs, [short, long], const {}, now: now).single.title, 'short');
    expect(SmartPlaylists.build(SmartPlaylistKind.longSongs, [short, long], const {}, now: now).single.title, 'long');
  });

  test('quick picks are stable within a day and skip songs heard in the last hours', () {
    final tracks = [
      for (var i = 0; i < 40; i++) makeTrack(title: 't$i', album: 'album$i', playCount: i % 5),
      makeTrack(title: 'just heard', playCount: 100, lastPlayed: now.subtract(const Duration(minutes: 20))),
    ];
    final a = SmartPlaylists.quickPicks(tracks, const {}, now: now);
    final b = SmartPlaylists.quickPicks(tracks, const {}, now: now.add(const Duration(hours: 1)));
    expect(a.map((t) => t.id), b.map((t) => t.id));
    expect(a.length, 20);
    expect(a.any((t) => t.title == 'just heard'), isFalse);
  });

  test('every smart playlist copes with an empty library', () {
    for (final kind in SmartPlaylistKind.values) {
      expect(SmartPlaylists.build(kind, const [], const {}, now: now), isEmpty);
    }
    expect(SmartPlaylists.quickPicks(const [], const {}), isEmpty);
  });
}
