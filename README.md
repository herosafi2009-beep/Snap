# Snap

Snap is a music player build with Flutter using Material 3 Expressive design using Claude
## Download
[Download the latest APK](https://github.com/YOUR-USERNAME/snap/releases/latest)

## Features

- **Library**: songs, albums, artists, genres and folders, with 9 sort fields and filter chips. Tags and embedded artwork are read in a background isolate. Rescans only re-read new or changed files, and removed files drop out of the library.
- **Now Playing**: large artwork that shrinks when paused, colors taken from the artwork, a slowly moving background, swipe left/right to skip, swipe down to close, and an optional spinning-record mode.
- **Playback**: gapless queue, shuffle, repeat off/all/one, background playback, notification and lock screen controls, audio focus handling, and pausing when headphones disconnect.
- **Queue**: drag to reorder, swipe to remove, undo, save as playlist. The queue and playback position are restored on the next launch.
- **Playlists**: create, rename, delete, reorder, pick custom artwork (or get a generated collage), plus 10 smart playlists that update themselves.
- **Home**: quick picks, recently played, continue listening, "Made for you", favorites, recently added and most played. You can reorder or hide sections.
- **Search** across songs, albums, artists, playlists and genres. It ignores accents and keeps optional search history.
- **Statistics**: daily, weekly and monthly listening time, when you listen, and top songs, artists and albums. All of it stays on your device.
- **Personalization**: system/light/dark theme, dynamic album colors, accent color (wallpaper, presets or custom), animation level, compact mode, and layout options.
- **File safety**: "Remove from library" hides a song without touching the file. "Delete file from device" asks you first, then Android asks you again.
- **Adaptive layouts**: bottom navigation on phones, a navigation rail on larger screens and landscape, and a sidebar, player bar and queue panel on tablets.

## Project structure

```
lib/
  core/        theme (Material 3 + album color extraction), routing, layout, services (scanner, permissions, files), utils
  data/        drift database + migrations, models, repositories
  features/    home, library, playlists, player, queue, search, favorites, statistics, settings, shell, actions
  widgets/     shared UI (artwork, track tile, media card, player buttons, collection page)
android/       manifest (permissions, audio service), MainActivity (MediaStore delete)
test/          unit, database and widget tests
tool/          make_icons.dart (turns assets/branding/snap_logo.png into launcher icons)
```

## Requirements

- Flutter 3.47+ (Dart 3.13)
- Android SDK (platform 36) and JDK 17 or 21

On this machine the toolchain is in `H:\dev`: `H:\dev\flutter`, `H:\dev\android-sdk` and `H:\dev\jdk21`. Add `H:\dev\flutter\bin` to your PATH.

## Development

```bash
flutter pub get
dart run build_runner build   # only after changing lib/data/database/app_database.dart
flutter run                   # with a phone connected (USB debugging) or an emulator
flutter analyze
flutter test
```

## Build the APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Smaller APKs, one per CPU type:

```bash
flutter build apk --release --split-per-abi
```

Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (use this one on modern phones) and the other ABIs.

The release build is signed with the debug key so it installs directly. Set up your own signing key before publishing to a store.

## Regenerating icons

```bash
dart run tool/make_icons.dart
dart run flutter_launcher_icons
```
