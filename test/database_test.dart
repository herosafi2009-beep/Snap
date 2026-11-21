import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/data/database/app_database.dart';
import 'package:snap/data/models/scanned_track.dart';
import 'package:snap/data/repositories/history_repository.dart';
import 'package:snap/data/repositories/library_repository.dart';
import 'package:snap/data/repositories/playlist_repository.dart';
import 'package:snap/data/repositories/settings_repository.dart';

ScannedTrack scanned(String name, {String title = 'Title', int modified = 1000}) => ScannedTrack(
      path: '/music/$name.mp3',
      folder: '/music',
      title: title,
      artist: 'Artist',
      album: 'Album',
      albumArtist: '',
      genre: 'Pop',
      durationMs: 180000,
      fileSize: 100,
      fileModifiedMs: modified,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LibraryRepository library;
  late PlaylistRepository playlists;
  late HistoryRepository history;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepository(db);
    playlists = PlaylistRepository(db);
    history = HistoryRepository(db);
    settings = SettingsRepository(db);
  });

  tearDown(() => db.close());

  test('rescans update metadata but keep favorites, play counts and date added', () async {
    await library.upsertScanned([scanned('a'), scanned('b')]);
    var tracks = await library.watchTracks().first;
    expect(tracks.length, 2);
    final a = tracks.firstWhere((t) => t.path.endsWith('a.mp3'));
    await library.setFavorite(a.id, true);
    await history.countPlay(a.id, DateTime(2024));
    final added = a.dateAdded;

    await library.upsertScanned([scanned('a', title: 'Retagged', modified: 5000)]);
    tracks = await library.watchTracks().first;
    final updated = tracks.firstWhere((t) => t.id == a.id);
    expect(updated.title, 'Retagged');
    expect(updated.isFavorite, isTrue);
    expect(updated.playCount, 1);
    expect(updated.dateAdded, added);

    final index = await library.loadIndex();
    expect(index['/music/a.mp3']!.fileModifiedMs, 5000);
  });

  test('remove from library hides songs until restored; deleting removes rows', () async {
    await library.upsertScanned([scanned('a'), scanned('b')]);
    final tracks = await library.watchTracks().first;
    await library.setExcluded([tracks.first.id], true);
    expect((await library.watchTracks().first).length, 1);
    expect(await library.excludedCount(), 1);
    // Excluded files remain in the index so rescans do not re-add them.
    expect((await library.loadIndex()).length, 2);
    await library.restoreAllExcluded();
    expect((await library.watchTracks().first).length, 2);
    await library.deleteByPaths(['/music/a.mp3']);
    expect((await library.watchTracks().first).single.path, '/music/b.mp3');
  });

  test('playlists: create, add without duplicates, reorder, remove and undo', () async {
    await library.upsertScanned([scanned('a'), scanned('b'), scanned('c')]);
    final ids = (await library.watchTracks().first).map((t) => t.id).toList()..sort();
    final id = await playlists.create('Road trip', trackIds: [ids[0], ids[1]]);

    final result = await playlists.addTracks(id, [ids[1], ids[2]]);
    expect(result.added, 1);
    expect(result.skipped, 1);

    Future<List<int>> order() async => (await playlists.watchAllEntries().first)
        .where((e) => e.playlistId == id)
        .map((e) => e.trackId)
        .toList();

    expect(await order(), [ids[0], ids[1], ids[2]]);
    await playlists.reorder(id, 2, 0);
    expect(await order(), [ids[2], ids[0], ids[1]]);

    final entries = (await playlists.watchAllEntries().first).where((e) => e.playlistId == id).toList();
    final removed = entries[1];
    await playlists.removeEntries(id, [removed.id]);
    expect(await order(), [ids[2], ids[1]]);
    await playlists.restoreEntry(removed);
    expect(await order(), [ids[2], ids[0], ids[1]]);

    await playlists.rename(id, 'Summer');
    expect((await playlists.watchPlaylists().first).single.name, 'Summer');

    // Deleting a song from the library cascades to playlist entries.
    await library.deleteById(ids[0]);
    expect(await order(), [ids[2], ids[1]]);

    await playlists.delete(id);
    expect(await playlists.watchPlaylists().first, isEmpty);
    expect(await playlists.watchAllEntries().first, isEmpty);
  });

  test('listening history aggregates and resets', () async {
    await library.upsertScanned([scanned('a')]);
    final track = (await library.watchTracks().first).single;
    final night = DateTime(2024, 1, 1, 23, 30);
    final eventId = await history.insertEvent(
      trackId: track.id,
      playedAt: night,
      listenedMs: 5000,
      completed: false,
      source: 'album:x',
    );
    await history.updateEvent(eventId, listenedMs: 170000, completed: true);
    await history.insertEvent(
        trackId: track.id, playedAt: DateTime(2024, 1, 2, 12), listenedMs: 20000, completed: false);
    await history.countPlay(track.id, night);

    final stats = (await history.watchTrackStats().first)[track.id]!;
    expect(stats.plays, 2);
    expect(stats.completedPlays, 1);
    expect(stats.nightPlays, 1);

    final totals = await history.watchTotals().first;
    expect(totals.events, 2);
    expect(totals.listenedMs, 190000);
    expect((await history.watchRecentSources().first).single.source, 'album:x');

    await history.resetStatistics();
    expect((await history.watchTotals().first).events, 0);
    expect((await library.watchTracks().first).single.playCount, 0);
  });

  test('settings, queue and search history persist', () async {
    await library.upsertScanned([scanned('a'), scanned('b')]);
    final ids = (await library.watchTracks().first).map((t) => t.id).toList();

    await settings.write('k', 'v1');
    await settings.write('k', 'v2');
    expect(await settings.read('k'), 'v2');

    await settings.saveQueue([ids[1], ids[0], ids[1]]);
    expect(await settings.loadQueue(), [ids[1], ids[0], ids[1]]);
    final restored = await library.tracksByIds(await settings.loadQueue());
    expect(restored.map((t) => t.id), [ids[1], ids[0], ids[1]]);

    await settings.addSearch('daft');
    await settings.addSearch('punk');
    await settings.addSearch('daft');
    expect((await settings.watchSearchHistory().first).toSet(), {'daft', 'punk'});
    await settings.clearSearchHistory();
    expect(await settings.watchSearchHistory().first, isEmpty);
  });
}
