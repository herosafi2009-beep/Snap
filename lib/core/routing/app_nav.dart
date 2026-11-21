import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Navigation helpers. Detail pages open inside the section the user is
/// currently in, so the navigation bar and mini player stay visible.
class AppNav {
  /// Bottom navigation sections, in order.
  static const branches = ['home', 'library', 'search', 'settings'];
  static const searchBranch = 2;

  /// Updated by the shell whenever the selected branch changes.
  static int currentBranch = 0;

  /// True from the moment the player starts to open until it has shrunk
  /// all the way back into the music pill. The pill hides meanwhile, since
  /// the player draws an exact copy of it at both ends of the trip.
  static final playerOpen = ValueNotifier<bool>(false);

  /// The music pill's card. The player measures it to grow out of and
  /// shrink into exactly the pill's place.
  static final pillKey = GlobalKey(debugLabel: 'music pill');

  /// Set by the open player: brings it back to full screen if it is on its
  /// way into the pill when the pill is tapped.
  static VoidCallback? expandPlayer;

  /// True while the open player fully covers the app. The app behind is
  /// then neither painted nor ticking, so the player has the whole frame
  /// budget to itself; it is still laid out, so the pill can be measured.
  static final playerCovers = ValueNotifier<bool>(false);

  /// Incremented to ask the Search section to focus its field.
  static final searchFocusRequests = ValueNotifier<int>(0);

  static String encodeKey(String key) => base64Url.encode(utf8.encode(key));
  static String decodeKey(String encoded) {
    try {
      return utf8.decode(base64Url.decode(encoded));
    } catch (_) {
      return encoded;
    }
  }

  static GoRouter _routerLeavingPlayer(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.routerDelegate.currentConfiguration.uri.path.startsWith('/now-playing')) router.pop();
    return router;
  }

  static void _push(BuildContext context, String subpath) {
    _routerLeavingPlayer(context).push('/${branches[currentBranch]}/$subpath');
  }

  static void album(BuildContext context, String key) => _push(context, 'album/${encodeKey(key)}');
  static void artist(BuildContext context, String name) =>
      _push(context, 'artist/${encodeKey(name.toLowerCase())}');
  static void genre(BuildContext context, String name) => _push(context, 'genre/${encodeKey(name.toLowerCase())}');
  static void folder(BuildContext context, String path) => _push(context, 'folder/${encodeKey(path)}');
  static void playlist(BuildContext context, int id) => _push(context, 'playlist/$id');
  static void smart(BuildContext context, String kind) => _push(context, 'smart/$kind');
  static void statistics(BuildContext context) => _push(context, 'statistics');
  static void settingsPage(BuildContext context, String page) => _push(context, 'settings-$page');

  /// Opens the Search section and focuses its field.
  static void search(BuildContext context) {
    _routerLeavingPlayer(context).go('/search');
    searchFocusRequests.value++;
  }

  /// Opens Library on a tab: folders, artists, songs, playlists, liked, queue.
  static void libraryTab(BuildContext context, String tab) {
    // The counter makes repeated requests for the same tab distinguishable
    // from ordinary rebuilds of the Library route.
    _libraryRequests++;
    _routerLeavingPlayer(context).go('/library?tab=$tab&n=$_libraryRequests');
  }

  static int _libraryRequests = 0;

  static void nowPlaying(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.routerDelegate.currentConfiguration.uri.path.startsWith('/now-playing')) {
      expandPlayer?.call();
      return;
    }
    router.push('/now-playing');
  }

  static void branch(BuildContext context, int index) => GoRouter.of(context).go('/${branches[index]}');
}
