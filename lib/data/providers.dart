import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/app_database.dart';
import 'repositories/history_repository.dart';
import 'repositories/library_repository.dart';
import 'repositories/playlist_repository.dart';
import 'repositories/settings_repository.dart';

/// Overridden in `main.dart` with the opened database.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider'));

final libraryRepositoryProvider = Provider((ref) => LibraryRepository(ref.watch(databaseProvider)));
final playlistRepositoryProvider = Provider((ref) => PlaylistRepository(ref.watch(databaseProvider)));
final historyRepositoryProvider = Provider((ref) => HistoryRepository(ref.watch(databaseProvider)));
final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));
