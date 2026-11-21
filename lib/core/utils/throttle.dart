import 'dart:async';

/// Emits the first event immediately, then at most one event (the latest)
/// per [window]. Used to keep bursts of database updates, e.g. while a large
/// library is scanned, from rebuilding the UI dozens of times per second.
Stream<T> throttleLatest<T>(Stream<T> source, Duration window) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? timer;
  T? pending;
  var hasPending = false;
  var sourceDone = false;

  void flush() {
    if (hasPending) {
      controller.add(pending as T);
      hasPending = false;
      pending = null;
      timer = Timer(window, flush);
    } else {
      timer = null;
      if (sourceDone) controller.close();
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (event) {
          if (timer == null) {
            controller.add(event);
            timer = Timer(window, flush);
          } else {
            pending = event;
            hasPending = true;
          }
        },
        onError: controller.addError,
        onDone: () {
          sourceDone = true;
          if (timer == null) controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      timer?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
