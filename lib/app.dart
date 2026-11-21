import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routing/app_router.dart';
import 'core/theme/boot_colors.dart';
import 'core/theme/theme_providers.dart';
import 'data/providers.dart';
import 'features/library/scan_controller.dart';
import 'features/player/player_controller.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_model.dart';
import 'features/shell/boot_curtain.dart';
import 'features/shell/global_shortcuts.dart';

class SnapApp extends ConsumerStatefulWidget {
  const SnapApp({super.key, required this.startPage, this.bootColors});
  final StartPage startPage;

  /// Start-up colors saved by the previous session.
  final BootColors? bootColors;

  @override
  ConsumerState<SnapApp> createState() => _SnapAppState();
}

class _SnapAppState extends ConsumerState<SnapApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(widget.startPage);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await ref.read(playerControllerProvider.notifier).restore();
    // Pick up files added or removed while the app was closed, without
    // competing with the first frames.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final folders = await ref.read(libraryRepositoryProvider).folders();
    if (folders.isNotEmpty && mounted) unawaited(ref.read(scanControllerProvider.notifier).scan());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The user may have granted storage access in system settings.
      ref.invalidate(storageAccessProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Snap',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: themeMode,
      // No cross-fade of the whole theme. Lerping a ThemeData rebuilds every
      // widget in the app on every frame of the fade, and with album colors
      // that happened on each song change, right as the song-change
      // animations ran: the main cause of stutter there. The new colours
      // apply in one frame, timed by appSeedProvider to land after those
      // animations; the player fades its own colours cheaply.
      themeAnimationDuration: Duration.zero,
      routerConfig: _router,
      builder: (context, child) => BootCurtain(
        saved: widget.bootColors,
        child: GlobalShortcuts(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
