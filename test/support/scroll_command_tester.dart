import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Future<T> pumpScrollCommand<T>(
  WidgetTester tester,
  Future<T> future, {
  int maxFrames = 30,
  Duration frameDuration = Duration.zero,
}) async {
  late T value;
  Object? error;
  StackTrace? stackTrace;
  var completed = false;
  unawaited(
    future.then<void>(
      (T result) {
        value = result;
        completed = true;
      },
      onError: (Object caught, StackTrace trace) {
        error = caught;
        stackTrace = trace;
        completed = true;
      },
    ),
  );
  for (var frame = 0; frame < maxFrames && !completed; frame += 1) {
    await tester.pump(frameDuration);
  }
  expect(
    completed,
    isTrue,
    reason: 'scroll command did not settle within $maxFrames frames',
  );
  if (error != null) {
    Error.throwWithStackTrace(error!, stackTrace!);
  }
  return value;
}
