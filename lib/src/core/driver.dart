import 'dart:async';

import 'capability.dart';
import 'command_model.dart';
import 'logical_geometry.dart';
import 'motion.dart';
import 'scroll_target.dart';

enum ScrollResolutionStatus {
  resolved,
  targetNotLoaded,
  targetDeleted,
  targetOutOfRange,
  resolverRejected,
  unsupported,
}

/// Resolves an application-defined [CustomScrollTarget] into target geometry.
typedef ScrollCustomTargetResolver = FutureOr<ScrollCustomTargetResolution>
    Function(CustomScrollTarget target);

/// Typed result returned by [ScrollCustomTargetResolver].
final class ScrollCustomTargetResolution {
  const ScrollCustomTargetResolution.resolved({
    required this.targetInterval,
    this.mode = ScrollResolutionMode.exact,
    this.dataRevision,
    this.diagnostics,
  }) : status = ScrollResolutionStatus.resolved;

  const ScrollCustomTargetResolution._failure(this.status)
      : targetInterval = null,
        mode = ScrollResolutionMode.exact,
        dataRevision = null,
        diagnostics = null;

  const ScrollCustomTargetResolution.targetNotLoaded()
      : this._failure(ScrollResolutionStatus.targetNotLoaded);
  const ScrollCustomTargetResolution.targetDeleted()
      : this._failure(ScrollResolutionStatus.targetDeleted);
  const ScrollCustomTargetResolution.targetOutOfRange()
      : this._failure(ScrollResolutionStatus.targetOutOfRange);
  const ScrollCustomTargetResolution.resolverRejected({
    Map<String, Object?>? diagnostics,
  }) : this._failureWithDiagnostics(
          ScrollResolutionStatus.resolverRejected,
          diagnostics,
        );
  const ScrollCustomTargetResolution._failureWithDiagnostics(
    this.status,
    this.diagnostics,
  )   : targetInterval = null,
        mode = ScrollResolutionMode.exact,
        dataRevision = null;
  const ScrollCustomTargetResolution.unsupported()
      : this._failure(ScrollResolutionStatus.unsupported);

  final ScrollResolutionStatus status;
  final LogicalInterval? targetInterval;
  final ScrollResolutionMode mode;
  final int? dataRevision;
  final Map<String, Object?>? diagnostics;

  bool get isResolved => status == ScrollResolutionStatus.resolved;
}

final class ScrollResolution {
  const ScrollResolution.resolved({
    required this.target,
    required this.logicalPixels,
    required this.mode,
    this.dataRevision,
    this.clamped = false,
    this.clampReason,
    this.diagnostics,
  }) : status = ScrollResolutionStatus.resolved;

  const ScrollResolution._failure(this.status)
      : target = null,
        logicalPixels = null,
        mode = ScrollResolutionMode.exact,
        dataRevision = null,
        clamped = false,
        clampReason = null,
        diagnostics = null;

  const ScrollResolution.targetNotLoaded()
      : this._failure(ScrollResolutionStatus.targetNotLoaded);
  const ScrollResolution.targetDeleted()
      : this._failure(ScrollResolutionStatus.targetDeleted);
  const ScrollResolution.targetOutOfRange()
      : this._failure(ScrollResolutionStatus.targetOutOfRange);
  const ScrollResolution.resolverRejected({Map<String, Object?>? diagnostics})
      : this._failureWithDiagnostics(
          ScrollResolutionStatus.resolverRejected,
          diagnostics,
        );
  const ScrollResolution._failureWithDiagnostics(
    this.status,
    this.diagnostics,
  )   : target = null,
        logicalPixels = null,
        mode = ScrollResolutionMode.exact,
        dataRevision = null,
        clamped = false,
        clampReason = null;
  const ScrollResolution.unsupported()
      : this._failure(ScrollResolutionStatus.unsupported);

  final ScrollResolutionStatus status;
  final ScrollTarget? target;
  final double? logicalPixels;
  final ScrollResolutionMode mode;
  final int? dataRevision;
  final bool clamped;
  final String? clampReason;
  final Map<String, Object?>? diagnostics;

  bool get isResolved => status == ScrollResolutionStatus.resolved;

  @override
  bool operator ==(Object other) =>
      other is ScrollResolution &&
      other.status == status &&
      other.target == target &&
      other.logicalPixels == logicalPixels &&
      other.mode == mode &&
      other.dataRevision == dataRevision &&
      other.clamped == clamped &&
      other.clampReason == clampReason;

  @override
  int get hashCode => Object.hash(
        status,
        target,
        logicalPixels,
        mode,
        dataRevision,
        clamped,
        clampReason,
      );
}

final class ScrollDriverResult {
  const ScrollDriverResult({
    required this.finalLogicalPixels,
    required this.finalError,
    this.outcome = ScrollOutcome.completed,
    this.clamped = false,
    this.clampReason,
    this.correctionCount = 0,
    this.replanCount = 0,
    this.endRevision,
    this.diagnostics,
  });

  final double finalLogicalPixels;
  final double finalError;
  final ScrollOutcome outcome;
  final bool clamped;
  final String? clampReason;
  final int correctionCount;
  final int replanCount;
  final int? endRevision;
  final Map<String, Object?>? diagnostics;
}

abstract interface class ScrollDriver {
  ScrollCapabilities get capabilities;
  Future<ScrollResolution> resolve(ScrollTarget target);
  ScrollMotionPlan planMotion(
    ScrollResolution resolution,
    ScrollMotion motion,
  );
  Future<ScrollDriverResult> jump(ScrollResolution resolution);
  Future<ScrollDriverResult> animate(
    ScrollResolution resolution,
    ScrollMotionPlan plan,
  );
  Future<ScrollDriverResult> stabilize(
    ScrollTarget target,
    ScrollResolution initialResolution,
    ScrollDriverResult initialResult, {
    required ScrollExecutionPolicy executionPolicy,
    ScrollMotion? correctionMotion,
  });
  void stop(ScrollStopReason reason);
}

extension ScrollDriverResultStatus on ScrollDriverResult {
  bool get isSuccess =>
      outcome == ScrollOutcome.completed || outcome == ScrollOutcome.clamped;
}

abstract interface class ScrollClock {
  Duration get now;
  Future<void> delay(Duration duration);
}

final class SystemScrollClock implements ScrollClock {
  SystemScrollClock() : _started = Stopwatch()..start();

  final Stopwatch _started;

  @override
  Duration get now => _started.elapsed;

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

final class DeterministicScrollClock implements ScrollClock {
  Duration _now = Duration.zero;
  final List<_ClockWaiter> _waiters = <_ClockWaiter>[];

  @override
  Duration get now => _now;

  @override
  Future<void> delay(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    if (duration == Duration.zero) {
      return Future<void>.value();
    }
    final Completer<void> completer = Completer<void>();
    _waiters.add(_ClockWaiter(_now + duration, completer));
    _waiters.sort((_ClockWaiter a, _ClockWaiter b) => a.at.compareTo(b.at));
    return completer.future;
  }

  void elapse(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    _now += duration;
    while (_waiters.isNotEmpty && _waiters.first.at <= _now) {
      _waiters.removeAt(0).completer.complete();
    }
  }
}

final class _ClockWaiter {
  const _ClockWaiter(this.at, this.completer);
  final Duration at;
  final Completer<void> completer;
}
