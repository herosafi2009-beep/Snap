import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolved application directories. Initialised once at startup.
class AppPaths {
  AppPaths._(this.support);

  final Directory support;

  static late AppPaths instance;

  static Future<AppPaths> init() async {
    final dir = await getApplicationSupportDirectory();
    instance = AppPaths._(dir);
    for (final d in [instance.artworkDir, instance.playlistArtDir, instance.customArtDir]) {
      if (!d.existsSync()) d.createSync(recursive: true);
    }
    return instance;
  }

  Directory get artworkDir => Directory(p.join(support.path, 'artwork'));
  Directory get playlistArtDir => Directory(p.join(support.path, 'playlist_art'));

  /// Artwork chosen by the user for individual songs. Kept apart from the
  /// scanner's cache so clearing the image cache never removes it.
  Directory get customArtDir => Directory(p.join(support.path, 'custom_art'));

  /// Size in bytes of every file below [dir].
  static Future<int> directorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
