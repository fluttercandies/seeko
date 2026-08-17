import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Internal profile/debug timeline helpers compiled out of release builds.
abstract final class SeekoTimeline {
  static SeekoTimelineTask? start(
    String name, {
    Map<String, Object?>? arguments,
  }) {
    if (kReleaseMode) {
      return null;
    }
    final developer.TimelineTask task = developer.TimelineTask(
      filterKey: 'seeko',
    )..start(name, arguments: arguments);
    return SeekoTimelineTask._(task);
  }

  static T sync<T>(
    String name,
    T Function() action, {
    Map<String, Object?>? arguments,
  }) {
    if (kReleaseMode) {
      return action();
    }
    return developer.Timeline.timeSync(
      name,
      action,
      arguments: arguments,
    );
  }
}

final class SeekoTimelineTask {
  SeekoTimelineTask._(this._task);

  developer.TimelineTask? _task;

  void finish({Map<String, Object?>? arguments}) {
    final developer.TimelineTask? task = _task;
    if (task == null) {
      return;
    }
    _task = null;
    task.finish(arguments: arguments);
  }
}
