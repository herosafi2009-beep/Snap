import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../data/providers.dart';
import '../settings/settings_model.dart';
import 'library_logic.dart';
import '../../widgets/motion.dart';

/// Song order inside an opened folder. Only changes what is displayed (and
/// what plays when a song is tapped); files on disk are never touched.
enum FolderSortOption {
  albumAsc('Album', 'A → Z', SortField.album, true),
  albumDesc('Album', 'Z → A', SortField.album, false),
  nameAsc('Name', 'A → Z', SortField.title, true),
  nameDesc('Name', 'Z → A', SortField.title, false),
  addedNewest('Date added', 'Newest → Oldest', SortField.dateAdded, false),
  addedOldest('Date added', 'Oldest → Newest', SortField.dateAdded, true),
  artistAsc('Artist', 'A → Z', SortField.artist, true),
  artistDesc('Artist', 'Z → A', SortField.artist, false),
  durationShortest('Duration', 'Shortest → Longest', SortField.duration, true),
  durationLongest('Duration', 'Longest → Shortest', SortField.duration, false);

  const FolderSortOption(this.group, this.direction, this.field, this.ascending);

  final String group;
  final String direction;
  final SortField field;
  final bool ascending;

  /// Album A → Z matches the folder's natural order (album, disc, track).
  static const fallback = FolderSortOption.albumAsc;

  String get label => '$group · $direction';

  IconData get icon => switch (field) {
        SortField.title => Icons.sort_by_alpha_rounded,
        SortField.dateAdded => Icons.schedule_rounded,
        SortField.artist => Icons.person_rounded,
        SortField.duration => Icons.timer_rounded,
        _ => Icons.album_rounded,
      };

  List<Track> apply(List<Track> tracks) {
    if (this == fallback) return List.of(tracks)..sort(LibraryLogic.albumOrder);
    return LibraryLogic.sortTracks(tracks, SortSpec(field, ascending));
  }
}

const _storageKey = 'folder_sorts';

/// Remembers the chosen order per folder path, persisted with the settings.
final folderSortProvider = NotifierProvider<FolderSortController, Map<String, FolderSortOption>>(
  FolderSortController.new,
);

class FolderSortController extends Notifier<Map<String, FolderSortOption>> {
  @override
  Map<String, FolderSortOption> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(settingsRepositoryProvider).read(_storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final loaded = <String, FolderSortOption>{};
      for (final e in decoded.entries) {
        final option = FolderSortOption.values.where((o) => o.name == e.value).firstOrNull;
        if (option != null && e.key is String) loaded[e.key as String] = option;
      }
      // Choices made before loading finished win.
      state = {...loaded, ...state};
    } catch (_) {}
  }

  FolderSortOption optionFor(String path) => state[path] ?? FolderSortOption.fallback;

  void set(String path, FolderSortOption option) {
    final next = {...state};
    if (option == FolderSortOption.fallback) {
      next.remove(path);
    } else {
      next[path] = option;
    }
    state = next;
    ref
        .read(settingsRepositoryProvider)
        .write(_storageKey, jsonEncode({for (final e in next.entries) e.key: e.value.name}))
        .catchError((Object _) {});
  }
}

/// Bottom sheet listing every order, grouped by what is sorted.
Future<void> showFolderSortSheet(BuildContext context, WidgetRef ref, String path) {
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: sheetMotion,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(folderSortProvider)[path] ?? FolderSortOption.fallback;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text('Sort songs', style: theme.textTheme.titleLarge),
              ),
              for (final option in FolderSortOption.values) ...[
                if (option.index % 2 == 0 && option.index > 0) const SizedBox(height: 6),
                Material(
                  color: option == current ? scheme.secondaryContainer : Colors.transparent,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    shape: const StadiumBorder(),
                    leading: Icon(option.icon,
                        color: option == current ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                    title: Text(option.group),
                    subtitle: Text(option.direction),
                    trailing: option == current
                        ? Icon(Icons.check_rounded, color: scheme.onSecondaryContainer)
                        : null,
                    onTap: () {
                      ref.read(folderSortProvider.notifier).set(path, option);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
