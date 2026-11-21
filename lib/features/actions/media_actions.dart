import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/routing/app_nav.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/app_paths.dart';
import '../../core/services/file_ops.dart';
import '../../core/utils/format.dart';
import '../../data/models/track.dart';
import '../../data/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/common.dart';
import '../../widgets/volume_slider.dart';
import '../player/player_controller.dart';
import '../lyrics/lyrics_sheet.dart';
import '../playlists/playlist_providers.dart';
import '../../widgets/motion.dart';

class MenuAction {
  const MenuAction(this.icon, this.label, this.onSelected, {this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Context for dialogs and snackbars that outlives the widget that opened a
/// menu (e.g. a list row that disappears after "Remove").
BuildContext get _rootContext => rootNavigatorKey.currentContext!;

/// Popup menu at [position] (right click / desktop) or a bottom sheet (touch).
Future<void> showActionMenu(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? artPath,
  List<String> collageArt = const [],
  required List<MenuAction?> actions,
  Offset? position,
  bool showVolume = false,
}) async {
  if (position != null) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final scheme = Theme.of(context).colorScheme;
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        for (var i = 0; i < actions.length; i++)
          if (actions[i] == null)
            const PopupMenuDivider()
          else
            PopupMenuItem<int>(
              value: i,
              height: 44,
              child: Row(
                children: [
                  Icon(actions[i]!.icon, size: 20, color: actions[i]!.destructive ? scheme.error : scheme.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Text(actions[i]!.label, style: TextStyle(color: actions[i]!.destructive ? scheme.error : null)),
                ],
              ),
            ),
      ],
    );
    if (selected != null) actions[selected]!.onSelected();
    return;
  }

  final action = await showModalBottomSheet<MenuAction>(
    context: context,
    sheetAnimationStyle: sheetMotion,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            // A song's own menu leads with its name and the volume; other
            // menus (albums, folders) keep their artwork header.
            if (showVolume) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: VolumeSlider(),
              ),
            ] else
              ListTile(
                leading: SizedBox.square(
                  dimension: 52,
                  child: collageArt.isNotEmpty
                      ? CollageArtwork(paths: collageArt, placeholderKey: title, radius: 12)
                      : Artwork(path: artPath, placeholderKey: title, radius: 12),
                ),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                subtitle: subtitle == null ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            const Divider(indent: 16, endIndent: 16, height: 16),
            for (final a in actions)
              if (a == null)
                const Divider(indent: 16, endIndent: 16, height: 16)
              else
                ListTile(
                  leading: Icon(a.icon, color: a.destructive ? theme.colorScheme.error : null),
                  title: Text(a.label, style: a.destructive ? TextStyle(color: theme.colorScheme.error) : null),
                  onTap: () => Navigator.pop(context, a),
                ),
          ],
        ),
      );
    },
  );
  action?.onSelected();
}

// Tracks ------------------------------------------------------------------------

Future<void> showTrackMenu(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  Offset? position,
  PlaylistItem? playlistItem,
  int? queueIndex,
}) {
  final player = ref.read(playerControllerProvider.notifier);
  final actions = <MenuAction?>[
    MenuAction(Icons.play_arrow_rounded, 'Play', () => player.playTracks([track])),
    MenuAction(Icons.playlist_play_rounded, 'Play next', () {
      player.playNext([track]);
      showSnack(_rootContext, 'Playing "${track.title}" next');
    }),
    MenuAction(Icons.queue_music_rounded, 'Add to queue', () {
      player.addToQueue([track]);
      showSnack(_rootContext, 'Added to queue');
    }),
    MenuAction(Icons.playlist_add_rounded, 'Add to playlist', () => showAddToPlaylist(_rootContext, ref, [track])),
    MenuAction(
      track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      track.isFavorite ? 'Remove from favorites' : 'Add to favorites',
      () => toggleFavorite(ref, track),
    ),
    null,
    MenuAction(Icons.album_rounded, 'View album', () => AppNav.album(_rootContext, track.albumKey)),
    MenuAction(Icons.person_rounded, 'View artist', () => AppNav.artist(_rootContext, track.artistNames.first)),
    MenuAction(Icons.folder_rounded, 'Go to folder', () => AppNav.folder(_rootContext, track.folder)),
    MenuAction(Icons.lyrics_rounded, 'Lyrics', () => showLyrics(_rootContext, track)),
    MenuAction(Icons.info_outline_rounded, 'Song details', () => showSongInfo(_rootContext, track)),
    MenuAction(Icons.image_rounded, 'Change album art', () => changeTrackArt(ref, track)),
    if (track.customArtPath != null)
      MenuAction(Icons.hide_image_rounded, 'Restore original album art', () => restoreTrackArt(ref, track)),
    null,
    if (queueIndex != null)
      MenuAction(Icons.remove_circle_outline_rounded, 'Remove from queue', () => player.removeAt(queueIndex)),
    if (playlistItem != null)
      MenuAction(Icons.playlist_remove_rounded, 'Remove from playlist', () async {
        await ref.read(playlistRepositoryProvider).removeEntries(playlistItem.entry.playlistId, [playlistItem.entry.id]);
        final ctx = _rootContext;
        if (!ctx.mounted) return;
        showSnack(ctx, 'Removed from playlist', actionLabel: 'Undo', onAction: () {
          ref.read(playlistRepositoryProvider).restoreEntry(playlistItem.entry);
        });
      }),
    MenuAction(Icons.hide_source_rounded, 'Remove from library', () => removeFromLibrary(ref, [track])),
    MenuAction(Icons.delete_forever_rounded, 'Delete file from device', () => deleteTrackFile(ref, track),
        destructive: true),
  ];
  return showActionMenu(
    context,
    title: track.title,
    subtitle: '${track.displayArtist} · ${track.displayAlbum}',
    artPath: track.artPath,
    actions: actions,
    position: position,
    showVolume: true,
  );
}

/// Menu for any group of songs (album, artist, genre, folder, smart playlist).
Future<void> showCollectionMenu(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  String? subtitle,
  required List<Track> tracks,
  String? source,
  List<String> art = const [],
  Offset? position,
  List<MenuAction> extra = const [],
  VoidCallback? onOpen,
}) {
  final player = ref.read(playerControllerProvider.notifier);
  return showActionMenu(
    context,
    title: title,
    subtitle: subtitle,
    collageArt: art,
    position: position,
    actions: [
      if (onOpen != null) MenuAction(Icons.open_in_full_rounded, 'Open', onOpen),
      MenuAction(Icons.play_arrow_rounded, 'Play', () => player.playTracks(tracks, source: source, shuffle: false)),
      MenuAction(Icons.shuffle_rounded, 'Shuffle', () => player.playTracks(tracks, source: source, shuffle: true)),
      MenuAction(Icons.playlist_play_rounded, 'Play next', () {
        player.playNext(tracks);
        showSnack(_rootContext, '${Format.songs(tracks.length)} will play next');
      }),
      MenuAction(Icons.queue_music_rounded, 'Add to queue', () {
        player.addToQueue(tracks);
        showSnack(_rootContext, 'Added ${Format.songs(tracks.length)} to queue');
      }),
      MenuAction(Icons.playlist_add_rounded, 'Add to playlist', () => showAddToPlaylist(_rootContext, ref, tracks)),
      if (extra.isNotEmpty) null,
      ...extra,
    ],
  );
}

/// Lets the user pick an image as this song's artwork. The image is copied
/// into the app's own storage (so it keeps working if the original is moved)
/// and stored per song; every screen, the mini player and the album colors
/// pick it up immediately through the library stream.
Future<void> changeTrackArt(WidgetRef ref, Track track) async {
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose album art');
  } catch (_) {
    final ctx = _rootContext;
    if (ctx.mounted) showSnack(ctx, 'Could not open the image picker');
    return;
  }
  final source = picked?.path;
  if (source == null) return;
  final ctx = _rootContext;
  try {
    final bytes = await File(source).readAsBytes();
    // Make sure it is an image Flutter can actually decode before saving it.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    descriptor.dispose();
    buffer.dispose();

    final dir = AppPaths.instance.customArtDir;
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = p.extension(source).toLowerCase();
    final target = p.join(dir.path, '${track.id}_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.img' : ext}');
    await File(target).writeAsBytes(bytes, flush: true);

    final previous = track.customArtPath;
    await ref.read(libraryRepositoryProvider).setCustomArt(track.id, target);
    _deleteOwnedCustomArt(previous);
    if (ctx.mounted) showSnack(ctx, 'Album art updated for "${track.title}"');
  } catch (_) {
    if (ctx.mounted) showSnack(ctx, 'That file could not be used as album art');
  }
}

/// Removes the custom artwork and goes back to the song's own cover.
Future<void> restoreTrackArt(WidgetRef ref, Track track) async {
  final previous = track.customArtPath;
  await ref.read(libraryRepositoryProvider).setCustomArt(track.id, null);
  _deleteOwnedCustomArt(previous);
  final ctx = _rootContext;
  if (ctx.mounted) showSnack(ctx, 'Original album art restored');
}

void _deleteOwnedCustomArt(String? path) {
  if (path == null) return;
  if (p.isWithin(AppPaths.instance.customArtDir.path, path)) {
    File(path).delete().catchError((Object _) => File(path));
  }
}

Future<void> toggleFavorite(WidgetRef ref, Track track) async {
  await ref.read(libraryRepositoryProvider).setFavorite(track.id, !track.isFavorite);
}

Future<void> removeFromLibrary(WidgetRef ref, List<Track> tracks) async {
  final single = tracks.length == 1;
  final ok = await confirmDialog(
    _rootContext,
    icon: Icons.hide_source_rounded,
    title: single ? 'Remove from library?' : 'Remove ${tracks.length} songs from library?',
    message: '${single ? '"${tracks.first.title}"' : 'These songs'} will be hidden from Snap and skipped by '
        'future scans. The ${single ? 'file stays' : 'files stay'} on your device.\n\n'
        'You can bring removed songs back in Settings › Library.',
    confirmLabel: 'Remove',
  );
  if (!ok) return;
  final ids = tracks.map((t) => t.id).toList();
  await ref.read(libraryRepositoryProvider).setExcluded(ids, true);
  await ref.read(playerControllerProvider.notifier).removeTracks(ids.toSet());
  final ctx = _rootContext;
  if (ctx.mounted) {
    showSnack(ctx, single ? 'Removed from library' : 'Removed ${tracks.length} songs', actionLabel: 'Undo',
        onAction: () => ref.read(libraryRepositoryProvider).setExcluded(ids, false));
  }
}

Future<void> deleteTrackFile(WidgetRef ref, Track track) async {
  final ok = await confirmDialog(
    _rootContext,
    icon: Icons.delete_forever_rounded,
    destructive: true,
    title: 'Delete file from device?',
    message: '"${track.fileName}" will be permanently deleted from your device. '
        'This is not the same as removing it from the library.\n\nThis cannot be undone.',
    confirmLabel: 'Delete file',
  );
  if (!ok) return;
  final player = ref.read(playerControllerProvider.notifier);
  // Release the file first so the OS lets us delete it.
  await player.removeTracks({track.id});
  final outcome = await FileOps.deleteAudioFile(track.path);
  final ctx = _rootContext;
  switch (outcome) {
    case DeleteOutcome.deleted:
      await ref.read(libraryRepositoryProvider).deleteById(track.id);
      if (ctx.mounted) showSnack(ctx, 'Deleted "${track.title}"');
    case DeleteOutcome.cancelled:
      if (ctx.mounted) showSnack(ctx, 'Delete cancelled');
    case DeleteOutcome.failed:
      if (ctx.mounted) showSnack(ctx, 'Could not delete the file. Check permissions and try again.');
  }
}

Future<void> showSongInfo(BuildContext context, Track track) {
  final date = DateFormat.yMMMd().add_jm();
  final rows = <(String, String)>[
    ('Title', track.title),
    ('Artist', track.displayArtist),
    ('Album', track.displayAlbum),
    if (track.albumArtist.isNotEmpty) ('Album artist', track.albumArtist),
    ('Genre', track.displayGenre),
    if (track.year != null) ('Year', '${track.year}'),
    if (track.trackNumber != null) ('Track', '${track.trackNumber}${track.discNumber != null ? ' · Disc ${track.discNumber}' : ''}'),
    ('Duration', Format.durationMs(track.durationMs)),
    ('Format', track.extension),
    ('Size', Format.bytes(track.fileSize)),
    ('Plays', '${track.playCount}'),
    if (track.lastPlayed != null) ('Last played', date.format(track.lastPlayed!)),
    ('Added', date.format(track.dateAdded)),
    ('Modified', date.format(track.fileModified)),
    ('Location', track.path),
  ];
  return showDialog(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Song details'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 104,
                          child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
    },
  );
}

// Playlists ------------------------------------------------------------------------

Future<void> showAddToPlaylist(BuildContext context, WidgetRef ref, List<Track> tracks) async {
  if (tracks.isEmpty) return;
  final result = await showModalBottomSheet<Object>(
    context: context,
    sheetAnimationStyle: sheetMotion,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final playlists = ref.watch(playlistViewsProvider);
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text('Add ${Format.songs(tracks.length)} to…', style: theme.textTheme.titleLarge),
              ),
              ListTile(
                leading: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.add_rounded, color: theme.colorScheme.onPrimaryContainer),
                ),
                title: const Text('New playlist'),
                onTap: () => Navigator.pop(context, 'new'),
              ),
              for (final view in playlists)
                ListTile(
                  leading: SizedBox.square(
                    dimension: 52,
                    child: CollageArtwork(
                      paths: view.artPaths,
                      coverPath: view.playlist.coverPath,
                      placeholderKey: view.playlist.name,
                      radius: 12,
                    ),
                  ),
                  title: Text(view.playlist.name),
                  subtitle: Text(Format.songs(view.items.length)),
                  onTap: () => Navigator.pop(context, view.playlist.id),
                ),
            ],
          ),
        );
      },
    ),
  );
  if (result == null) return;
  final ctx = _rootContext;
  if (!ctx.mounted) return;
  if (result == 'new') {
    await showCreatePlaylistDialog(ctx, ref, tracks: tracks);
    return;
  }
  final id = result as int;
  final outcome = await ref.read(playlistRepositoryProvider).addTracks(id, tracks.map((t) => t.id).toList());
  final name = ref.read(playlistViewProvider(id))?.playlist.name ?? 'playlist';
  if (!ctx.mounted) return;
  final message = outcome.added == 0
      ? 'Already in $name'
      : 'Added ${Format.songs(outcome.added)} to $name${outcome.skipped > 0 ? ' (${outcome.skipped} already there)' : ''}';
  showSnack(ctx, message, actionLabel: 'Open', onAction: () => AppNav.playlist(_rootContext, id));
}

Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  IconData icon = Icons.queue_music_rounded,
}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final valid = controller.text.trim().isNotEmpty;
        void submit() {
          if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
        }

        return AlertDialog(
          icon: Icon(icon),
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Playlist name', counterText: ''),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: valid ? submit : null, child: Text(confirmLabel)),
          ],
        );
      },
    ),
  );
}

Future<int?> showCreatePlaylistDialog(BuildContext context, WidgetRef ref, {List<Track> tracks = const []}) async {
  final name = await showNameDialog(
    context,
    title: 'New playlist',
    confirmLabel: 'Create',
    icon: Icons.playlist_add_rounded,
  );
  if (name == null) return null;
  final id = await ref.read(playlistRepositoryProvider).create(name, trackIds: tracks.map((t) => t.id).toList());
  final ctx = _rootContext;
  if (ctx.mounted) {
    showSnack(
      ctx,
      tracks.isEmpty ? 'Created "$name"' : 'Created "$name" with ${Format.songs(tracks.length)}',
      actionLabel: 'Open',
      onAction: () => AppNav.playlist(_rootContext, id),
    );
  }
  return id;
}

Future<void> renamePlaylist(BuildContext context, WidgetRef ref, int id, String current) async {
  final name = await showNameDialog(context, title: 'Rename playlist', confirmLabel: 'Rename', initial: current, icon: Icons.edit_rounded);
  if (name != null && name != current) await ref.read(playlistRepositoryProvider).rename(id, name);
}

Future<bool> deletePlaylist(BuildContext context, WidgetRef ref, int id, String name) async {
  final ok = await confirmDialog(
    context,
    icon: Icons.delete_outline_rounded,
    destructive: true,
    title: 'Delete "$name"?',
    message: 'The playlist will be deleted. Your songs stay in the library.',
    confirmLabel: 'Delete',
  );
  if (!ok) return false;
  final cover = ref.read(playlistViewProvider(id))?.playlist.coverPath;
  await ref.read(playlistRepositoryProvider).delete(id);
  _deleteOwnedCover(cover);
  return true;
}

Future<void> pickPlaylistCover(BuildContext context, WidgetRef ref, int id) async {
  try {
    final picked = await FilePicker.pickFile(type: FileType.image);
    final source = picked?.path;
    if (source == null) return;
    final dir = AppPaths.instance.playlistArtDir;
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = p.join(dir.path, '${id}_${DateTime.now().millisecondsSinceEpoch}${p.extension(source).toLowerCase()}');
    await File(source).copy(target);
    final old = ref.read(playlistViewProvider(id))?.playlist.coverPath;
    await ref.read(playlistRepositoryProvider).setCover(id, target);
    _deleteOwnedCover(old);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not use that image');
  }
}

Future<void> removePlaylistCover(WidgetRef ref, int id) async {
  final old = ref.read(playlistViewProvider(id))?.playlist.coverPath;
  await ref.read(playlistRepositoryProvider).setCover(id, null);
  _deleteOwnedCover(old);
}

void _deleteOwnedCover(String? path) {
  if (path == null) return;
  if (p.isWithin(AppPaths.instance.playlistArtDir.path, path)) {
    File(path).delete().catchError((Object _) => File(path));
  }
}
