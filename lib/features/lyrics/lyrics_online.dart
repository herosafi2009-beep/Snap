import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/track.dart';

/// What the online lookup found for a song.
class OnlineLyrics {
  const OnlineLyrics({this.raw, this.instrumental = false});

  /// LRC text when synced lyrics exist, else plain text; null if none.
  final String? raw;
  final bool instrumental;

  bool get found => raw != null || instrumental;
}

/// The song as the lyrics search sees it: title, artist and album cleaned of
/// "feat." credits, file-name prefixes and remaster notes, plus the version
/// words (live, remix, acoustic...) that must match on both sides.
class LyricsQuery {
  LyricsQuery._({
    required this.title,
    required this.artist,
    required this.searchArtist,
    required this.album,
    required this.seconds,
    required this.versions,
  });

  factory LyricsQuery.of(Track track) {
    var title = track.title.trim();
    var artist = track.artist.trim();
    // File-name style titles: "MF DOOM - Doomsday (feat. Pebbles)".
    final dash = title.indexOf(' - ');
    if (dash > 0) {
      final before = title.substring(0, dash).trim();
      if (artist.isEmpty || LyricsMatcher.sameArtist(before, artist)) {
        if (artist.isEmpty) artist = before;
        title = title.substring(dash + 3).trim();
      }
    }
    return LyricsQuery._(
      title: LyricsMatcher.cleanTitle(title),
      artist: LyricsMatcher.primaryArtist(artist),
      searchArtist: artist.replaceAll(LyricsMatcher._featTail, '').trim(),
      album: LyricsMatcher.cleanTitle(track.album.trim()),
      seconds: track.durationMs > 0 ? track.durationMs / 1000 : null,
      versions: LyricsMatcher.versionWords(track.title),
    );
  }

  final String title;
  /// First credited artist, used for matching.
  final String artist;

  /// The full artist credit without "feat.", sent to the search.
  final String searchArtist;
  final String album;
  final double? seconds;
  final Set<String> versions;

  bool get usable => title.isNotEmpty && artist.isNotEmpty && !LyricsMatcher.isUnknown(artist);

  /// Changes whenever anything the search uses changes.
  String get cacheKey => '$title|$artist|$album|${seconds?.round()}|${versions.join(',')}';
}

/// Decides whether a lyrics record really belongs to a song. Pure functions,
/// so the rules are easy to test.
class LyricsMatcher {
  /// Words that mean a different recording, with different or no lyrics.
  static const _versionWords = {
    'live',
    'remix',
    'acoustic',
    'instrumental',
    'karaoke',
    'demo',
    'unplugged',
    'reprise',
    'cover',
    'sped up',
    'slowed',
    'nightcore',
    'a cappella',
    'acapella',
  };

  // "(feat. X)", "[with X]", or a trailing "feat. X" with no brackets. A
  // bare "with" is left alone: it is part of titles like "Dance With Me".
  static final _feat = RegExp(r'\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s+[^\)\]]*[\)\]]', caseSensitive: false);
  static final _featTail = RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);
  static final _brackets = RegExp(r'\s*[\(\[][^\)\]]*[\)\]]');
  static final _space = RegExp(r'\s+');
  static final _nonWord = RegExp(r'[^\p{L}\p{N} ]', unicode: true);

  /// Version words in [text] (bracketed or after a dash), lower case.
  static Set<String> versionWords(String text) {
    final lower = text.toLowerCase();
    return {
      for (final w in _versionWords)
        if (RegExp('(^|[^a-z])${RegExp.escape(w)}([^a-z]|\$)').hasMatch(lower)) w,
    };
  }

  /// The title without credits or bracketed notes ("Remastered 2011").
  static String cleanTitle(String title) {
    var t = title.replaceAll(_feat, ' ').replaceAll(_featTail, '');
    t = t.replaceAll(_brackets, ' ');
    // " - Remastered 2009", " - Radio Edit": notes that do not change lyrics.
    final dash = t.indexOf(' - ');
    if (dash > 0) {
      final tail = t.substring(dash + 3).toLowerCase();
      if (RegExp(r'remaster|edit|version|mono|stereo|single|bonus|deluxe|\d{4}').hasMatch(tail) &&
          versionWords(tail).isEmpty) {
        t = t.substring(0, dash);
      }
    }
    return t.replaceAll(_space, ' ').trim();
  }

  /// First credited artist: "A, B & C feat. D" is A.
  static String primaryArtist(String artist) {
    final first = artist.split(RegExp(r'\s*(,|;|&| x | feat\.? | ft\.? | featuring | and |/)\s*', caseSensitive: false)).first;
    return first.trim();
  }

  static bool isUnknown(String artist) {
    final a = normalize(artist);
    return a.isEmpty || a == 'unknown artist' || a == 'unknown' || a == 'various artists';
  }

  /// Lower case, accents kept, punctuation and "the " removed.
  static String normalize(String s) {
    var t = s.toLowerCase().replaceAll('&', ' and ').replaceAll(_nonWord, ' ').replaceAll(_space, ' ').trim();
    if (t.startsWith('the ')) t = t.substring(4);
    return t;
  }

  static bool sameArtist(String a, String b) {
    final x = normalize(primaryArtist(a));
    final y = normalize(primaryArtist(b));
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.replaceAll(' ', '') == y.replaceAll(' ', '');
  }

  static bool sameTitle(String a, String b) {
    final x = normalize(cleanTitle(a));
    final y = normalize(cleanTitle(b));
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.replaceAll(' ', '') == y.replaceAll(' ', '');
  }

  /// A score for [record] (an LRCLIB result) against [q], or null when it is
  /// a different song, artist or version. Higher is better.
  static double? score(LyricsQuery q, Map<String, dynamic> record) {
    final title = record['trackName'] as String? ?? record['name'] as String? ?? '';
    final artist = record['artistName'] as String? ?? '';
    final album = record['albumName'] as String? ?? '';
    final duration = (record['duration'] as num?)?.toDouble();
    if (!sameTitle(q.title, title)) return null;
    // Every credited artist on the record is checked, so "A & B" matches a
    // file tagged just "B" too.
    final credited = artist.split(RegExp(r'\s*(,|;|&| x | feat\.? | ft\.? | featuring | and |/)\s*', caseSensitive: false));
    if (!credited.any((a) => sameArtist(a, q.artist))) return null;
    // Same recording only: a remix, live take or cover is a different song
    // as far as lyrics timing (and often wording) goes.
    if (!_sameVersions(q.versions, versionWords('$title $album'))) return null;
    var s = 1.0;
    if (q.seconds != null && duration != null && duration > 0) {
      final off = (q.seconds! - duration).abs();
      if (off > 4) return null;
      s += 1 - off / 4;
    }
    if (q.album.isNotEmpty && normalize(album) == normalize(q.album)) s += 0.5;
    if ((record['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false) s += 0.75;
    return s;
  }

  static bool _sameVersions(Set<String> mine, Set<String> theirs) {
    // Album names often say "Live at..." for a whole album; the local title
    // decides. A version word only on their side is a different recording.
    for (final w in theirs) {
      if (!mine.contains(w)) return false;
    }
    for (final w in mine) {
      if (!theirs.contains(w)) return false;
    }
    return true;
  }

  /// The best acceptable record, or null.
  static Map<String, dynamic>? best(LyricsQuery q, Iterable<Map<String, dynamic>> records) {
    Map<String, dynamic>? top;
    var topScore = -1.0;
    for (final r in records) {
      final hasText = ((r['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false) ||
          ((r['plainLyrics'] as String?)?.trim().isNotEmpty ?? false) ||
          r['instrumental'] == true;
      if (!hasText) continue;
      final s = score(q, r);
      if (s != null && s > topScore) {
        top = r;
        topScore = s;
      }
    }
    return top;
  }
}

/// Looks songs up on LRCLIB (lrclib.net), a free, open lyrics database with
/// time-synced lyrics. Only the song's title, artist, album and length are
/// sent, and only when the lyrics view is opened for a song with no lyrics
/// of its own. Answers are cached on the device, misses for a week.
class OnlineLyricsClient {
  OnlineLyricsClient(this._cacheDir);

  final Directory _cacheDir;
  static const _host = 'lrclib.net';
  static const _missTtl = Duration(days: 7);
  final _pending = <String, Future<OnlineLyrics>>{};

  Future<OnlineLyrics> find(Track track) {
    final q = LyricsQuery.of(track);
    if (!q.usable) return Future.value(const OnlineLyrics());
    final key = '${track.id}|${q.cacheKey}';
    return _pending.putIfAbsent(key, () async {
      try {
        final cached = await _readCache(track.id, q);
        if (cached != null) return cached;
        final result = await _lookup(q);
        if (result != null) await _writeCache(track.id, q, result);
        return result ?? const OnlineLyrics();
      } finally {
        _pending.remove(key);
      }
    });
  }

  /// Null means "could not ask" (offline, server error): not cached, so it
  /// is tried again next time.
  Future<OnlineLyrics?> _lookup(LyricsQuery q) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = 'Snap music player (lyrics lookup)';
    try {
      // 1. Exact lookup: title, artist, album and length all given.
      if (q.seconds != null) {
        final exact = await _get(client, '/api/get', {
          'track_name': q.title,
          'artist_name': q.searchArtist,
          if (q.album.isNotEmpty) 'album_name': q.album,
          'duration': q.seconds!.round().toString(),
        });
        if (exact is Map<String, dynamic>) {
          final ok = LyricsMatcher.best(q, [exact]);
          if (ok != null) return _toResult(ok);
        }
      }
      // 2. Search by title and artist, then keep only a true match.
      final hits = await _get(client, '/api/search', {'track_name': q.title, 'artist_name': q.searchArtist});
      if (hits == null) return null;
      final list = hits is List ? hits.whereType<Map<String, dynamic>>() : const <Map<String, dynamic>>[];
      final ok = LyricsMatcher.best(q, list);
      return ok == null ? const OnlineLyrics() : _toResult(ok);
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on HttpException {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Decoded JSON, `false` for "not found", or null for a failure.
  Future<Object?> _get(HttpClient client, String path, Map<String, String> query) async {
    final uri = Uri.https(_host, path, query);
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return false;
    if (response.statusCode != 200) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  OnlineLyrics _toResult(Map<String, dynamic> r) {
    final synced = (r['syncedLyrics'] as String?)?.trim();
    final plain = (r['plainLyrics'] as String?)?.trim();
    if (synced != null && synced.isNotEmpty) return OnlineLyrics(raw: synced);
    if (plain != null && plain.isNotEmpty) return OnlineLyrics(raw: plain);
    return OnlineLyrics(instrumental: r['instrumental'] == true);
  }

  File _file(int trackId) => File(p.join(_cacheDir.path, '$trackId.json'));

  Future<OnlineLyrics?> _readCache(int trackId, LyricsQuery q) async {
    try {
      final file = _file(trackId);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['key'] != q.cacheKey) return null;
      final raw = json['raw'] as String?;
      final instrumental = json['instrumental'] == true;
      if (raw == null && !instrumental) {
        final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int? ?? 0);
        if (DateTime.now().difference(at) > _missTtl) return null;
      }
      return OnlineLyrics(raw: raw, instrumental: instrumental);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(int trackId, LyricsQuery q, OnlineLyrics r) async {
    try {
      await _cacheDir.create(recursive: true);
      await _file(trackId).writeAsString(jsonEncode({
        'key': q.cacheKey,
        'raw': r.raw,
        'instrumental': r.instrumental,
        'at': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  /// Forgets the cached answer for a song, so the next view asks again.
  Future<void> forget(int trackId) async {
    try {
      final f = _file(trackId);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
