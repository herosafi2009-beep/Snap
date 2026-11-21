import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:snap/features/library/library_logic.dart';
import 'package:snap/features/search/search_logic.dart';
import 'package:snap/features/settings/settings_model.dart';

import 'test_utils.dart';

void main() {
  group('sorting', () {
    test('title sort ignores case and a leading "The"', () {
      final tracks = [makeTrack(title: 'zebra'), makeTrack(title: 'The Apple'), makeTrack(title: 'banana')];
      final sorted = LibraryLogic.sortTracks(tracks, const SortSpec(SortField.title, true));
      expect(sorted.map((t) => t.title), ['The Apple', 'banana', 'zebra']);
    });

    test('descending last played keeps never-played songs last', () {
      final tracks = [
        makeTrack(title: 'never'),
        makeTrack(title: 'old', lastPlayed: DateTime(2020)),
        makeTrack(title: 'new', lastPlayed: DateTime(2024)),
      ];
      final desc = LibraryLogic.sortTracks(tracks, const SortSpec(SortField.lastPlayed, false));
      expect(desc.map((t) => t.title), ['new', 'old', 'never']);
      final asc = LibraryLogic.sortTracks(tracks, const SortSpec(SortField.lastPlayed, true));
      expect(asc.last.title, 'never');
    });

    test('album sort uses disc then track number', () {
      final tracks = [
        makeTrack(title: 'c', discNumber: 2, trackNumber: 1),
        makeTrack(title: 'b', discNumber: 1, trackNumber: 2),
        makeTrack(title: 'a', discNumber: 1, trackNumber: 1),
      ];
      final sorted = LibraryLogic.sortTracks(tracks, const SortSpec(SortField.album, true));
      expect(sorted.map((t) => t.title), ['a', 'b', 'c']);
    });
  });

  group('filtering', () {
    final now = DateTime(2024, 6, 1);
    final tracks = [
      makeTrack(title: 'fav', favorite: true, playCount: 3, dateAdded: DateTime(2024, 5, 25)),
      makeTrack(title: 'unplayed', genre: 'Jazz; Soul', dateAdded: DateTime(2023)),
      makeTrack(title: 'played', artist: 'Other', playCount: 1, dateAdded: DateTime(2023)),
    ];

    test('combines filters', () {
      expect(LibraryLogic.filterTracks(tracks, const LibraryFilter(favorites: true), now: now).single.title, 'fav');
      expect(LibraryLogic.filterTracks(tracks, const LibraryFilter(played: false), now: now).single.title, 'unplayed');
      expect(LibraryLogic.filterTracks(tracks, const LibraryFilter(recentlyAdded: true), now: now).single.title, 'fav');
      expect(LibraryLogic.filterTracks(tracks, const LibraryFilter(genre: 'soul'), now: now).single.title, 'unplayed');
      expect(LibraryLogic.filterTracks(tracks, const LibraryFilter(artist: 'other', played: true), now: now).single.title,
          'played');
    });
  });

  group('grouping', () {
    test('compilations without album artist stay together per folder', () {
      final tracks = [
        makeTrack(title: '1', album: 'Hits', artist: 'A', folder: '/m/hits'),
        makeTrack(title: '2', album: 'Hits', artist: 'B', folder: '/m/hits'),
        makeTrack(title: '3', album: 'Hits', artist: 'C', folder: '/m/other-hits'),
      ];
      final albums = LibraryLogic.groupAlbums(tracks);
      expect(albums.length, 2);
      final big = albums.firstWhere((a) => a.tracks.length == 2);
      expect(big.artist, 'Various artists');
    });

    test('album artist tag groups across folders', () {
      final tracks = [
        makeTrack(album: 'X', albumArtist: 'Band', folder: '/a'),
        makeTrack(album: 'X', albumArtist: 'Band', folder: '/b'),
      ];
      expect(LibraryLogic.groupAlbums(tracks).single.artist, 'Band');
    });

    test('multi-value artist tags are split', () {
      final artists = LibraryLogic.groupArtists([makeTrack(artist: 'Alice; Bob'), makeTrack(artist: 'bob')]);
      expect(artists.map((a) => a.name), containsAll(['Alice', 'Bob']));
      expect(artists.firstWhere((a) => a.key == 'bob').tracks.length, 2);
    });

    test('folder tree nests folders under their music root', () {
      // Paths use the host's separator, as they do when read from disk.
      final root = p.normalize('/music');
      final elsewhere = p.normalize('/elsewhere');
      final tracks = [
        makeTrack(folder: p.join(root, 'rock', 'album1')),
        makeTrack(folder: p.join(root, 'rock', 'album2')),
        makeTrack(folder: root),
        makeTrack(folder: elsewhere),
      ];
      final tree = LibraryLogic.buildFolderTree(tracks, [root]);
      final music = tree.firstWhere((n) => n.path == root);
      expect(music.totalTracks, 3);
      expect(music.subfolders.single.name, 'rock');
      expect(music.subfolders.single.subfolders.length, 2);
      expect(tree.any((n) => n.path == elsewhere), isTrue);
      expect(LibraryLogic.findFolder(tree, p.join(root, 'rock', 'album2'))?.tracks.length, 1);
    });

    test('handles empty libraries', () {
      expect(LibraryLogic.groupAlbums([]), isEmpty);
      expect(LibraryLogic.buildFolderTree([], ['/music']), isEmpty);
    });
  });

  group('search', () {
    final tracks = [
      makeTrack(title: 'Halo', artist: 'Beyoncé', playCount: 10),
      makeTrack(title: 'Hello', artist: 'Adele'),
      makeTrack(title: 'Say Hello', artist: 'Someone'),
    ];

    List<String> titles(String q) => SearchLogic.search(
          query: q,
          tracks: tracks,
          albums: const [],
          artists: const [],
          genres: const [],
          playlists: const [],
        ).tracks.map((t) => t.title).toList();

    test('is accent and case insensitive', () => expect(titles('BEYONCE'), ['Halo']));
    test('requires every word', () => expect(titles('hello adele'), ['Hello']));
    test('ranks prefix matches first', () => expect(titles('hello'), ['Hello', 'Say Hello']));
    test('empty query returns nothing', () => expect(titles('   '), isEmpty));
  });
}
