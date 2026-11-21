import 'dart:io';

import 'package:flutter/widgets.dart';

/// Material 3 window size classes.
enum WindowSize { compact, medium, expanded, large, extraLarge }

extension WindowSizeX on WindowSize {
  bool get isCompact => this == WindowSize.compact;
  bool operator >=(WindowSize other) => index >= other.index;
}

class Breakpoints {
  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width < 600) return WindowSize.compact;
    if (width < 840) return WindowSize.medium;
    if (width < 1200) return WindowSize.expanded;
    if (width < 1600) return WindowSize.large;
    return WindowSize.extraLarge;
  }

  static bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Horizontal page padding that grows with the window.
  static double pagePadding(BuildContext context) => switch (of(context)) {
        WindowSize.compact => 16,
        WindowSize.medium => 24,
        _ => 32,
      };
}
