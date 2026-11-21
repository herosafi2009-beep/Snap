import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../../data/models/scanned_track.dart';

/// Formats ExoPlayer can decode on Android.
const supportedExtensions = {'.mp3', '.flac', '.wav', '.m4a', '.aac', '.ogg', '.oga', '.opus', '.aif', '.aiff'};

class ScanRequest {
  const ScanRequest({
    required this.roots,
    required this.index,
    required this.artDir,
    required this.extensions,
    required this.minDurationMs,
    required this.force,
    required this.sendPort,
  });

  final List<String> roots;
  final Map<String, IndexedFile> index;
  final String artDir;
  final Set<String> extensions;
  final int minDurationMs;
  final bool force;
  final SendPort sendPort;
}

sealed class ScanMessage {
  const ScanMessage();
}

class ScanProgressMessage extends ScanMessage {
  const ScanProgressMessage({required this.discovering, required this.processed, required this.total, this.current});
  final bool discovering;
  final int processed;
  final int total;
  final String? current;
}

class ScanBatchMessage extends ScanMessage {
  const ScanBatchMessage(this.tracks);
  final List<ScannedTrack> tracks;
}

class ScanDoneMessage extends ScanMessage {
  const ScanDoneMessage({
    required this.removedPaths,
    required this.added,
    required this.updated,
    required this.failed,
    required this.unreadableRoots,
  });
  final List<String> removedPaths;
  final int added;
  final int updated;
  final int failed;
  final List<String> unreadableRoots;
}

/// Isolate entry point. Walks the music folders, reads tags of new or changed
/// files and streams results back in batches. A broken file only ever affects
/// itself: every file is read inside its own try/catch.
Future<void> scanLibraryIsolate(ScanRequest request) async {
  final send = request.sendPort;
  final artDir = Directory(request.artDir);
  if (!artDir.existsSync()) artDir.createSync(recursive: true);

  // 1. Discover files.
  final files = <String, FileStat>{};
  final unreadableRoots = <String>[];
  final readableRoots = <String>[];
  for (final root in request.roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      unreadableRoots.add(root);
      continue;
    }
    try {
      dir.listSync(followLinks: false);
      readableRoots.add(root);
    } catch (_) {
      unreadableRoots.add(root);
      continue;
    }
    _walk(dir, request.extensions, files, (count) {
      if (count % 200 == 0) {
        send.send(ScanProgressMessage(discovering: true, processed: count, total: 0));
      }
    });
  }

  // 2. Read metadata for new / modified files.
  final paths = files.keys.toList()..sort();
  final total = paths.length;
  final batch = <ScannedTrack>[];
  final folderArtCache = <String, String?>{};
  final found = <String>{};
  var processed = 0;
  var added = 0;
  var updated = 0;
  var failed = 0;
  var lastProgress = DateTime.now();

  for (final path in paths) {
    processed++;
    final stat = files[path]!;
    final known = request.index[path];
    final modifiedMs = stat.modified.millisecondsSinceEpoch;
    final unchanged = !request.force &&
        known != null &&
        (known.fileModifiedMs ~/ 1000) == (modifiedMs ~/ 1000) &&
        known.fileSize == stat.size;

    if (unchanged) {
      if (known.durationMs == 0 || known.durationMs >= request.minDurationMs) found.add(path);
    } else {
      try {
        final scanned = readTrack(path, stat, artDir.path, folderArtCache);
        if (scanned.durationMs == 0 || scanned.durationMs >= request.minDurationMs) {
          batch.add(scanned);
          found.add(path);
          known == null ? added++ : updated++;
        }
      } catch (_) {
        failed++;
      }
    }

    if (batch.length >= 400) {
      send.send(ScanBatchMessage(List.of(batch)));
      batch.clear();
    }
    final now = DateTime.now();
    if (now.difference(lastProgress).inMilliseconds > 120 || processed == total) {
      lastProgress = now;
      send.send(ScanProgressMessage(discovering: false, processed: processed, total: total, current: path));
    }
  }
  if (batch.isNotEmpty) send.send(ScanBatchMessage(List.of(batch)));

  // 3. Work out removals. Files under a root that could not be read (e.g. an
  // unplugged drive or revoked permission) are kept rather than wiped.
  final removed = <String>[];
  for (final path in request.index.keys) {
    if (found.contains(path)) continue;
    final underUnreadable = unreadableRoots.any((r) => p.isWithin(r, path));
    final underReadable = readableRoots.any((r) => p.isWithin(r, path));
    if (underUnreadable && !underReadable) continue;
    removed.add(path);
  }

  send.send(ScanDoneMessage(
    removedPaths: removed,
    added: added,
    updated: updated,
    failed: failed,
    unreadableRoots: unreadableRoots,
  ));
}

void _walk(Directory dir, Set<String> extensions, Map<String, FileStat> out, void Function(int) onFile) {
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(followLinks: false);
  } catch (_) {
    return; // Permission denied or vanished; skip this branch.
  }
  // Android convention: folders with a .nomedia file are not media libraries.
  if (entries.any((e) => p.basename(e.path) == '.nomedia')) return;
  for (final entity in entries) {
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    if (entity is Directory) {
      _walk(entity, extensions, out, onFile);
    } else if (entity is File && extensions.contains(p.extension(name).toLowerCase())) {
      try {
        final stat = entity.statSync();
        if (stat.size > 0) {
          out[entity.path] = stat;
          onFile(out.length);
        }
      } catch (_) {}
    }
  }
}

/// Reads one file. Missing tags fall back to information in the file name.
ScannedTrack readTrack(String path, FileStat stat, String artDir, Map<String, String?> folderArtCache) {
  final folder = p.dirname(path);
  final fromName = parseFileName(p.basenameWithoutExtension(path));

  String? title;
  String? artist;
  String? album;
  String? albumArtist;
  List<String> genres = const [];
  int? year;
  int? trackNumber;
  int? discNumber;
  Duration? duration;
  List<Picture> pictures = const [];

  final file = File(path);
  try {
    if (p.extension(path).toLowerCase() == '.mp3') {
      // The generic reader folds TPE2 (album artist) into the track artist,
      // so MP3s are read with the dedicated parser to keep them apart.
      final reader = file.openSync();
      try {
        final m = MP3Parser(fetchImage: true).parse(reader);
        title = m.songName;
        artist = m.leadPerformer ?? m.originalArtist ?? m.bandOrOrchestra;
        albumArtist = m.bandOrOrchestra;
        album = m.album;
        genres = m.genres;
        year = m.year ?? m.originalReleaseYear;
        trackNumber = m.trackNumber;
        discNumber = m.discNumber;
        duration = m.duration;
        pictures = m.pictures;
      } finally {
        reader.closeSync();
      }
    } else {
      final m = readMetadata(file, getImage: true);
      title = m.title;
      artist = m.artist;
      albumArtist = m.albumArtist;
      album = m.album;
      genres = m.genres;
      year = m.year?.year;
      trackNumber = m.trackNumber;
      discNumber = m.discNumber;
      duration = m.duration;
      pictures = m.pictures;
    }
  } catch (_) {
    // Unsupported container or corrupted tags: keep the file-name fallback.
  }

  String? artPath;
  try {
    artPath = _saveEmbeddedArt(pictures, artDir) ?? _folderArt(folder, folderArtCache);
  } catch (_) {
    artPath = null;
  }

  return ScannedTrack(
    path: path,
    folder: folder,
    title: _clean(title) ?? fromName.title,
    artist: _clean(artist) ?? fromName.artist ?? '',
    album: _clean(album) ?? '',
    albumArtist: _clean(albumArtist) ?? '',
    genre: genres.map((g) => g.trim()).where((g) => g.isNotEmpty).toSet().join('; '),
    year: (year != null && year > 0 && year < 10000) ? year : null,
    trackNumber: (trackNumber != null && trackNumber > 0) ? trackNumber : fromName.track,
    discNumber: (discNumber != null && discNumber > 0) ? discNumber : null,
    durationMs: (duration?.inMilliseconds ?? 0).clamp(0, 1 << 40),
    artPath: artPath,
    fileSize: stat.size,
    fileModifiedMs: stat.modified.millisecondsSinceEpoch,
  );
}

String? _clean(String? value) {
  if (value == null) return null;
  final v = value.replaceAll(' ', '; ').trim();
  return v.isEmpty ? null : v;
}

/// "01 - Artist - Title", "Artist - Title", "01. Title", "01 Title".
({String title, String? artist, int? track}) parseFileName(String name) {
  var rest = name.replaceAll('_', ' ').trim();
  int? track;
  final trackMatch = RegExp(r'^(\d{1,3})\s*(?:[-.)]\s*|\s+)(.+)$').firstMatch(rest);
  if (trackMatch != null) {
    track = int.tryParse(trackMatch.group(1)!);
    rest = trackMatch.group(2)!.trim();
  }
  final parts = rest.split(RegExp(r'\s+-\s+'));
  if (parts.length >= 2 && parts.first.isNotEmpty) {
    return (title: parts.sublist(1).join(' - ').trim(), artist: parts.first.trim(), track: track);
  }
  return (title: rest.isEmpty ? name : rest, artist: null, track: track);
}

String? _saveEmbeddedArt(List<Picture> pictures, String artDir) {
  if (pictures.isEmpty) return null;
  final picture = pictures.firstWhere(
    (pic) => pic.pictureType == PictureType.coverFront,
    orElse: () => pictures.first,
  );
  final bytes = picture.bytes;
  if (bytes.length < 64) return null;
  final ext = _imageExtension(bytes, picture.mimetype);
  if (ext == null) return null;
  final file = File(p.join(artDir, '${hashBytes(bytes)}$ext'));
  if (!file.existsSync()) {
    // Write to a temp file first so a crash never leaves a truncated image.
    final tmp = File('${file.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(file.path);
  }
  return file.path;
}

String? _folderArt(String folder, Map<String, String?> cache) {
  return cache.putIfAbsent(folder, () {
    const names = ['cover', 'folder', 'front', 'album', 'albumart'];
    try {
      for (final entity in Directory(folder).listSync(followLinks: false)) {
        if (entity is! File) continue;
        final base = p.basenameWithoutExtension(entity.path).toLowerCase();
        final ext = p.extension(entity.path).toLowerCase();
        if (names.contains(base) && (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp')) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
  });
}

String? _imageExtension(Uint8List bytes, String mime) {
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return '.jpg';
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return '.png';
  if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) return '.webp';
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return '.gif';
  if (mime.contains('png')) return '.png';
  if (mime.contains('jp')) return '.jpg';
  return null;
}

/// Content hash (two independent FNV-1a 32-bit passes) used to de-duplicate
/// identical cover images shared by every track of an album.
String hashBytes(Uint8List bytes) {
  var h1 = 0x811c9dc5;
  var h2 = 0x050c5d1f;
  for (var i = 0; i < bytes.length; i++) {
    h1 = ((h1 ^ bytes[i]) * 0x01000193) & 0xFFFFFFFF;
    h2 = ((h2 ^ bytes[bytes.length - 1 - i]) * 0x01000193) & 0xFFFFFFFF;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}${bytes.length.toRadixString(16)}';
}
