import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum NotificationAccess { granted, denied, permanentlyDenied }

/// The media notification (and apps that mirror it, such as lock screen and
/// "dynamic island" style apps) needs notification permission on Android 13+,
/// and notifications must not be switched off for the app on older versions.
class NotificationPermission {
  static bool _askedThisSession = false;

  static Future<NotificationAccess> status() async {
    if (!Platform.isAndroid) return NotificationAccess.granted;
    try {
      final s = await Permission.notification.status;
      if (s.isGranted || s.isLimited || s.isProvisional) return NotificationAccess.granted;
      if (s.isPermanentlyDenied || s.isRestricted) return NotificationAccess.permanentlyDenied;
      return NotificationAccess.denied;
    } catch (_) {
      return NotificationAccess.granted;
    }
  }

  /// Asks once per app session, the first time music starts playing.
  /// Returns the resulting access, or null when nothing needed to be done.
  static Future<NotificationAccess?> ensureForPlayback() async {
    if (!Platform.isAndroid || _askedThisSession) return null;
    _askedThisSession = true;
    var access = await status();
    if (access == NotificationAccess.granted) return null;
    if (access == NotificationAccess.denied) {
      try {
        final result = await Permission.notification.request();
        access = result.isGranted
            ? NotificationAccess.granted
            : (result.isPermanentlyDenied ? NotificationAccess.permanentlyDenied : NotificationAccess.denied);
      } catch (_) {}
    }
    return access;
  }

  static Future<void> openSettings() => openAppSettings();
}
