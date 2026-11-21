import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:snap/data/database/app_database.dart';
import 'package:snap/data/models/scanned_track.dart';
import 'package:snap/data/repositories/library_repository.dart';

ScannedTrack scanned(String name, {String? art, int modified = 1000}) => ScannedTrack(
      path: '/music/$name.mp3',
      folder: '/music',
      title: name,
      artist: 'Artist',
      album: 'Album',
      albumArtist: '',
      genre: 'Pop',
      durationMs: 180000,
      artPath: art,
      fileSize: 100,
      fileModifiedMs: modified,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('custom album art wins over scanned art and survives rescans', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryRepository(db);

    await library.upsertScanned([scanned('song', art: '/cache/embedded.jpg')]);
    var track = (await library.watchTracks().first).single;
    expect(track.artPath, '/cache/embedded.jpg');

    await library.setCustomArt(track.id, '/custom/mine.png');
    track = (await library.watchTracks().first).single;
    expect(track.artPath, '/custom/mine.png');
    expect(track.scannedArtPath, '/cache/embedded.jpg');

    // A rescan with new embedded art keeps the user's choice.
    await library.upsertScanned([scanned('song', art: '/cache/new.jpg', modified: 9000)]);
    track = (await library.watchTracks().first).single;
    expect(track.artPath, '/custom/mine.png');
    expect(track.scannedArtPath, '/cache/new.jpg');

    // Clearing the image cache does not touch custom art either.
    await library.invalidateIndex(clearArt: true);
    expect((await library.watchTracks().first).single.artPath, '/custom/mine.png');
    expect(await library.referencedArtPaths(), contains('/custom/mine.png'));

    await library.setCustomArt(track.id, null);
    expect((await library.watchTracks().first).single.artPath, isNull);
  });

  test('a version 1 library upgrades without losing data', () async {
    final dir = Directory.systemTemp.createTempSync('snap_migration_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'library.sqlite'));

    // Build a database, then turn it back into the version 1 schema.
    final v2 = AppDatabase(NativeDatabase(file));
    await LibraryRepository(v2).upsertScanned([scanned('kept', art: '/cache/a.jpg')]);
    await v2.customStatement('ALTER TABLE tracks DROP COLUMN custom_art_path');
    await v2.customStatement('PRAGMA user_version = 1');
    await v2.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final library = LibraryRepository(upgraded);
    final track = (await library.watchTracks().first).single;
    expect(track.title, 'kept');
    expect(track.artPath, '/cache/a.jpg');
    await library.setCustomArt(track.id, '/custom/b.png');
    expect((await library.watchTracks().first).single.artPath, '/custom/b.png');
  });
}
