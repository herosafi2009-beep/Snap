import 'package:intl/intl.dart';

class Format {
  static String duration(Duration d) {
    final negative = d.isNegative;
    final abs = d.abs();
    final h = abs.inHours;
    final m = abs.inMinutes.remainder(60);
    final s = abs.inSeconds.remainder(60);
    final core = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
    return negative ? '-$core' : core;
  }

  static String durationMs(int ms) => duration(Duration(milliseconds: ms));

  /// "2 h 14 min", "45 min", "30 s".
  static String totalTime(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inHours >= 1) {
      final minutes = d.inMinutes.remainder(60);
      return minutes == 0 ? '${d.inHours} h' : '${d.inHours} h $minutes min';
    }
    if (d.inMinutes >= 1) return '${d.inMinutes} min';
    return '${d.inSeconds} s';
  }

  static String count(int n, String singular, [String? plural]) {
    final word = n == 1 ? singular : (plural ?? '${singular}s');
    return '${NumberFormat.decimalPattern().format(n)} $word';
  }

  static String songs(int n) => count(n, 'song');

  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
  }

  static String greeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String relativeDate(DateTime date, [DateTime? now]) {
    final clock = now ?? DateTime.now();
    final diff = clock.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat.yMMMd().format(date);
  }
}
