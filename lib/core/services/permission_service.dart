import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum StorageAccess { granted, denied, permanentlyDenied }

/// Android needs READ_MEDIA_AUDIO (13+) or READ_EXTERNAL_STORAGE (12 and
/// lower) to read music files. Desktop platforms need nothing.
class PermissionService {
  const PermissionService();

  Future<StorageAccess> status() async {
    if (!Platform.isAndroid) return StorageAccess.granted;
    try {
      final audio = await Permission.audio.status;
      final storage = await Permission.storage.status;
      if (audio.isGranted || storage.isGranted) return StorageAccess.granted;
      if (audio.isPermanentlyDenied && storage.isPermanentlyDenied) {
        return StorageAccess.permanentlyDenied;
      }
      return StorageAccess.denied;
    } catch (_) {
      return StorageAccess.denied;
    }
  }

  Future<StorageAccess> request() async {
    if (!Platform.isAndroid) return StorageAccess.granted;
    try {
      // Requesting both lets the plugin pick whichever applies to the OS
      // version; the one that does not apply simply stays denied.
      final results = await [Permission.audio, Permission.storage].request();
      if (results.values.any((s) => s.isGranted || s.isLimited)) return StorageAccess.granted;
      if (results.values.every((s) => s.isPermanentlyDenied || s.isRestricted)) {
        return StorageAccess.permanentlyDenied;
      }
      return StorageAccess.denied;
    } catch (_) {
      return StorageAccess.denied;
    }
  }

  Future<void> openSettings() => openAppSettings();
}
