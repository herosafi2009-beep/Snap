import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:snap/core/services/library_scanner.dart';
import 'package:snap/data/models/scanned_track.dart';

/// Minimal valid 16-bit mono PCM WAV of [seconds] of silence.
Uint8List wav(int seconds) {
  const rate = 8000;
  final dataLen = rate * 2 * seconds;
  final b = ByteData(44 + dataLen);
  void str(int o, String s) => s.codeUnits.asMap().forEach((i, c) => b.setUint8(o + i, c));
  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  group('parseFileName', () {
    test('track number, artist and title', () {
      final r = parseFileName('01 - Daft Punk - One More Time');
      expect(r.track, 1);
      expect(r.artist, 'Daft Punk');
      expect(r.title, 'One More Time');
    });
    test('track number and title', () {
      final r = parseFileName('07. Intro');
      expect(r.track, 7);
      expect(r.title, 'Intro');
      expect(r.artist, isNull);
    });
    test('plain title', () {
      final r = parseFileName('voice_memo');
      expect(r.title, 'voice memo');
      expect(r.track, isNull);
    });
  });

  test('hashBytes is stable and content sensitive', () {
    final a = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    final b = Uint8List.fromList(List.generate(1000, (i) => (i + 1) % 256));
    expect(hashBytes(a), hashBytes(Uint8List.fromList(a)));
    expect(hashBytes(a), isNot(hashBytes(b)));
  });

  group('scanLibraryIsolate', () {
    late Directory root;
    late Directory art;

    setUp(() {
      root = Directory.systemTemp.createTempSync('snap_scan_');
      art = Directory(p.join(root.path, '.art'));
    });

    tearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<List<ScanMessage>> run(Map<String, IndexedFile> index, {int minDurationMs = 0}) async {
      final port = ReceivePort();
      final messages = <ScanMessage>[];
      final done = port.listen((m) => messages.add(m as ScanMessage));
      await scanLibraryIsolate(ScanRequest(
        roots: [p.join(root.path, 'music'), p.join(root.path, 'unplugged-drive')],
        index: index,
        artDir: art.path,
        extensions: supportedExtensions,
        minDurationMs: minDurationMs,
        force: false,
        sendPort: port.sendPort,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await done.cancel();
      port.close();
      return messages;
    }

    test('survives corrupted files, falls back to file names and detects removals', () async {
      final music = Directory(p.join(root.path, 'music', 'Album'))..createSync(recursive: true);
      File(p.join(music.path, '02 - Some Band - Real Song.wav')).writeAsBytesSync(wav(3));
      final random = Random(1);
      File(p.join(music.path, '01 - Broken Artist - Broken.mp3'))
          .writeAsBytesSync(List.generate(4096, (_) => random.nextInt(256)));
      File(p.join(music.path, 'cover.txt')).writeAsStringSync('not audio');
      // Hidden by .nomedia, as on Android.
      final hidden = Directory(p.join(root.path, 'music', 'Ringtones'))..createSync();
      File(p.join(hidden.path, '.nomedia')).writeAsStringSync('');
      File(p.join(hidden.path, 'ring.wav')).writeAsBytesSync(wav(1));

      final ghostPath = p.join(root.path, 'music', 'Album', 'deleted.mp3');
      final offlinePath = p.join(root.path, 'unplugged-drive', 'kept.mp3');
      const info = IndexedFile(id: 1, fileModifiedMs: 0, fileSize: 1, hasArt: false, durationMs: 1000);

      final messages = await run({ghostPath: info, offlinePath: info});
      final tracks = messages.whereType<ScanBatchMessage>().expand((b) => b.tracks).toList();
      final done = messages.whereType<ScanDoneMessage>().single;

      expect(tracks.length, 2);
      final broken = tracks.firstWhere((t) => t.path.endsWith('Broken.mp3'));
      expect(broken.title, 'Broken');
      expect(broken.artist, 'Broken Artist');
      expect(broken.trackNumber, 1);
      final real = tracks.firstWhere((t) => t.path.endsWith('.wav'));
      expect(real.durationMs, inInclusiveRange(2900, 3100));
      expect(done.added, 2);
      // Missing file is removed; files on an unreadable root are kept.
      expect(done.removedPaths, [ghostPath]);
      expect(done.unreadableRoots.single, endsWith('unplugged-drive'));
    });

    test('skips unchanged files and honours the minimum duration', () async {
      final music = Directory(p.join(root.path, 'music'))..createSync(recursive: true);
      final file = File(p.join(music.path, 'song.wav'))..writeAsBytesSync(wav(2));
      final stat = file.statSync();
      final unchanged = await run({
        file.path: IndexedFile(
          id: 1,
          fileModifiedMs: stat.modified.millisecondsSinceEpoch,
          fileSize: stat.size,
          hasArt: false,
          durationMs: 2000,
        ),
      });
      expect(unchanged.whereType<ScanBatchMessage>(), isEmpty);
      expect(unchanged.whereType<ScanDoneMessage>().single.removedPaths, isEmpty);

      final tooShort = await run(const {}, minDurationMs: 10000);
      expect(tooShort.whereType<ScanBatchMessage>(), isEmpty);
    });
  });
}
