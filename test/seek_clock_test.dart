import 'package:flutter_test/flutter_test.dart';
import 'package:snap/features/player/widgets/seek_bar.dart';

void main() {
  late Duration now;
  SeekClock clockAt(Duration start) {
    now = Duration.zero;
    final clock = SeekClock(now: () => now)
      ..setPlaying(true)
      ..report(start);
    return clock;
  }

  void advance(Duration by) => now += by;

  test('the position keeps moving between reports', () {
    final clock = clockAt(const Duration(seconds: 10));
    expect(clock.position, const Duration(seconds: 10));
    advance(const Duration(milliseconds: 100));
    expect(clock.position, const Duration(milliseconds: 10100));
    advance(const Duration(milliseconds: 150));
    expect(clock.position, const Duration(milliseconds: 10250));
  });

  test('a paused song stays where it is', () {
    final clock = clockAt(const Duration(seconds: 10))..setPlaying(false);
    advance(const Duration(seconds: 5));
    expect(clock.position, const Duration(seconds: 10));
    clock.setPlaying(true);
    advance(const Duration(seconds: 1));
    expect(clock.position, const Duration(seconds: 11));
  });

  test('reporting jitter is eased away, never jumped backwards', () {
    final clock = clockAt(const Duration(seconds: 10));
    advance(const Duration(milliseconds: 200));
    // The player reports slightly behind where the clock guessed.
    clock.report(const Duration(milliseconds: 10150));
    final corrected = clock.position;
    expect(corrected, lessThan(const Duration(milliseconds: 10200)));
    expect(corrected, greaterThan(const Duration(milliseconds: 10150)),
        reason: 'only a fraction of the difference is taken back, so the line does not stall');
    advance(const Duration(milliseconds: 100));
    expect(clock.position, greaterThan(corrected), reason: 'and it keeps moving forwards');
  });

  test('a seek or a new song snaps straight there', () {
    final clock = clockAt(const Duration(seconds: 10));
    clock.report(const Duration(minutes: 3));
    expect(clock.position, const Duration(minutes: 3));
    clock.report(Duration.zero);
    expect(clock.position, Duration.zero);
  });

  test('a released drag holds its position until the player catches up', () {
    final clock = clockAt(const Duration(seconds: 10))..jumpTo(const Duration(seconds: 90));
    expect(clock.position, const Duration(seconds: 90));
    advance(const Duration(milliseconds: 50));
    // A stale report from before the seek does not drag the line back.
    clock.report(const Duration(seconds: 10));
    expect(clock.position, const Duration(seconds: 10),
        reason: 'a difference that large is treated as the new truth');
  });

  test('fractions are clamped to the song', () {
    final clock = clockAt(const Duration(seconds: 30));
    expect(clock.fractionOf(const Duration(minutes: 1)), closeTo(0.5, 0.001));
    expect(clock.fractionOf(Duration.zero), 0);
    clock.report(const Duration(minutes: 5));
    expect(clock.fractionOf(const Duration(minutes: 1)), 1);
  });
}
