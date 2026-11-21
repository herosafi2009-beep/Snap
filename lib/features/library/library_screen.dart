import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/routing/app_nav.dart';
import '../../core/services/permission_service.dart';
import '../../core/utils/format.dart';
import '../../data/models/library_groups.dart';
import '../../data/models/track.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/media_card.dart';
import '../../widgets/motion.dart';
import '../../widgets/track_tile.dart';
import '../actions/media_actions.dart';
import '../player/player_controller.dart';
import '../playlists/playlists_screen.dart';
import '../queue/queue_screen.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_model.dart';
import 'collection_screens.dart';
import 'folder_flow.dart';
import 'library_logic.dart';
import 'library_providers.dart';
import 'scan_controller.dart';

extension on LibraryTab {
  String get label => switch (this) {
        LibraryTab.folders => 'Folders',
        LibraryTab.artists => 'Artists',
        LibraryTab.songs => 'Songs',
        LibraryTab.playlists => 'Playlists',
        LibraryTab.liked => 'Liked',
        LibraryTab.queue => 'Queue',
      };

  IconData get icon => switch (this) {
        LibraryTab.folders => Icons.folder_rounded,
        LibraryTab.artists => Icons.person_rounded,
        LibraryTab.songs => Icons.music_note_rounded,
        LibraryTab.playlists => Icons.queue_music_rounded,
        LibraryTab.liked => Icons.favorite_rounded,
        LibraryTab.queue => Icons.playlist_play_rounded,
      };

  /// Tabs that only make sense once songs have been scanned.
  bool get needsSongs => this != LibraryTab.playlists && this != LibraryTab.queue;

  /// The section whose layout and sorting this tab controls, if any.
  LibraryCategory? get category => switch (this) {
        LibraryTab.songs => LibraryCategory.songs,
        LibraryTab.artists => LibraryCategory.artists,
        LibraryTab.folders => LibraryCategory.folders,
        _ => null,
      };

  /// Sections that can be shown as a grid as well as a list.
  bool get canSwitchLayout => this == LibraryTab.artists || this == LibraryTab.folders;

  bool get canSort => category != null;
}

/// Library section: Folders, Artists, Songs, Playlists, Liked and Queue as
/// swipeable pill tabs, so the bottom navigation stays short.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.requestedTab, this.requestId});

  /// Tab asked for through navigation (e.g. Home > "Your favorites").
  final String? requestedTab;
  final String? requestId;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _handledRequest;

  /// The tab the user is actually looking at. It follows the swipe, flipping
  /// at the half-way point, so the sort and layout buttons always belong to
  /// the content on screen (and act on the right section).
  late LibraryTab _visible;

  @override
  void initState() {
    super.initState();
    final LibraryTab initial = _parse(widget.requestedTab) ?? ref.read(libraryTabProvider);
    _handledRequest = widget.requestId;
    _visible = initial;
    _tabs = TabController(
      length: LibraryTab.values.length,
      vsync: this,
      initialIndex: initial.index,
    );
    _tabs.animation?.addListener(_syncVisibleTab);
  }

  void _syncVisibleTab() {
    final position = _tabs.animation?.value ?? _tabs.index.toDouble();
    final tab = LibraryTab.values[position.round().clamp(0, LibraryTab.values.length - 1)];
    if (tab == _visible) return;
    setState(() => _visible = tab);
    ref.read(libraryTabProvider.notifier).set(tab);
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = _parse(widget.requestedTab);
    if (requested != null && widget.requestId != null && widget.requestId != _handledRequest) {
      _handledRequest = widget.requestId;
      _tabs.animateTo(requested.index);
    }
  }

  static LibraryTab? _parse(String? name) => LibraryTab.values.where((t) => t.name == name).firstOrNull;

  @override
  void dispose() {
    _tabs.animation?.removeListener(_syncVisibleTab);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(allTracksProvider);
    final tab = _visible;
    final category = tab.category;
    final layout = category == null
        ? LibraryLayout.list
        : ref.watch(settingsProvider.select((s) => s.layoutFor(category)));
    final scanning = ref.watch(scanControllerProvider.select((s) => s.running));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pad = Breakpoints.pagePadding(context);
    final motion = Motion.of(context, ref);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 12, pad - 8, 4),
              child: Row(
                children: [
                  Expanded(child: Semantics(header: true, child: Text('Library', style: theme.textTheme.headlineMedium))),
                  // Only the buttons that apply to the visible section, swapped
                  // as the section changes rather than popped in and out.
                  FadeThrough(
                    alignment: Alignment.centerRight,
                    child: Row(
                      key: ValueKey(tab),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.canSort)
                          IconButton(
                            tooltip: 'Sort',
                            onPressed: () => _showSortSheet(context, ref, tab),
                            icon: const Icon(Icons.sort_rounded),
                          ),
                        if (tab.canSwitchLayout && category != null)
                          IconButton(
                            tooltip: layout == LibraryLayout.grid ? 'List view' : 'Grid view',
                            onPressed: () {
                              final next = layout == LibraryLayout.grid ? LibraryLayout.list : LibraryLayout.grid;
                              ref.read(settingsProvider.notifier).update((s) => s.withLayout(category, next));
                            },
                            icon: FadeThrough(
                              child: Icon(
                                layout == LibraryLayout.grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                                key: ValueKey(layout),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Library options',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      switch (v) {
                        case 'add':
                          addMusicFolder(context, ref);
                        case 'rescan':
                          ref.read(scanControllerProvider.notifier).scan();
                        case 'folders':
                          AppNav.settingsPage(context, 'library');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'add', child: Text('Add music folder')),
                      PopupMenuItem(value: 'rescan', enabled: !scanning, child: const Text('Rescan library')),
                      const PopupMenuItem(value: 'folders', child: Text('Manage folders')),
                    ],
                  ),
                ],
              ),
            ),
            const _PermissionBanner(),
            // Pill tabs: the indicator slides with swipes between tabs.
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.fromLTRB(pad - 4, 4, pad - 4, 8),
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              dividerHeight: 0,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: ShapeDecoration(color: scheme.secondaryContainer, shape: const StadiumBorder()),
              splashBorderRadius: BorderRadius.circular(999),
              labelColor: scheme.onSecondaryContainer,
              unselectedLabelColor: scheme.onSurfaceVariant,
              labelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              unselectedLabelStyle: theme.textTheme.labelLarge,
              overlayColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: 0.06)),
              tabs: [
                for (final t in LibraryTab.values)
                  Tab(
                    height: 40,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(t.icon, size: 18), const SizedBox(width: 8), Text(t.label)],
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: motion.short,
              curve: Curves.easeOutCubic,
              child: tracks.isNotEmpty && (tab == LibraryTab.songs || tab == LibraryTab.artists)
                  ? const _FilterBar()
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  for (final t in LibraryTab.values)
                    _NeedsLibrary(
                      tab: t,
                      child: switch (t) {
                        LibraryTab.folders => const _FoldersTab(),
                        LibraryTab.artists => const _ArtistsTab(),
                        LibraryTab.songs => const _SongsTab(),
                        LibraryTab.playlists => const PlaylistsView(),
                        LibraryTab.liked => const _LikedTab(),
                        LibraryTab.queue => const QueueView(),
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows loading / empty-library states for tabs that list scanned songs.
class _NeedsLibrary extends ConsumerWidget {
  const _NeedsLibrary({required this.tab, required this.child});
  final LibraryTab tab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!tab.needsSongs) return child;
    // Placeholder, empty state and real content cross-fade into each other
    // instead of snapping, including when a scan fills the library.
    return FadeThrough(alignment: Alignment.topCenter, child: _body(context, ref, child));
  }

  Widget _body(BuildContext context, WidgetRef ref, Widget child) {
    if (!ref.watch(libraryLoadedProvider)) {
      // A placeholder shaped like what is coming, so nothing jumps when the
      // real content arrives.
      final category = tab.category;
      final grid = category != null &&
          ref.watch(settingsProvider.select((s) => s.layoutFor(category))) == LibraryLayout.grid;
      if (grid) return MediaGridSkeleton(key: const ValueKey('skeleton'), circular: tab == LibraryTab.artists);
      return const SingleChildScrollView(key: ValueKey('skeleton'), child: TrackListSkeleton(count: 10));
    }
    if (ref.watch(allTracksProvider.select((t) => t.isNotEmpty))) {
      return KeyedSubtree(key: const ValueKey('content'), child: child);
    }
    final scanning = ref.watch(scanControllerProvider.select((s) => s.running));
    return EmptyState(
      key: const ValueKey('empty'),
      icon: Icons.library_music_rounded,
      title: scanning ? 'Building your library' : 'No music yet',
      message: scanning ? 'Songs will appear as they are found.' : 'Choose a music folder to build your library.',
      action: scanning ? null : const AddMusicButtons(),
    );
  }
}

/// Library > Liked: every song you have hearted.
class _LikedTab extends ConsumerWidget {
  const _LikedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(favoriteTracksProvider);
    final player = ref.read(playerControllerProvider.notifier);
    final pad = Breakpoints.pagePadding(context);
    final theme = Theme.of(context);

    if (liked.isEmpty) {
      return const EmptyState(
        compact: true,
        icon: Icons.favorite_border_rounded,
        title: 'No liked songs yet',
        message: 'Tap the heart on any song and it will show up here.',
      );
    }
    final totalMs = liked.fold<int>(0, (a, t) => a + t.durationMs);
    return Scrollbar(
      child: CustomScrollView(
        key: const PageStorageKey('liked-list'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Format.songs(liked.length)} · ${Format.totalTime(totalMs)}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SpringPress(
                    pressedScale: 0.92,
                    child: FilledButton.icon(
                      onPressed: () => player.playTracks(liked, source: 'favorites', shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SpringPress(
                    pressedScale: 0.92,
                    child: FilledButton.tonalIcon(
                      onPressed: () => player.playTracks(liked, source: 'favorites', shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad - 12, 0, pad - 12, 24),
            sliver: SliverFixedExtentList.builder(
              itemExtent: TrackTile.height,
              itemCount: liked.length,
              itemBuilder: (context, i) => TrackTile(
                track: liked[i],
                onTap: () => player.playTracks(liked, startIndex: i, source: 'favorites'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final access = ref.watch(storageAccessProvider).value;
    final hasFolders = (ref.watch(musicFoldersProvider).value ?? const []).isNotEmpty;
    if (access == null || access == StorageAccess.granted || !hasFolders) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: Icon(Icons.lock_rounded, color: scheme.onErrorContainer),
          title: Text('Permission needed', style: TextStyle(color: scheme.onErrorContainer)),
          subtitle: Text('Allow access to audio files to scan your music.', style: TextStyle(color: scheme.onErrorContainer)),
          trailing: FilledButton(
            onPressed: () async {
              if (await ensureStorageAccess(context, ref)) ref.read(scanControllerProvider.notifier).scan();
            },
            child: const Text('Allow'),
          ),
        ),
      ),
    );
  }
}

// Filters ------------------------------------------------------------------------

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final notifier = ref.read(libraryFilterProvider.notifier);
    final pad = Breakpoints.pagePadding(context);

    Future<void> pick(String title, List<(String key, String label)> options, void Function(String) onPicked) async {
      final picked = await showDialog<String>(context: context, builder: (_) => _PickerDialog(title: title, options: options));
      if (picked != null) onPicked(picked);
    }

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
        children: [
          if (!filter.isEmpty) ...[
            ActionChip(
              avatar: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Clear'),
              onPressed: () => notifier.set(const LibraryFilter()),
            ),
            const SizedBox(width: 8),
          ],
          FilterChip(
            label: const Text('Favorites'),
            selected: filter.favorites,
            onSelected: (v) => notifier.set(filter.copyWith(favorites: v)),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Recently added'),
            selected: filter.recentlyAdded,
            onSelected: (v) => notifier.set(filter.copyWith(recentlyAdded: v)),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Played'),
            selected: filter.played == true,
            onSelected: (v) => notifier.set(filter.copyWith(played: () => v ? true : null)),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Unplayed'),
            selected: filter.played == false,
            onSelected: (v) => notifier.set(filter.copyWith(played: () => v ? false : null)),
          ),
          const SizedBox(width: 8),
          _DropdownChip(
            label: 'Genre',
            value: filter.genre == null
                ? null
                : ref.read(genresProvider).where((g) => g.key == filter.genre).map((g) => g.name).firstOrNull,
            onTap: () => pick('Genre', [for (final g in ref.read(genresProvider)) (g.key, g.name)],
                (k) => notifier.set(filter.copyWith(genre: () => k))),
            onClear: () => notifier.set(filter.copyWith(genre: () => null)),
          ),
          const SizedBox(width: 8),
          _DropdownChip(
            label: 'Artist',
            value: filter.artist == null ? null : ref.read(artistByKeyProvider)[filter.artist]?.name,
            onTap: () => pick('Artist', [for (final a in ref.read(artistsProvider)) (a.key, a.name)],
                (k) => notifier.set(filter.copyWith(artist: () => k))),
            onClear: () => notifier.set(filter.copyWith(artist: () => null)),
          ),
          const SizedBox(width: 8),
          _DropdownChip(
            label: 'Album',
            value: filter.albumKey == null ? null : ref.read(albumByKeyProvider)[filter.albumKey]?.title,
            onTap: () => pick('Album', [for (final a in ref.read(albumsProvider)) (a.key, '${a.title} · ${a.artist}')],
                (k) => notifier.set(filter.copyWith(albumKey: () => k))),
            onClear: () => notifier.set(filter.copyWith(albumKey: () => null)),
          ),
        ],
      ),
    );
  }
}

class _DropdownChip extends StatelessWidget {
  const _DropdownChip({required this.label, required this.value, required this.onTap, required this.onClear});
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return ActionChip(
        label: Text(label),
        avatar: const Icon(Icons.arrow_drop_down_rounded),
        onPressed: onTap,
      );
    }
    return InputChip(
      label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(value!, overflow: TextOverflow.ellipsis)),
      selected: true,
      onPressed: onTap,
      onDeleted: onClear,
    );
  }
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({required this.title, required this.options});
  final String title;
  final List<(String, String)> options;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final options = q.isEmpty ? widget.options : widget.options.where((o) => o.$2.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Filter'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: options.isEmpty
                  ? const Center(child: Text('No matches'))
                  : ListView.builder(
                      itemCount: options.length,
                      itemExtent: 52,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(options[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, options[i].$1),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

// Sorting ------------------------------------------------------------------------

Future<void> _showSortSheet(BuildContext context, WidgetRef ref, LibraryTab tab) {
  final (provider, fields) = switch (tab) {
    LibraryTab.artists => (artistSortProvider, [SortField.title, SortField.playCount, SortField.duration]),
    LibraryTab.folders => (folderListSortProvider, [SortField.title, SortField.duration, SortField.dateAdded]),
    _ => (songSortProvider, SortField.values),
  };
  String label(SortField f) => switch ((tab, f)) {
        (LibraryTab.artists, SortField.title) => 'Name',
        (LibraryTab.artists, SortField.duration) => 'Number of songs',
        (LibraryTab.folders, SortField.title) => 'Folder name',
        (LibraryTab.folders, SortField.duration) => 'Number of songs',
        (LibraryTab.folders, SortField.dateAdded) => 'Recently added music',
        _ => f.label,
      };

  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: sheetMotion,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final spec = ref.watch(provider);
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text('Sort by', style: theme.textTheme.titleLarge),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.arrow_upward_rounded), label: Text('Ascending')),
                    ButtonSegment(value: false, icon: Icon(Icons.arrow_downward_rounded), label: Text('Descending')),
                  ],
                  selected: {spec.ascending},
                  onSelectionChanged: (v) => ref.read(provider.notifier).set(spec.copyWith(ascending: v.first)),
                ),
                const SizedBox(height: 8),
                RadioGroup<SortField>(
                  groupValue: spec.field,
                  onChanged: (f) {
                    if (f != null) ref.read(provider.notifier).set(spec.copyWith(field: f));
                  },
                  child: Column(
                    children: [
                      for (final f in fields)
                        RadioListTile<SortField>(
                          value: f,
                          secondary: Icon(f.icon),
                          title: Text(label(f)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// Tabs -----------------------------------------------------------------------------

class _SongsTab extends ConsumerWidget {
  const _SongsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(visibleTracksProvider);
    final player = ref.read(playerControllerProvider.notifier);
    final pad = Breakpoints.pagePadding(context);
    final theme = Theme.of(context);

    if (tracks.isEmpty) {
      return const EmptyState(
        compact: true,
        icon: Icons.filter_alt_off_rounded,
        title: 'No matching songs',
        message: 'Try removing some filters.',
      );
    }
    final totalMs = tracks.fold<int>(0, (a, t) => a + t.durationMs);
    return Scrollbar(
      interactive: true,
      child: CustomScrollView(
        primary: true,
        key: const PageStorageKey('songs-list'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${Format.songs(tracks.length)} · ${Format.totalTime(totalMs)}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  SpringPress(
                    pressedScale: 0.92,
                    child: FilledButton.tonalIcon(
                      onPressed: () => player.playTracks(tracks, shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad - 12, 0, pad - 12, 24),
            sliver: SliverFixedExtentList.builder(
              itemExtent: TrackTile.height,
              itemCount: tracks.length,
              itemBuilder: (context, i) => TrackTile(
                track: tracks[i],
                onTap: () => player.playTracks(tracks, startIndex: i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistsTab extends ConsumerWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(visibleArtistsProvider);
    final grid = ref.watch(settingsProvider.select((s) => s.layoutFor(LibraryCategory.artists))) == LibraryLayout.grid;
    final pad = Breakpoints.pagePadding(context);
    if (artists.isEmpty) {
      return const EmptyState(compact: true, icon: Icons.person_rounded, title: 'No artists', message: 'Try removing some filters.');
    }

    void menu(Artist a, Offset? pos) => showCollectionMenu(context, ref,
        title: a.name,
        tracks: a.tracks,
        source: 'artist:${a.key}',
        art: [?a.artPath],
        position: pos,
        onOpen: () => AppNav.artist(context, a.name));

    // Both layouts are built the same way and cross-faded, so switching
    // between them is a transition rather than a jump cut.
    final Widget body = grid
        ? Scrollbar(
            key: const ValueKey('artists-grid'),
            child: GridView.builder(
              key: const PageStorageKey('artists-grid'),
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
              gridDelegate: mediaGridDelegate(context, extent: 180),
              itemCount: artists.length,
              itemBuilder: (context, i) {
                final a = artists[i];
                return MediaCard(
                  circular: true,
                  artwork:
                      Artwork(path: a.artPath, placeholderKey: a.key, shape: BoxShape.circle, icon: Icons.person_rounded),
                  title: a.name,
                  subtitle: Format.songs(a.tracks.length),
                  onTap: () => AppNav.artist(context, a.name),
                  onMenu: (pos) => menu(a, pos),
                );
              },
            ),
          )
        : Scrollbar(
            key: const ValueKey('artists-list'),
            child: ListView.builder(
              key: const PageStorageKey('artists-list'),
              padding: EdgeInsets.fromLTRB(pad - 8, 0, pad - 8, 24),
              itemExtent: 76,
              itemCount: artists.length,
              itemBuilder: (context, i) {
                final a = artists[i];
                return _GroupTile(
                  art:
                      Artwork(path: a.artPath, placeholderKey: a.key, shape: BoxShape.circle, icon: Icons.person_rounded),
                  title: a.name,
                  subtitle: '${Format.count(a.albumCount, 'album')} · ${Format.songs(a.tracks.length)}',
                  onTap: () => AppNav.artist(context, a.name),
                  onMenu: (pos) => menu(a, pos),
                );
              },
            ),
          );
    return FadeThrough(alignment: Alignment.topCenter, child: body);
  }
}

class _FoldersTab extends ConsumerWidget {
  const _FoldersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(visibleFoldersProvider);
    final grid = ref.watch(settingsProvider.select((s) => s.layoutFor(LibraryCategory.folders))) == LibraryLayout.grid;
    final pad = Breakpoints.pagePadding(context);
    List<Track> collect(FolderNode n) => [...n.tracks, for (final s in n.subfolders) ...collect(s)];
    void menu(FolderNode node, Offset? pos) => showCollectionMenu(context, ref,
        title: node.name, subtitle: node.path, tracks: collect(node), source: 'folder:${node.path}', position: pos);

    if (folders.isEmpty) {
      return EmptyState(
        compact: true,
        icon: Icons.folder_rounded,
        title: 'No folders yet',
        message: 'Add a folder and the music inside it shows up here.',
        action: FilledButton.icon(
          onPressed: () => addMusicFolder(context, ref),
          icon: const Icon(Icons.create_new_folder_rounded),
          label: const Text('Add music folder'),
        ),
      );
    }

    final manage = Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => AppNav.settingsPage(context, 'library'),
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Manage music folders'),
        ),
      ),
    );

    return FadeThrough(
      alignment: Alignment.topCenter,
      child: grid
          ? GridView.builder(
              key: const PageStorageKey('folders-grid'),
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
              gridDelegate: mediaGridDelegate(context, extent: 190),
              itemCount: folders.length,
              itemBuilder: (context, i) => FolderCard(
                node: folders[i],
                onTap: () => AppNav.folder(context, folders[i].path),
                onMenu: (pos) => menu(folders[i], pos),
              ),
            )
          : ListView.builder(
              key: const PageStorageKey('folders-list'),
              padding: EdgeInsets.fromLTRB(pad - 4, 4, pad - 4, 24),
              itemCount: folders.length + 1,
              itemBuilder: (context, i) {
                if (i == folders.length) return manage;
                final node = folders[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FolderTile(
                    node: node,
                    onTap: () => AppNav.folder(context, node.path),
                    onMenu: (pos) => menu(node, pos),
                  ),
                );
              },
            ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.art, required this.title, required this.subtitle, required this.onTap, required this.onMenu});
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final void Function(Offset?) onMenu;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: Breakpoints.isDesktop ? null : () => onMenu(null),
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox.square(dimension: 56, child: art),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'More options',
              onPressed: () => onMenu(null),
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
