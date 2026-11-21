import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/permission_service.dart';
import '../../widgets/common.dart';
import 'scan_controller.dart';

/// Makes sure Android storage access is granted, explaining why if needed.
Future<bool> ensureStorageAccess(BuildContext context, WidgetRef ref) async {
  if (!Platform.isAndroid) return true;
  final service = ref.read(permissionServiceProvider);
  var access = await service.status();
  if (access == StorageAccess.granted) return true;
  access = await service.request();
  ref.invalidate(storageAccessProvider);
  if (access == StorageAccess.granted) return true;
  if (!context.mounted) return false;
  final open = await confirmDialog(
    context,
    icon: Icons.lock_open_rounded,
    title: 'Allow access to music',
    message: 'Snap needs permission to read audio files on this device to build your library. '
        'Nothing leaves your device.',
    confirmLabel: 'Open settings',
  );
  if (open) await service.openSettings();
  return false;
}

/// Lets the user pick a folder and adds it to the library.
Future<void> addMusicFolder(BuildContext context, WidgetRef ref) async {
  if (!await ensureStorageAccess(context, ref)) return;
  String? path;
  try {
    path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a music folder');
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not open the folder picker');
    return;
  }
  if (path == null) return;
  if (!context.mounted) return;
  await addFolderPath(context, ref, path);
}

Future<void> addFolderPath(BuildContext context, WidgetRef ref, String path) async {
  if (!await Directory(path).exists()) {
    if (context.mounted) showSnack(context, 'That folder cannot be read');
    return;
  }
  final added = await ref.read(scanControllerProvider.notifier).addFolder(path);
  if (!context.mounted) return;
  showSnack(context, added ? 'Scanning $path' : 'That folder is already in your library');
}

/// Common Android locations offered as one-tap shortcuts.
List<(String label, String path)> suggestedFolders() {
  if (!Platform.isAndroid) return const [];
  const root = '/storage/emulated/0';
  return [
    ('Music', '$root/Music'),
    ('Downloads', '$root/Download'),
    ('Entire internal storage', root),
  ].where((e) => Directory(e.$2).existsSync()).toList();
}

class AddMusicButtons extends ConsumerWidget {
  const AddMusicButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = suggestedFolders();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: () => addMusicFolder(context, ref),
          icon: const Icon(Icons.create_new_folder_rounded),
          label: const Text('Add music folder'),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final (label, path) in suggestions)
                ActionChip(
                  avatar: const Icon(Icons.folder_rounded, size: 18),
                  label: Text(label),
                  onPressed: () async {
                    if (await ensureStorageAccess(context, ref) && context.mounted) {
                      await addFolderPath(context, ref, path);
                    }
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
