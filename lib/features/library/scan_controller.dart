import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/services/app_paths.dart';
import '../../core/services/library_scanner.dart';
import '../../core/services/permission_service.dart';
import '../../data/providers.dart';
import '../settings/settings_controller.dart';

enum ScanPhase { idle, discovering, reading, finishing }

class ScanState {
  const ScanState({
    this.phase = ScanPhase.idle,
    this.processed = 0,
    this.total = 0,
    this.current,
    this.lastResult,
    this.error,
  });

  final ScanPhase phase;
  final int processed;
  final int total;
  final String? current;
  final ScanResult? lastResult;
  final String? error;

  bool get running => phase != ScanPhase.idle;
  double? get progress => phase == ScanPhase.reading && total > 0 ? processed / total : null;

  ScanState copyWith({
    ScanPhase? phase,
    int? processed,
    int? total,
    String? current,
    ScanResult? lastResult,
    String? error,
  }) {
    return ScanState(
      phase: phase ?? this.phase,
      processed: processed ?? this.processed,
      total: total ?? this.total,
      current: current ?? this.current,
      lastResult: lastResult ?? this.lastResult,
      error: error,
    );
  }
}

class ScanResult {
  const ScanResult({
    required this.added,
    required this.updated,
    required this.removed,
    required this.failed,
    required this.unreadableRoots,
    required this.finishedAt,
  });
  final int added;
  final int updated;
  final int removed;
  final int failed;
  final List<String> unreadableRoots;
  final DateTime finishedAt;

  String get summary {
    final parts = <String>[
      if (added > 0) '$added added',
      if (updated > 0) '$updated updated',
      if (removed > 0) '$removed removed',
      if (failed > 0) '$failed unreadable',
    ];
    return parts.isEmpty ? 'Library is up to date' : parts.join(' · ');
  }
}

final permissionServiceProvider = Provider((ref) => const PermissionService());

final storageAccessProvider = FutureProvider<StorageAccess>((ref) {
  return ref.watch(permissionServiceProvider).status();
});

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);

class ScanController extends Notifier<ScanState> {
  Isolate? _isolate;
  ReceivePort? _port;
  Completer<void>? _done;

  @override
  ScanState build() {
    ref.onDispose(_stopIsolate);
    return const ScanState();
  }

  /// Adds a folder to the library and scans it. Returns false when the folder
  /// was already present.
  Future<bool> addFolder(String path) async {
    final repo = ref.read(libraryRepositoryProvider);
    final normalized = p.normalize(path);
    final existing = await repo.folders();
    if (existing.any((f) => p.equals(f.path, normalized) || p.isWithin(f.path, normalized))) {
      return false;
    }
    // A new parent folder replaces its now-redundant children.
    for (final f in existing.where((f) => p.isWithin(normalized, f.path))) {
      await repo.removeFolder(f.path);
    }
    await repo.addFolder(normalized);
    unawaited(scan());
    return true;
  }

  Future<void> removeFolder(String path) async {
    await ref.read(libraryRepositoryProvider).removeFolder(path);
    unawaited(scan());
  }

  /// Incremental scan: only new or modified files are read. [force] re-reads
  /// everything (full rescan).
  Future<void> scan({bool force = false}) async {
    if (state.running) return _done?.future;
    final repo = ref.read(libraryRepositoryProvider);
    final folders = await repo.folders();

    if (folders.isNotEmpty && Platform.isAndroid) {
      final access = await ref.read(permissionServiceProvider).status();
      if (access != StorageAccess.granted) {
        ref.invalidate(storageAccessProvider);
        state = state.copyWith(error: 'Storage permission is required to read your music.');
        return;
      }
    }

    _done = Completer<void>();
    state = const ScanState(phase: ScanPhase.discovering);
    final stopwatch = Stopwatch()..start();

    try {
      final index = await repo.loadIndex();
      final settings = ref.read(settingsProvider);
      final port = ReceivePort();
      _port = port;
      final request = ScanRequest(
        roots: folders.map((f) => f.path).toList(),
        index: index,
        artDir: AppPaths.instance.artworkDir.path,
        extensions: supportedExtensions,
        minDurationMs: settings.minTrackSeconds * 1000,
        force: force,
        sendPort: port.sendPort,
      );
      _isolate = await Isolate.spawn(scanLibraryIsolate, request, errorsAreFatal: true, onExit: port.sendPort, onError: port.sendPort);

      // Database writes are serialised so batches never interleave.
      var writes = Future<void>.value();
      await for (final message in port) {
        if (message is ScanProgressMessage) {
          state = state.copyWith(
            phase: message.discovering ? ScanPhase.discovering : ScanPhase.reading,
            processed: message.processed,
            total: message.total,
            current: message.current,
          );
        } else if (message is ScanBatchMessage) {
          writes = writes.then((_) => repo.upsertScanned(message.tracks));
        } else if (message is ScanDoneMessage) {
          state = state.copyWith(phase: ScanPhase.finishing);
          await writes;
          await repo.deleteByPaths(message.removedPaths);
          await _pruneArtwork();
          state = ScanState(
            lastResult: ScanResult(
              added: message.added,
              updated: message.updated,
              removed: message.removedPaths.length,
              failed: message.failed,
              unreadableRoots: message.unreadableRoots,
              finishedAt: DateTime.now(),
            ),
          );
          debugPrint('Scan finished in ${stopwatch.elapsedMilliseconds} ms');
          break;
        } else if (message == null || message is List) {
          // Isolate exited (null) or crashed (List with error + stack).
          await writes;
          state = ScanState(
            lastResult: state.lastResult,
            error: message is List ? 'Scan stopped: ${message.first}' : null,
          );
          break;
        }
      }
    } catch (e) {
      state = ScanState(lastResult: state.lastResult, error: 'Scan failed: $e');
    } finally {
      _stopIsolate();
      _done?.complete();
      _done = null;
    }
  }

  void cancel() {
    if (!state.running) return;
    _stopIsolate();
    state = ScanState(lastResult: state.lastResult);
  }

  void _stopIsolate() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
  }

  Future<void> _pruneArtwork() async {
    try {
      final referenced = await ref.read(libraryRepositoryProvider).referencedArtPaths();
      final normalized = referenced.map(p.normalize).toSet();
      for (final dir in [AppPaths.instance.artworkDir, AppPaths.instance.customArtDir]) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is File && !normalized.contains(p.normalize(entity.path))) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Clears decoded images from memory and the extracted artwork on disk,
  /// then rebuilds artwork with a full rescan.
  Future<void> clearImageCache() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    final repo = ref.read(libraryRepositoryProvider);
    await repo.invalidateIndex(clearArt: true);
    final dir = AppPaths.instance.artworkDir;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } catch (_) {}
    await scan(force: true);
  }
}
