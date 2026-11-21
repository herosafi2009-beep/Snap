import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_nav.dart';
import '../../data/models/track.dart';
import '../../data/providers.dart';
import '../../data/repositories/history_repository.dart';
import '../library/library_logic.dart';
import '../library/library_providers.dart';
import '../playlists/playlist_providers.dart';
import '../playlists/smart_playlists.dart';

final recentPlaysProvider = StreamProvider<List<RecentPlay>>((ref) {
  return ref.watch(historyRepositoryProvider).watchRecentPlays(limit: 40);
});

final recentSourcesProvider = StreamProvider<List<RecentPlay>>((ref) {
  return ref.watch(historyRepositoryProvider).watchRecentSources(limit: 12);
});

final recentlyPlayedTracksProvider = Provider<List<Track>>((ref) {
  final byId = ref.watch(trackByIdProvider);
  final plays = ref.watch(recentPlaysProvider).value ?? const [];
  return [for (final p in plays) ?byId[p.trackId]];
});

final quickPicksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(allTracksProvider);
  final stats = ref.watch(trackStatsProvider).value ?? const {};
  return SmartPlaylists.quickPicks(tracks, stats, count: 24);
});

final mostPlayedTracksProvider = Provider<List<Track>>((ref) {
  return ref.watch(smartPlaylistProvider(SmartPlaylistKind.mostPlayed)).take(20).toList();
});

/// Something the user can resume: an album, playlist, artist...
class PlaySourceView {
  const PlaySourceView({
    required this.source,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tracks,
    required this.artPaths,
    this.coverPath,
    required this.open,
  });

  final String source;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Track> tracks;
  final List<String> artPaths;
  final String? coverPath;
  final void Function(BuildContext context) open;
}

final continueListeningProvider = Provider<List<PlaySourceView>>((ref) {
  final sources = ref.watch(recentSourcesProvider).value ?? const [];
  final views = <PlaySourceView>[];
  for (final s in sources) {
    final view = resolveSource(ref, s.source!);
    if (view != null && view.tracks.isNotEmpty) views.add(view);
  }
  return views;
});

List<String> _art(List<Track> tracks) => tracks.map((t) => t.artPath).whereType<String>().toSet().take(4).toList();

PlaySourceView? resolveSource(Ref ref, String source) {
  final sep = source.indexOf(':');
  if (sep < 0) return null;
  final kind = source.substring(0, sep);
  final value = source.substring(sep + 1);
  switch (kind) {
    case 'album':
      final album = ref.watch(albumByKeyProvider)[value];
      if (album == null) return null;
      return PlaySourceView(
        source: source,
        title: album.title,
        subtitle: album.artist,
        icon: Icons.album_rounded,
        tracks: album.tracks,
        artPaths: [?album.artPath],
        open: (c) => AppNav.album(c, value),
      );
    case 'artist':
      final artist = ref.watch(artistByKeyProvider)[value];
      if (artist == null) return null;
      return PlaySourceView(
        source: source,
        title: artist.name,
        subtitle: 'Artist',
        icon: Icons.person_rounded,
        tracks: artist.tracks,
        artPaths: [?artist.artPath],
        open: (c) => AppNav.artist(c, value),
      );
    case 'playlist':
      final id = int.tryParse(value) ?? -1;
      final view = ref.watch(playlistViewProvider(id));
      if (view == null) return null;
      return PlaySourceView(
        source: source,
        title: view.playlist.name,
        subtitle: 'Playlist',
        icon: Icons.queue_music_rounded,
        tracks: view.tracks,
        artPaths: view.artPaths,
        coverPath: view.playlist.coverPath,
        open: (c) => AppNav.playlist(c, id),
      );
    case 'smart':
      final k = SmartPlaylistKind.values.firstWhereOrNull((k) => k.name == value);
      if (k == null) return null;
      final tracks = ref.watch(smartPlaylistProvider(k));
      return PlaySourceView(
        source: source,
        title: k.info.title,
        subtitle: 'Smart playlist',
        icon: k.info.icon,
        tracks: tracks,
        artPaths: _art(tracks),
        open: (c) => AppNav.smart(c, value),
      );
    case 'genre':
      final genre = ref.watch(genresProvider).firstWhereOrNull((g) => g.key == value);
      if (genre == null) return null;
      return PlaySourceView(
        source: source,
        title: genre.name,
        subtitle: 'Genre',
        icon: Icons.category_rounded,
        tracks: genre.tracks,
        artPaths: genre.artPaths,
        open: (c) => AppNav.genre(c, value),
      );
    case 'folder':
      final node = LibraryLogic.findFolder(ref.watch(folderTreeProvider), value);
      if (node == null) return null;
      return PlaySourceView(
        source: source,
        title: node.name,
        subtitle: 'Folder',
        icon: Icons.folder_rounded,
        tracks: node.tracks,
        artPaths: _art(node.tracks),
        open: (c) => AppNav.folder(c, value),
      );
  }
  return null;
}
