import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A notifier holding a single value that widgets can replace.
class SimpleNotifier<T> extends Notifier<T> {
  SimpleNotifier(this._initial);
  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}
