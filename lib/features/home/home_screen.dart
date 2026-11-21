import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/routing/app_nav.dart';
import '../../core/utils/format.dart';
import '../../data/models/track.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/media_card.dart';
import '../actions/media_actions.dart';
import '../library/collection_screens.dart';
import '../library/folder_flow.dart';
import '../library/library_providers.dart';
import '../library/scan_controller.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_providers.dart';
import '../playlists/smart_playlists.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_model.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(libraryLoadedProvider);
    final tracks = ref.watch(allTracksProvider);
    final scan = ref.watch(scanControllerProvider);
    final settings = ref.watch(settingsProvider);
    final pad = Breakpoints.pagePadding(context);
    final theme = Theme.of(context);
    final compact = Breakpoints.of(context).isCompact;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad - 8, 4),
      child: Row(
        children: [
          if (compact) ...[const AppLogo(size: 36, flush: true), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(Format.greeting(), style: theme.textTheme.headlineMedium)),
                if (tracks.isNotEmpty)
                  Text(
                    '${Format.songs(tracks.length)} · ${Format.totalTime(tracks.fold(0, (a, t) => a + t.durationMs))} of music',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (settings.showStatistics)
            IconButton(
              tooltip: 'Listening statistics',
              onPressed: () => AppNav.statistics(context),
              icon: const Icon(Icons.insights_rounded),
            ),
          if (compact)
            IconButton(
              tooltip: 'Search',
              onPressed: () => AppNav.search(context),
              icon: const Icon(Icons.search_rounded),
            ),
        ],
      ),
    );

    if (!loaded) {
      return Scaffold(
        body: SafeArea(
          child: ListView(children: [header, const SizedBox(height: 24), const TrackListSkeleton()]),
        ),
      );
    }

    if (tracks.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              header,
              Expanded(
                child: scan.running
                    ? const EmptyState(
                        icon: Icons.library_music_rounded,
                        title: 'Building your library',
                        message: 'Snap is reading your music. Songs will appear here as soon as they are found.',
                        action: SizedBox(width: 200, child: LinearProgressIndicator()),
                      )
                    : const EmptyState(
                        icon: Icons.library_music_rounded,
                        title: 'No music yet',
                        message: 'Choose a music folder to build your library.',
                        action: AddMusicButtons(),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    final sections = <Widget>[];
    for (final config in settings.homeSections.where((s) => s.visible)) {
      final widget = switch (config.section) {
        HomeSection.quickPicks => const _QuickPicks(),
        HomeSection.recentlyPlayed => settings.showRecentlyPlayed ? const _RecentlyPlayed() : null,
        HomeSection.continueListening => const _ContinueListening(),
        HomeSection.madeForYou => const _MadeForYou(),
        HomeSection.favorites => const _Favorites(),
        HomeSection.recentlyAdded => const _RecentlyAdded(),
        HomeSection.mostPlayed => const _MostPlayed(),
      };
      if (widget != null) sections.add(widget);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: header),
            SliverList.list(children: sections),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => AppNav.settingsPage(context, 'home'),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Customize home'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    this.subtitle,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 236,
    this.itemWidth = 160,
    this.onMore,
  });

  final String title;
  final String? subtitle;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final double height;
  final double itemWidth;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final pad = Breakpoints.pagePadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, subtitle: subtitle, onMore: onMore, padding: EdgeInsets.fromLTRB(pad, 28, pad - 8, 12)),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) => SizedBox(width: itemWidth, child: itemBuilder(context, i)),
          ),
        ),
      ],
    );
  }
}

class _QuickPicks extends ConsumerWidget {
  const _QuickPicks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(quickPicksProvider);
    if (picks.isEmpty) return const SizedBox.shrink();
    final player = ref.read(playerControllerProvider.notifier);
    const perColumn = 4;
    final columns = (picks.length / perColumn).ceil();
    final width = MediaQuery.sizeOf(context).width;
    final columnWidth = width < 600 ? width * 0.82 : 340.0;
    final theme = Theme.of(context);

    return _Shelf(
      title: 'Quick picks',
      subtitle: 'Start here',
      itemCount: columns,
      height: perColumn * 64.0,
      itemWidth: columnWidth,
      itemBuilder: (context, c) => Column(
        children: [
          for (var i = c * perColumn; i < (c + 1) * perColumn && i < picks.length; i++)
            SizedBox(
              height: 64,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => player.playTracks(picks, startIndex: i),
                onLongPress: () => showTrackMenu(context, ref, picks[i]),
                onSecondaryTapUp: (d) => showTrackMenu(context, ref, picks[i], position: d.globalPosition),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 52,
                      child: Artwork(path: picks[i].artPath, placeholderKey: picks[i].albumKey, radius: 12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(picks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                          Text(
                            picks[i].displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _trackCard(BuildContext context, WidgetRef ref, List<Track> list, int i, {String? source, String? subtitle}) {
  final t = list[i];
  final player = ref.read(playerControllerProvider.notifier);
  return MediaCard(
    artwork: Artwork(path: t.artPath, placeholderKey: t.albumKey, radius: 20),
    title: t.title,
    subtitle: subtitle ?? t.displayArtist,
    onTap: () => player.playTracks(list, startIndex: i, source: source),
    onPlay: () => player.playTracks(list, startIndex: i, source: source),
    onMenu: (pos) => showTrackMenu(context, ref, t, position: pos),
  );
}

class _RecentlyPlayed extends ConsumerWidget {
  const _RecentlyPlayed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyPlayedTracksProvider);
    if (recent.isEmpty) return const SizedBox.shrink();
    return _Shelf(
      title: 'Recently played',
      itemCount: recent.length,
      onMore: () => AppNav.smart(context, SmartPlaylistKind.recentlyPlayed.name),
      itemBuilder: (context, i) => _trackCard(context, ref, recent, i, source: 'smart:recentlyPlayed'),
    );
  }
}

class _ContinueListening extends ConsumerWidget {
  const _ContinueListening();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueListeningProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final player = ref.read(playerControllerProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    return _Shelf(
      title: 'Continue listening',
      itemCount: items.length,
      height: 112,
      itemWidth: width < 600 ? width * 0.78 : 320,
      itemBuilder: (context, i) {
        final item = items[i];
        return PressScale(
          child: Card(
            color: scheme.surfaceContainerHigh,
            child: InkWell(
              onTap: () => item.open(context),
              onSecondaryTapUp: (d) => showCollectionMenu(context, ref,
                  title: item.title, tracks: item.tracks, source: item.source, art: item.artPaths, position: d.globalPosition),
              onLongPress: () => showCollectionMenu(context, ref,
                  title: item.title, tracks: item.tracks, source: item.source, art: item.artPaths),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 112,
                    child: CollageArtwork(
                      paths: item.artPaths,
                      coverPath: item.coverPath,
                      placeholderKey: item.title,
                      radius: 0,
                      icon: item.icon,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                          Text(item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Play ${item.title}',
                    onPressed: () => player.playTracks(item.tracks, source: item.source),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MadeForYou extends ConsumerWidget {
  const _MadeForYou();

  static const kinds = [
    SmartPlaylistKind.recentlyAdded,
    SmartPlaylistKind.mostPlayed,
    SmartPlaylistKind.neverFinished,
    SmartPlaylistKind.lateNight,
    SmartPlaylistKind.favorites,
    SmartPlaylistKind.forgottenGems,
    SmartPlaylistKind.unplayed,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = [
      for (final k in kinds)
        if (ref.watch(smartPlaylistProvider(k)) case final list when list.isNotEmpty) (k, list),
    ];
    if (available.isEmpty) return const SizedBox.shrink();
    final player = ref.read(playerControllerProvider.notifier);
    return _Shelf(
      title: 'Made for you',
      subtitle: 'From your listening',
      itemCount: available.length,
      height: 244,
      itemWidth: 170,
      itemBuilder: (context, i) {
        final (kind, tracks) = available[i];
        final art = tracks.map((t) => t.artPath).whereType<String>().toSet().take(4).toList();
        return MediaCard(
          artwork: SmartPlaylistArt(info: kind.info, artPaths: art, radius: 20),
          title: kind.info.title,
          subtitle: Format.songs(tracks.length),
          onTap: () => AppNav.smart(context, kind.name),
          onPlay: () => player.playTracks(tracks, source: 'smart:${kind.name}'),
          onMenu: (pos) => showCollectionMenu(context, ref,
              title: kind.info.title, tracks: tracks, source: 'smart:${kind.name}', art: art, position: pos),
        );
      },
    );
  }
}

class _Favorites extends ConsumerWidget {
  const _Favorites();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteTracksProvider);
    if (favorites.isEmpty) return const SizedBox.shrink();
    final list = favorites.take(20).toList();
    return _Shelf(
      title: 'Your favorites',
      itemCount: list.length,
      onMore: () => AppNav.libraryTab(context, 'liked'),
      itemBuilder: (context, i) => _trackCard(context, ref, list, i, source: 'favorites'),
    );
  }
}

class _RecentlyAdded extends ConsumerWidget {
  const _RecentlyAdded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = [...ref.watch(albumsProvider)]..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    final list = albums.take(16).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final player = ref.read(playerControllerProvider.notifier);
    return _Shelf(
      title: 'Recently added',
      itemCount: list.length,
      onMore: () => AppNav.smart(context, SmartPlaylistKind.recentlyAdded.name),
      itemBuilder: (context, i) {
        final album = list[i];
        return MediaCard(
          artwork: Artwork(path: album.artPath, placeholderKey: album.key, radius: 20, icon: Icons.album_rounded),
          title: album.title,
          subtitle: album.artist,
          onTap: () => AppNav.album(context, album.key),
          onPlay: () => player.playTracks(album.tracks, source: 'album:${album.key}'),
          onMenu: (pos) => showCollectionMenu(context, ref,
              title: album.title,
              subtitle: album.artist,
              tracks: album.tracks,
              source: 'album:${album.key}',
              art: [?album.artPath],
              position: pos,
              onOpen: () => AppNav.album(context, album.key)),
        );
      },
    );
  }
}

class _MostPlayed extends ConsumerWidget {
  const _MostPlayed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(mostPlayedTracksProvider);
    if (list.isEmpty) return const SizedBox.shrink();
    final showCounts = ref.watch(settingsProvider.select((s) => s.showPlayCounts));
    return _Shelf(
      title: 'Most played',
      itemCount: list.length,
      onMore: () => AppNav.smart(context, SmartPlaylistKind.mostPlayed.name),
      itemBuilder: (context, i) => _trackCard(
        context,
        ref,
        list,
        i,
        source: 'smart:mostPlayed',
        subtitle: showCounts ? Format.count(list[i].playCount, 'play') : null,
      ),
    );
  }
}
