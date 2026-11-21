import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/routing/app_nav.dart';
import '../../core/utils/format.dart';
import '../../data/models/library_groups.dart';
import '../../data/models/track.dart';
import '../../widgets/artwork.dart';
import '../../widgets/collection_page.dart';
import '../../widgets/common.dart';
import '../../widgets/media_card.dart';
import '../actions/media_actions.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_providers.dart';
import '../playlists/smart_playlists.dart';
import '../settings/settings_model.dart';
import '../../widgets/motion.dart';
import 'folder_sort.dart';
import 'library_logic.dart';
import 'library_providers.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumKey});
  final String albumKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(libraryLoadedProvider)) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final album = ref.watch(albumByKeyProvider)[albumKey];
    if (album == null) return const NotFoundPage(what: 'Album');
    final discs = album.tracks.map((t) => t.discNumber ?? 1).toSet();
    final meta = [
      ?album.year?.toString(),
      Format.songs(album.tracks.length),
      Format.totalTime(album.durationMs),
      if (discs.length > 1) '${discs.length} discs',
    ].join(' · ');

    return CollectionPage(
      label: 'Album',
      title: album.title,
      subtitle: album.artist,
      onSubtitleTap: () => AppNav.artist(context, album.artist),
      meta: meta,
      artwork: Artwork(path: album.artPath, placeholderKey: album.key, radius: 28, icon: Icons.album_rounded),
      tintArtPath: album.artPath,
      tracks: album.tracks,
      source: 'album:${album.key}',
      numbered: true,
      headerActions: [_MoreButton(onPressed: (pos) => _albumMenu(context, ref, album, pos))],
    );
  }
}

void _albumMenu(BuildContext context, WidgetRef ref, Album album, Offset? position) {
  showCollectionMenu(
    context,
    ref,
    title: album.title,
    subtitle: album.artist,
    tracks: album.tracks,
    source: 'album:${album.key}',
    art: [?album.artPath],
    position: position,
    extra: [
      MenuAction(Icons.person_rounded, 'View artist', () => AppNav.artist(context, album.artist)),
      MenuAction(Icons.hide_source_rounded, 'Remove album from library', () => removeFromLibrary(ref, album.tracks)),
    ],
  );
}

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artistKey});
  final String artistKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(libraryLoadedProvider)) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final artist = ref.watch(artistByKeyProvider)[artistKey];
    if (artist == null) return const NotFoundPage(what: 'Artist');
    final albums = LibraryLogic.groupAlbums(artist.tracks)..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    final topSongs = [...artist.tracks]..sort((a, b) => b.playCount.compareTo(a.playCount));
    final player = ref.read(playerControllerProvider.notifier);
    final pad = Breakpoints.pagePadding(context);

    return CollectionPage(
      label: 'Artist',
      title: artist.name,
      meta: '${Format.count(albums.length, 'album')} · ${Format.songs(artist.tracks.length)} · ${Format.totalTime(artist.durationMs)}',
      artwork: Artwork(path: artist.artPath, placeholderKey: artist.key, shape: BoxShape.circle, icon: Icons.person_rounded),
      circularArt: true,
      tintArtPath: artist.artPath,
      tracks: artist.tracks,
      source: 'artist:${artist.key}',
      headerActions: [
        _MoreButton(
          onPressed: (pos) => showCollectionMenu(
            context,
            ref,
            title: artist.name,
            tracks: artist.tracks,
            source: 'artist:${artist.key}',
            art: [?artist.artPath],
            position: pos,
          ),
        ),
      ],
      slivers: [
        if (topSongs.first.playCount > 0) ...[
          SliverToBoxAdapter(child: SectionHeader(title: 'Popular', padding: EdgeInsets.fromLTRB(pad, 16, pad, 8))),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad - 8),
            sliver: SliverList.list(children: [
              for (final t in topSongs.where((t) => t.playCount > 0).take(5))
                _PopularTile(track: t, onTap: () => player.playTracks(topSongs, startIndex: topSongs.indexOf(t))),
            ]),
          ),
        ],
        SliverToBoxAdapter(child: SectionHeader(title: 'Albums', padding: EdgeInsets.fromLTRB(pad, 20, pad, 12))),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              itemCount: albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final album = albums[i];
                return MediaCard(
                  width: 180,
                  artwork: Artwork(path: album.artPath, placeholderKey: album.key, radius: 20, icon: Icons.album_rounded),
                  title: album.title,
                  subtitle: album.year?.toString() ?? Format.songs(album.tracks.length),
                  onTap: () => AppNav.album(context, album.key),
                  onPlay: () => player.playTracks(album.tracks, source: 'album:${album.key}'),
                  onMenu: (pos) => _albumMenu(context, ref, album, pos),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: SectionHeader(title: 'All songs', padding: EdgeInsets.fromLTRB(pad, 16, pad, 8))),
      ],
    );
  }
}

class _PopularTile extends StatelessWidget {
  const _PopularTile({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: SizedBox.square(dimension: 44, child: Artwork(path: track.artPath, placeholderKey: track.albumKey, radius: 10)),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(Format.count(track.playCount, 'play')),
      trailing: Text(Format.durationMs(track.durationMs), style: theme.textTheme.bodySmall),
    );
  }
}

class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.genreKey});
  final String genreKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(libraryLoadedProvider)) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final genre = ref.watch(genresProvider).firstWhereOrNull((g) => g.key == genreKey);
    if (genre == null) return const NotFoundPage(what: 'Genre');
    final tracks = LibraryLogic.sortTracks(genre.tracks, const SortSpec(SortField.artist, true));
    final artists = tracks.map((t) => t.displayArtist).toSet();
    return CollectionPage(
      label: 'Genre',
      title: genre.name,
      meta: '${Format.songs(tracks.length)} · ${Format.count(artists.length, 'artist')}',
      artwork: CollageArtwork(paths: genre.artPaths, placeholderKey: genre.key, radius: 28, icon: Icons.category_rounded),
      tintArtPath: genre.artPaths.firstOrNull,
      tracks: tracks,
      source: 'genre:${genre.key}',
      headerActions: [
        _MoreButton(
          onPressed: (pos) => showCollectionMenu(context, ref,
              title: genre.name, tracks: tracks, source: 'genre:${genre.key}', art: genre.artPaths, position: pos),
        ),
      ],
    );
  }
}

class FolderScreen extends ConsumerWidget {
  const FolderScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(libraryLoadedProvider)) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final node = LibraryLogic.findFolder(ref.watch(folderTreeProvider), path);
    if (node == null) return const NotFoundPage(what: 'Folder');
    final pad = Breakpoints.pagePadding(context);
    final sort = ref.watch(folderSortProvider.select((m) => m[node.path] ?? FolderSortOption.fallback));
    // Sorting only changes the displayed / played order, never the files.
    final tracks = sort.apply(node.tracks.isEmpty ? _collect(node) : node.tracks);

    // Clean header: just the folder name, the song count and actions.
    return CollectionPage(
      title: node.name,
      meta: [
        if (node.subfolders.isNotEmpty) Format.count(node.subfolders.length, 'folder'),
        Format.songs(node.totalTracks),
      ].join(' · '),
      tracks: tracks,
      source: 'folder:${node.path}',
      headerActions: [
        Builder(
          builder: (context) => SpringPress(
            pressedScale: 0.94,
            child: OutlinedButton.icon(
              onPressed: () => showFolderSortSheet(context, ref, node.path),
              icon: const Icon(Icons.sort_rounded),
              label: Text(sort == FolderSortOption.fallback ? 'Sort' : sort.label),
            ),
          ),
        ),
      ],
      slivers: [
        if (node.subfolders.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad - 8),
            sliver: SliverList.list(children: [
              for (final sub in node.subfolders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FolderTile(
                    node: sub,
                    onTap: () => AppNav.folder(context, sub.path),
                    onMenu: (pos) => showCollectionMenu(context, ref,
                        title: sub.name,
                        subtitle: sub.path,
                        tracks: _collect(sub),
                        source: 'folder:${sub.path}',
                        position: pos),
                  ),
                ),
              if (node.tracks.isNotEmpty) const Divider(height: 24),
            ]),
          ),
      ],
    );
  }

  static List<Track> _collect(FolderNode node) => [...node.tracks, for (final s in node.subfolders) ..._collect(s)];
}

/// Folder row: a filled Material container so folders read as objects you can
/// open, rather than plain rows of text.
class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.node, required this.onTap, this.onMenu});
  final FolderNode node;
  final VoidCallback onTap;
  final void Function(Offset?)? onMenu;

  static String describe(FolderNode node) => [
        if (node.subfolders.isNotEmpty) Format.count(node.subfolders.length, 'folder'),
        Format.songs(node.totalTracks),
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMenu == null ? null : () => onMenu!(null),
        onSecondaryTapUp: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              FolderCoverCollage(
                covers: [for (final t in node.coverTracks) (t.artPath, t.albumKey)],
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      describe(node),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'More options',
                onPressed: onMenu == null ? null : () => onMenu!(null),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Folder as a card for the grid layout: the cover collage sits in its own
/// container with the name underneath.
class FolderCard extends StatelessWidget {
  const FolderCard({super.key, required this.node, required this.onTap, this.onMenu});
  final FolderNode node;
  final VoidCallback onTap;
  final void Function(Offset?)? onMenu;

  @override
  Widget build(BuildContext context) {
    return MediaCard(
      artwork: LayoutBuilder(
        builder: (context, c) => Center(
          child: FolderCoverCollage(
            covers: [for (final t in node.coverTracks) (t.artPath, t.albumKey)],
            size: c.biggest.shortestSide * 0.78,
          ),
        ),
      ),
      artworkBackground: Theme.of(context).colorScheme.surfaceContainerHigh,
      title: node.name,
      subtitle: FolderTile.describe(node),
      onTap: onTap,
      onMenu: onMenu ?? (_) {},
    );
  }
}

class SmartPlaylistScreen extends ConsumerWidget {
  const SmartPlaylistScreen({super.key, required this.kindName});
  final String kindName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = SmartPlaylistKind.values.firstWhereOrNull((k) => k.name == kindName);
    if (kind == null) return const NotFoundPage(what: 'Playlist');
    final info = kind.info;
    final tracks = ref.watch(smartPlaylistProvider(kind));
    final art = tracks.map((t) => t.artPath).whereType<String>().toSet().take(4).toList();
    return CollectionPage(
      label: 'Smart playlist',
      title: info.title,
      subtitle: info.subtitle,
      meta: '${Format.songs(tracks.length)} · ${Format.totalTime(tracks.fold(0, (a, t) => a + t.durationMs))} · Updates automatically',
      artwork: SmartPlaylistArt(info: info, artPaths: art),
      tintArtPath: art.firstOrNull,
      tracks: tracks,
      source: 'smart:${kind.name}',
      headerActions: [
        IconButton.outlined(
          tooltip: 'Save as playlist',
          onPressed: tracks.isEmpty ? null : () => showCreatePlaylistDialog(context, ref, tracks: tracks),
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      ],
      emptyState: EmptyState(
        compact: true,
        icon: info.icon,
        title: 'Nothing here yet',
        message: 'This playlist fills itself as you listen. Play some music and check back.',
      ),
    );
  }
}

/// Artwork for smart playlists: album collage with a tinted icon badge.
class SmartPlaylistArt extends StatelessWidget {
  const SmartPlaylistArt({super.key, required this.info, required this.artPaths, this.radius = 28});
  final SmartPlaylistInfo info;
  final List<String> artPaths;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = ColorScheme.fromSeed(seedColor: info.seed, brightness: brightness);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (artPaths.isNotEmpty)
            CollageArtwork(paths: artPaths, placeholderKey: info.title, radius: 0)
          else
            ColoredBox(color: scheme.primaryContainer),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.primary.withValues(alpha: 0.15), scheme.primary.withValues(alpha: 0.75)],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) => Padding(
              padding: EdgeInsets.all(c.maxWidth * 0.08),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(info.icon, color: scheme.onPrimary, size: c.maxWidth * 0.18),
                    if (c.maxWidth > 120)
                      Text(
                        info.title,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: c.maxWidth * 0.1,
                            ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onPressed});
  final void Function(Offset? position) onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: 'More options',
      onPressed: () {
        final box = context.findRenderObject() as RenderBox?;
        final pos = Breakpoints.isDesktop && box != null ? box.localToGlobal(box.size.center(Offset.zero)) : null;
        onPressed(pos);
      },
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}
