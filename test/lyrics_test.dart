import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:snap/data/database/app_database.dart';
import 'package:snap/data/models/scanned_track.dart';
import 'package:snap/data/repositories/library_repository.dart';
import 'package:snap/features/lyrics/lyrics_parser.dart';
import 'package:snap/features/lyrics/lyrics_service.dart';

ScannedTrack scanned(String name) => ScannedTrack(
      path: '/music/$name.mp3',
      folder: '/music',
      title: name,
      artist: 'Artist',
      album: 'Album',
      albumArtist: '',
      genre: 'Pop',
      durationMs: 180000,
      artPath: null,
      fileSize: 100,
      fileModifiedMs: 1000,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('plain lyrics keep their lines and lose the blank edges', () {
    final doc = LyricsParser.parse('\n\nFirst line\n\nSecond line\n\n');
    expect(doc.synced, isFalse);
    expect(doc.lines.map((l) => l.text).toList(), ['First line', '', 'Second line']);
    expect(doc.indexAt(const Duration(seconds: 5)), -1);
  });

  test('lrc lyrics are timed, sorted and stripped of tags', () {
    const raw = '[ar:Someone]\n'
        '[ti:A song]\n'
        '[00:20.50]Second line\n'
        '[00:05.00]<00:05.00>First <00:06.00>line\n'
        '[00:30.00][00:40.00]Chorus\n';
    final doc = LyricsParser.parse(raw);
    expect(doc.synced, isTrue);
    expect(doc.lines.map((l) => l.text).toList(), ['First line', 'Second line', 'Chorus', 'Chorus']);
    expect(doc.lines.first.time, const Duration(seconds: 5));
    expect(doc.indexAt(const Duration(seconds: 1)), -1);
    expect(doc.indexAt(const Duration(seconds: 6)), 0);
    expect(doc.indexAt(const Duration(seconds: 25)), 1);
    expect(doc.indexAt(const Duration(seconds: 45)), 3);
  });

  test('an offset tag shifts every line', () {
    final doc = LyricsParser.parse('[offset:-1000]\n[00:10.00]A\n[00:20.00]B\n');
    expect(doc.lines.first.time, const Duration(seconds: 11));
    expect(doc.lines.last.time, const Duration(seconds: 21));
  });

  test('empty or tag only lyrics count as no lyrics', () {
    expect(LyricsParser.parse('').isEmpty, isTrue);
    expect(LyricsParser.parse('[ar:Someone]\n[al:Album]\n').isEmpty, isTrue);
    expect(LyricsParser.parse('Something').isEmpty, isFalse);
  });

  test('lyrics the user saves are stored per song and can be removed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryRepository(db);
    await library.upsertScanned([scanned('one'), scanned('two')]);
    final tracks = await library.watchTracks().first;
    final service = LyricsService(db);

    await service.saveUser(tracks.first.id, 'My words');
    expect((await service.watchUser(tracks.first.id).first)?.content, 'My words');
    expect(await service.watchUser(tracks.last.id).first, isNull);

    // Saving again replaces rather than duplicating.
    await service.saveUser(tracks.first.id, 'Better words');
    expect((await service.watchUser(tracks.first.id).first)?.content, 'Better words');

    await service.deleteUser(tracks.first.id);
    expect(await service.watchUser(tracks.first.id).first, isNull);
  });

  test('a version 2 library gains the lyrics table', () async {
    final dir = Directory.systemTemp.createTempSync('snap_lyrics_migration_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'library.sqlite'));

    final v2 = AppDatabase(NativeDatabase(file));
    await LibraryRepository(v2).upsertScanned([scanned('kept')]);
    await v2.customStatement('DROP TABLE song_lyrics');
    await v2.customStatement('PRAGMA user_version = 2');
    await v2.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final track = (await LibraryRepository(upgraded).watchTracks().first).single;
    expect(track.title, 'kept');
    final service = LyricsService(upgraded);
    await service.saveUser(track.id, 'After the upgrade');
    expect((await service.watchUser(track.id).first)?.content, 'After the upgrade');
  });
}
