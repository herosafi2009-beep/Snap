import 'package:flutter/material.dart';

import '../../features/settings/settings_model.dart';

class AppTheme {
  static const defaultSeed = Color(0xFF3D8BE8); // Snap blue, from the logo

  /// Building a scheme from a seed runs Material's tonal palette maths and
  /// costs several milliseconds, which is a dropped frame if it happens while
  /// something is animating. Schemes are pure functions of their inputs, so
  /// they are cached, and [warm] can build them ahead of time.
  static final _schemes = <int, ColorScheme>{};
  static const _maxSchemes = 48;

  ///
  /// [contrast] is Material's contrast level (0 normal, 0.5 medium, 1 high).
  /// [amoled] turns dark schemes pure black (see [amoledScheme]).
  static ColorScheme scheme(
    Color seed,
    Brightness brightness, {
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
    double contrast = 0,
    bool amoled = false,
  }) {
    final black = amoled && brightness == Brightness.dark;
    final key = Object.hash(seed.toARGB32(), brightness, variant, contrast, black);
    final cached = _schemes[key];
    if (cached != null) return cached;
    var built = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: variant,
      contrastLevel: contrast,
    );
    if (black) built = amoledScheme(built);
    if (_schemes.length >= _maxSchemes) _schemes.remove(_schemes.keys.first);
    _schemes[key] = built;
    return built;
  }

  /// A dark scheme on true black: the background and lowest surfaces are
  /// #000000 (pixels switched off on an AMOLED screen) and the raised
  /// surfaces stay just light enough to tell cards, sheets and bars apart.
  /// Text and accent colours are untouched, so contrast only improves.
  static ColorScheme amoledScheme(ColorScheme s) {
    const black = Color(0xFF000000);
    Color toward(Color c, double keep) => Color.lerp(black, c, keep)!;
    return s.copyWith(
      surface: black,
      surfaceDim: black,
      surfaceContainerLowest: black,
      surfaceContainerLow: toward(s.surfaceContainerLow, 0.45),
      surfaceContainer: toward(s.surfaceContainer, 0.55),
      surfaceContainerHigh: toward(s.surfaceContainerHigh, 0.65),
      surfaceContainerHighest: toward(s.surfaceContainerHighest, 0.72),
      surfaceBright: toward(s.surfaceBright, 0.75),
    );
  }

  /// Builds the schemes a song will need before it starts playing, so the
  /// switch itself is a cache lookup. Call it when the device is idle.
  static void warm(Color seed, Brightness brightness, {double contrast = 0, bool amoled = false}) {
    scheme(seed, brightness, contrast: contrast, amoled: amoled);
    scheme(seed, brightness, variant: DynamicSchemeVariant.vibrant, contrast: contrast, amoled: amoled);
  }

  /// Assembling a theme costs about half a millisecond, and the same few are
  /// asked for over and over (light and dark for the current album, and again
  /// for the player's own colors), so finished themes are kept too.
  static final _themes = <(ColorScheme, bool, AnimationLevel, AppFont), ThemeData>{};
  static const _maxThemes = 12;

  /// [font] applies to every text style in the app, including the ones
  /// components derive for themselves (buttons, chips, dialogs, menus).
  static ThemeData build(
    ColorScheme scheme, {
    required bool compact,
    required AnimationLevel animationLevel,
    AppFont font = AppFont.system,
  }) {
    final key = (scheme, compact, animationLevel, font);
    final cached = _themes[key];
    if (cached != null) return cached;
    final built = _build(scheme, compact: compact, animationLevel: animationLevel, font: font);
    if (_themes.length >= _maxThemes) _themes.remove(_themes.keys.first);
    _themes[key] = built;
    return built;
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required bool compact,
    required AnimationLevel animationLevel,
    required AppFont font,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: font.family,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.adaptivePlatformDensity,
    );
    final text = _textTheme(base.textTheme, scheme);

    final transitions = animationLevel == AnimationLevel.off
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.android: _NoTransitionsBuilder(),
            TargetPlatform.windows: _NoTransitionsBuilder(),
            TargetPlatform.linux: _NoTransitionsBuilder(),
            TargetPlatform.macOS: _NoTransitionsBuilder(),
            TargetPlatform.iOS: _NoTransitionsBuilder(),
          })
        : const PageTransitionsTheme(builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          });

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      pageTransitionsTheme: transitions,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        selectedLabelTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        labelStyle: text.labelLarge,
        showCheckmark: true,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        constraints: const BoxConstraints(maxWidth: 640),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: text.bodyLarge,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        width: null,
      ),
      tabBarTheme: TabBarThemeData(
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: ShapeDecoration(color: scheme.secondaryContainer, shape: const StadiumBorder()),
        labelColor: scheme.onSecondaryContainer,
        unselectedLabelColor: scheme.onSurfaceVariant,
        splashBorderRadius: BorderRadius.circular(999),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: compact ? 64 : 76,
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      // The 2024 Material 3 progress style: rounded ends and a gap between
      // the filled and empty parts, matching the player's progress line.
      // The flag is marked deprecated only because false will become the
      // default; setting it is the documented way to opt in until then.
      // ignore: deprecated_member_use
      progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
      sliderTheme: SliderThemeData(
        // ignore: deprecated_member_use
        year2023: false,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.secondaryContainer,
        thumbColor: scheme.primary,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(12)),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStatePropertyAll(scheme.onSurfaceVariant.withValues(alpha: 0.4)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 1,
        highlightElevation: 2,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? const Icon(Icons.check_rounded) : null,
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    TextStyle? tight(TextStyle? s, FontWeight w, double spacing) =>
        s?.copyWith(fontWeight: w, letterSpacing: spacing);
    return base.copyWith(
      displayLarge: tight(base.displayLarge, FontWeight.w700, -1.2),
      displayMedium: tight(base.displayMedium, FontWeight.w700, -1.0),
      displaySmall: tight(base.displaySmall, FontWeight.w700, -0.6),
      headlineLarge: tight(base.headlineLarge, FontWeight.w700, -0.6),
      headlineMedium: tight(base.headlineMedium, FontWeight.w700, -0.4),
      headlineSmall: tight(base.headlineSmall, FontWeight.w700, -0.2),
      titleLarge: tight(base.titleLarge, FontWeight.w600, -0.1),
      titleMedium: tight(base.titleMedium, FontWeight.w600, 0),
      titleSmall: tight(base.titleSmall, FontWeight.w600, 0),
      labelLarge: tight(base.labelLarge, FontWeight.w600, 0.1),
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return child;
  }
}
