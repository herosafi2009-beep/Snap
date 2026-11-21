import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What Android reports about spatial audio right now.
///
/// Snap does not process audio itself: playback goes to Android through
/// ExoPlayer, and the platform decides whether to spatialize it for the
/// current output. This is only what the platform says, so the app can show
/// the truth instead of a claim.
class SpatialAudioStatus {
  const SpatialAudioStatus({
    this.platformSupported = false,
    this.available = false,
    this.enabled = false,
    this.headTracking = false,
    this.multichannel = false,
  });

  /// Android 12L or newer, where the Spatializer exists at all.
  final bool platformSupported;

  /// The device can spatialize for whatever is playing the audio right now
  /// (its speakers, the connected headphones).
  final bool available;

  /// Spatialization is switched on for that output.
  final bool enabled;

  /// The connected headphones report head tracking.
  final bool headTracking;

  /// Multichannel content (5.1, or Dolby Atmos carried in E-AC-3 JOC) would
  /// be spatialized rather than folded down to stereo.
  final bool multichannel;

  bool get active => available && enabled;

  factory SpatialAudioStatus.fromMap(Map<Object?, Object?> map) {
    bool flag(String key) => map[key] == true;
    return SpatialAudioStatus(
      platformSupported: flag('platformSupported'),
      available: flag('available'),
      enabled: flag('enabled'),
      headTracking: flag('headTracking'),
      multichannel: flag('multichannel'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpatialAudioStatus &&
      other.platformSupported == platformSupported &&
      other.available == available &&
      other.enabled == enabled &&
      other.headTracking == headTracking &&
      other.multichannel == multichannel;

  @override
  int get hashCode => Object.hash(platformSupported, available, enabled, headTracking, multichannel);
}

class SpatialAudioService {
  static const _channel = MethodChannel('snap/spatial');
  static const _events = EventChannel('snap/spatial/events');

  Future<SpatialAudioStatus> status() async {
    if (!Platform.isAndroid) return const SpatialAudioStatus();
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      return result == null ? const SpatialAudioStatus() : SpatialAudioStatus.fromMap(result);
    } on PlatformException {
      return const SpatialAudioStatus();
    } on MissingPluginException {
      return const SpatialAudioStatus();
    }
  }

  /// Updates as headphones come and go, or the setting is toggled in system
  /// settings while Snap is open.
  Stream<SpatialAudioStatus> watch() {
    if (!Platform.isAndroid) return Stream.value(const SpatialAudioStatus());
    return _events
        .receiveBroadcastStream()
        .map((event) => event is Map<Object?, Object?> ? SpatialAudioStatus.fromMap(event) : const SpatialAudioStatus())
        .handleError((Object _) {});
  }
}

final spatialAudioServiceProvider = Provider((ref) => SpatialAudioService());

/// Live spatial audio status, starting from a one-off read so the setting
/// shows something immediately.
final spatialAudioProvider = StreamProvider<SpatialAudioStatus>((ref) async* {
  final service = ref.watch(spatialAudioServiceProvider);
  yield await service.status();
  yield* service.watch();
});
