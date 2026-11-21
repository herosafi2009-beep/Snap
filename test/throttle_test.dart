import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/utils/throttle.dart';

void main() {
  test('throttleLatest emits first and latest events only', () async {
    final source = StreamController<int>();
    final received = <int>[];
    final sub = throttleLatest(source.stream, const Duration(milliseconds: 60)).listen(received.add);
    for (var i = 1; i <= 5; i++) {
      source.add(i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, [1, 5]);
    source.add(6);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(received, [1, 5, 6]);
    await source.close();
    await sub.cancel();
  });
}
