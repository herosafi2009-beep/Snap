import 'dart:io';

import 'package:flutter/services.dart';

enum DeleteOutcome { deleted, cancelled, failed }

/// Operations on the user's actual files. Deleting is only ever called after
/// an explicit confirmation dialog.
class FileOps {
  static const _channel = MethodChannel('snap/files');

  /// Goes through MediaStore so Android 11+ shows its own consent prompt
  /// (see MainActivity.kt). Falls back to a plain delete elsewhere.
  static Future<DeleteOutcome> deleteAudioFile(String path) async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<String>('deleteMedia', {'path': path});
        return switch (result) {
          'deleted' => DeleteOutcome.deleted,
          'cancelled' => DeleteOutcome.cancelled,
          _ => DeleteOutcome.failed,
        };
      }
      await File(path).delete();
      return DeleteOutcome.deleted;
    } catch (_) {
      return DeleteOutcome.failed;
    }
  }
}
