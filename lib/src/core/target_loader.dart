import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'command_model.dart';
import 'scroll_target.dart';

enum ScrollTargetLoadStatus { loaded, notFound, retry, rejected }

@immutable
final class ScrollTargetLoadRequest {
  ScrollTargetLoadRequest({
    required this.commandId,
    required this.target,
    required this.attempt,
    required this.startRevision,
    required this.cancellationToken,
  }) {
    RangeError.checkValueInInterval(commandId, 1, 0x7fffffff, 'commandId');
    RangeError.checkValueInInterval(attempt, 1, 0x7fffffff, 'attempt');
    if (startRevision != null) {
      RangeError.checkNotNegative(startRevision!, 'startRevision');
    }
  }

  final int commandId;
  final ScrollTarget target;

  /// One-based invocation count for this command.
  final int attempt;
  final int? startRevision;

  /// Becomes cancelled for user takeover, replacement, detach, or deadline.
  ///
  /// Loaders should abort external work promptly. The controller still races
  /// the loader future against this token so a non-cooperative loader cannot
  /// keep the scroll command pending forever.
  final ScrollCancellationToken cancellationToken;
}

@immutable
final class ScrollTargetLoadResult {
  factory ScrollTargetLoadResult.loaded({int? revision}) {
    if (revision != null) {
      RangeError.checkNotNegative(revision, 'revision');
    }
    return ScrollTargetLoadResult._(
      status: ScrollTargetLoadStatus.loaded,
      outcome: null,
      revision: revision,
      retryAfter: null,
      diagnostic: null,
    );
  }

  factory ScrollTargetLoadResult.notFound({
    required ScrollOutcome outcome,
    Object? diagnostic,
  }) {
    if (outcome != ScrollOutcome.targetDeleted &&
        outcome != ScrollOutcome.targetOutOfRange) {
      throw ArgumentError.value(
        outcome,
        'outcome',
        'must be targetDeleted or targetOutOfRange',
      );
    }
    return ScrollTargetLoadResult._(
      status: ScrollTargetLoadStatus.notFound,
      outcome: outcome,
      revision: null,
      retryAfter: null,
      diagnostic: diagnostic,
    );
  }

  factory ScrollTargetLoadResult.retry({
    Duration? retryAfter,
    Object? diagnostic,
  }) {
    if (retryAfter?.isNegative == true) {
      throw ArgumentError.value(
        retryAfter,
        'retryAfter',
        'must not be negative',
      );
    }
    return ScrollTargetLoadResult._(
      status: ScrollTargetLoadStatus.retry,
      outcome: null,
      revision: null,
      retryAfter: retryAfter,
      diagnostic: diagnostic,
    );
  }

  const ScrollTargetLoadResult.rejected({this.diagnostic})
      : status = ScrollTargetLoadStatus.rejected,
        revision = null,
        outcome = ScrollOutcome.resolverRejected,
        retryAfter = null;

  const ScrollTargetLoadResult._({
    required this.status,
    required this.outcome,
    required this.revision,
    required this.retryAfter,
    required this.diagnostic,
  });

  final ScrollTargetLoadStatus status;
  final int? revision;
  final ScrollOutcome? outcome;
  final Duration? retryAfter;
  final Object? diagnostic;
}

abstract interface class ScrollTargetLoader {
  FutureOr<ScrollTargetLoadResult> load(ScrollTargetLoadRequest request);
}

typedef ScrollTargetLoadCallback = FutureOr<ScrollTargetLoadResult> Function(
  ScrollTargetLoadRequest request,
);

final class CallbackScrollTargetLoader implements ScrollTargetLoader {
  const CallbackScrollTargetLoader(this.callback);

  final ScrollTargetLoadCallback callback;

  @override
  FutureOr<ScrollTargetLoadResult> load(ScrollTargetLoadRequest request) {
    return callback(request);
  }
}

@immutable
final class ScrollTargetLoadPolicy {
  ScrollTargetLoadPolicy({
    this.maxAttempts = 3,
    this.initialRetryDelay = const Duration(milliseconds: 50),
    this.backoffFactor = 2,
    this.maxRetryDelay = const Duration(seconds: 1),
  }) {
    RangeError.checkValueInInterval(
      maxAttempts,
      1,
      0x7fffffff,
      'maxAttempts',
    );
    if (initialRetryDelay.isNegative) {
      throw ArgumentError.value(
        initialRetryDelay,
        'initialRetryDelay',
        'must not be negative',
      );
    }
    if (!backoffFactor.isFinite || backoffFactor < 1) {
      throw ArgumentError.value(
        backoffFactor,
        'backoffFactor',
        'must be finite and at least 1',
      );
    }
    if (maxRetryDelay.isNegative || maxRetryDelay < initialRetryDelay) {
      throw ArgumentError.value(
        maxRetryDelay,
        'maxRetryDelay',
        'must be non-negative and not less than initialRetryDelay',
      );
    }
  }

  final int maxAttempts;
  final Duration initialRetryDelay;
  final double backoffFactor;
  final Duration maxRetryDelay;

  Duration retryDelayAfter(int completedAttempts, {Duration? suggested}) {
    RangeError.checkValueInInterval(
      completedAttempts,
      1,
      0x7fffffff,
      'completedAttempts',
    );
    if (suggested?.isNegative == true) {
      throw ArgumentError.value(
        suggested,
        'suggested',
        'must not be negative',
      );
    }
    final int requestedMicroseconds = suggested?.inMicroseconds ??
        (initialRetryDelay.inMicroseconds *
                math.pow(backoffFactor, completedAttempts - 1))
            .round();
    return Duration(
      microseconds: math.min(
        requestedMicroseconds,
        maxRetryDelay.inMicroseconds,
      ),
    );
  }
}
