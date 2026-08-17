import 'package:flutter/foundation.dart';

import 'scroll_target.dart';

enum ScrollOutcome {
  completed,
  clamped,
  superseded,
  interruptedByUser,
  targetNotLoaded,
  targetDeleted,
  targetOutOfRange,
  resolverRejected,
  unsupported,
  detached,
  layoutUnstable,
  timedOut,
  ignored,
  cancelled,
}

enum ScrollResolutionMode { exact, estimated, searched, fallback }

enum ScrollConflictPolicy { replace, enqueue, ignoreWhileActive, coalesce }

enum ScrollBoundaryPolicy { clampNumeric, reject, allowPhysicsOverscroll }

enum ScrollStopReason {
  requested,
  userInteraction,
  superseded,
  timedOut,
  disposed,
  detached
}

enum ScrollCommandPhase {
  queued,
  resolving,
  moving,
  correcting,
  settled,
  terminal
}

final class ScrollExecutionPolicy {
  factory ScrollExecutionPolicy({
    Duration deadline = const Duration(seconds: 3),
    int maxReplans = 8,
    int maxCorrections = 4,
    int settleSamples = 2,
    double targetTolerance = 0.5,
  }) {
    if (deadline <= Duration.zero || deadline > const Duration(seconds: 10)) {
      throw ArgumentError.value(deadline, 'deadline', 'must be in (0, 10s]');
    }
    RangeError.checkNotNegative(maxReplans, 'maxReplans');
    RangeError.checkNotNegative(maxCorrections, 'maxCorrections');
    RangeError.checkValueInInterval(settleSamples, 1, 120, 'settleSamples');
    if (!targetTolerance.isFinite || targetTolerance <= 0) {
      throw ArgumentError.value(
        targetTolerance,
        'targetTolerance',
        'must be finite and positive',
      );
    }
    return ScrollExecutionPolicy._(
      deadline: deadline,
      maxReplans: maxReplans,
      maxCorrections: maxCorrections,
      settleSamples: settleSamples,
      targetTolerance: targetTolerance,
    );
  }

  factory ScrollExecutionPolicy.jump() => ScrollExecutionPolicy(
        deadline: const Duration(seconds: 1),
      );

  const ScrollExecutionPolicy._({
    required this.deadline,
    required this.maxReplans,
    required this.maxCorrections,
    required this.settleSamples,
    required this.targetTolerance,
  });

  final Duration deadline;
  final int maxReplans;
  final int maxCorrections;
  final int settleSamples;
  final double targetTolerance;
}

final class ScrollResolutionPolicy {
  const ScrollResolutionPolicy({
    this.requireExact = false,
    this.allowEstimated = true,
    this.allowSearched = true,
    this.allowFallback = true,
  });

  final bool requireExact;
  final bool allowEstimated;
  final bool allowSearched;
  final bool allowFallback;
}

final class ScrollCommandOptions {
  const ScrollCommandOptions({
    this.conflictPolicy,
    this.boundaryPolicy,
    ScrollResolutionPolicy? resolutionPolicy,
    this.executionPolicy,
    this.cancellationToken,
    this.lockUserInteraction,
  })  : resolutionPolicy = resolutionPolicy ?? const ScrollResolutionPolicy(),
        _hasExplicitResolutionPolicy = resolutionPolicy != null;

  final ScrollConflictPolicy? conflictPolicy;
  final ScrollBoundaryPolicy? boundaryPolicy;
  final ScrollResolutionPolicy resolutionPolicy;
  final ScrollExecutionPolicy? executionPolicy;
  final ScrollCancellationToken? cancellationToken;
  final bool? lockUserInteraction;
  final bool _hasExplicitResolutionPolicy;

  ScrollCommandOptions merge(ScrollCommandOptions overrides) {
    return ScrollCommandOptions(
      conflictPolicy: overrides.conflictPolicy ?? conflictPolicy,
      boundaryPolicy: overrides.boundaryPolicy ?? boundaryPolicy,
      resolutionPolicy: overrides._hasExplicitResolutionPolicy
          ? overrides.resolutionPolicy
          : resolutionPolicy,
      executionPolicy: overrides.executionPolicy ?? executionPolicy,
      cancellationToken: overrides.cancellationToken ?? cancellationToken,
      lockUserInteraction: overrides.lockUserInteraction ?? lockUserInteraction,
    );
  }
}

final class ScrollResult {
  const ScrollResult({
    required this.commandId,
    required this.outcome,
    required this.requestedTarget,
    required this.capturedTarget,
    required this.achievedTarget,
    required this.startRevision,
    required this.endRevision,
    required this.resolutionMode,
    required this.finalLogicalPixels,
    required this.finalError,
    required this.elapsed,
    required this.replanCount,
    required this.correctionCount,
    this.clampReason,
    this.diagnostics,
  });

  final int commandId;
  final ScrollOutcome outcome;
  final ScrollTarget requestedTarget;
  final ScrollTarget? capturedTarget;
  final ScrollTarget? achievedTarget;
  final int? startRevision;
  final int? endRevision;
  final ScrollResolutionMode resolutionMode;
  final double? finalLogicalPixels;
  final double? finalError;
  final String? clampReason;
  final Duration elapsed;
  final int replanCount;
  final int correctionCount;
  final Map<String, Object?>? diagnostics;

  bool get isSuccess =>
      outcome == ScrollOutcome.completed || outcome == ScrollOutcome.clamped;

  bool get isDegraded => resolutionMode != ScrollResolutionMode.exact;

  bool get isTerminal => true;
}

final class ScrollCancellationToken extends ChangeNotifier {
  ScrollStopReason? _reason;

  bool get isCancelled => _reason != null;
  ScrollStopReason? get reason => _reason;

  @visibleForTesting
  bool get debugHasListeners => hasListeners;

  void _cancel(ScrollStopReason reason) {
    if (_reason != null) {
      return;
    }
    _reason = reason;
    notifyListeners();
  }
}

final class ScrollCancellationSource {
  final ScrollCancellationToken token = ScrollCancellationToken();

  void cancel([ScrollStopReason reason = ScrollStopReason.requested]) {
    token._cancel(reason);
  }

  void dispose() {
    token.dispose();
  }
}
