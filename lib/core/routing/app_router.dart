import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/library/collection_screens.dart';
import '../../features/library/library_screen.dart';
import '../../features/player/now_playing_screen.dart';
import '../../features/player/player_route.dart';
import '../../features/playlists/playlist_detail_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../features/settings/settings_pages.dart';
import '../../features/settings/settings_model.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/statistics/statistics_screen.dart';
import '../../widgets/motion.dart';
import 'app_nav.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter buildRouter(StartPage startPage) {
  final initial = switch (startPage) {
    StartPage.home => '/home',
    StartPage.library => '/library',
    StartPage.playlists => '/library?tab=playlists',
    StartPage.favorites => '/library?tab=liked',
  };

  List<RouteBase> details() => [
        GoRoute(
          path: 'album/:key',
          builder: (_, s) => AlbumScreen(albumKey: AppNav.decodeKey(s.pathParameters['key']!)),
        ),
        GoRoute(
          path: 'artist/:key',
          builder: (_, s) => ArtistScreen(artistKey: AppNav.decodeKey(s.pathParameters['key']!)),
        ),
        GoRoute(
          path: 'genre/:key',
          builder: (_, s) => GenreScreen(genreKey: AppNav.decodeKey(s.pathParameters['key']!)),
        ),
        GoRoute(
          path: 'folder/:key',
          builder: (_, s) => FolderScreen(path: AppNav.decodeKey(s.pathParameters['key']!)),
        ),
        GoRoute(
          path: 'playlist/:id',
          builder: (_, s) => PlaylistDetailScreen(playlistId: int.tryParse(s.pathParameters['id']!) ?? -1),
        ),
        GoRoute(path: 'smart/:kind', builder: (_, s) => SmartPlaylistScreen(kindName: s.pathParameters['kind']!)),
        GoRoute(path: 'statistics', builder: (_, _) => const StatisticsScreen()),
        GoRoute(path: 'settings-appearance', builder: (_, _) => const AppearanceSettingsPage()),
        GoRoute(path: 'settings-playback', builder: (_, _) => const PlaybackSettingsPage()),
        GoRoute(path: 'settings-library', builder: (_, _) => const LibrarySettingsPage()),
        GoRoute(path: 'settings-home', builder: (_, _) => const HomeSectionsSettingsPage()),
        GoRoute(path: 'settings-storage', builder: (_, _) => const StorageSettingsPage()),
        GoRoute(path: 'settings-shortcuts', builder: (_, _) => const ShortcutsSettingsPage()),
        GoRoute(path: 'settings-about', builder: (_, _) => const AboutScreen()),
      ];

  StatefulShellBranch branch(String name, Widget Function(GoRouterState state) screen) => StatefulShellBranch(
        routes: [
          GoRoute(path: '/$name', builder: (_, state) => screen(state), routes: details()),
        ],
      );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initial,
    routes: [
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        // Sections fade through instead of cutting.
        navigatorContainerBuilder: (context, shell, children) =>
            BranchSwitcher(currentIndex: shell.currentIndex, children: children),
        branches: [
          branch('home', (_) => const HomeScreen()),
          branch(
            'library',
            (state) => LibraryScreen(
              requestedTab: state.uri.queryParameters['tab'],
              requestId: state.uri.queryParameters['n'],
            ),
          ),
          branch('search', (_) => const SearchScreen()),
          branch('settings', (_) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: '/now-playing',
        parentNavigatorKey: rootNavigatorKey,
        // The player grows out of the music pill and shrinks back into it.
        pageBuilder: (context, state) => PlayerPage(key: state.pageKey, child: const NowPlayingScreen()),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
}
