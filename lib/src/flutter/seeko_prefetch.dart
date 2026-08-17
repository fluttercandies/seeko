import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/logical_geometry.dart';
import 'seeko_controller.dart';
import 'seeko_snapshot.dart';

enum ScrollPrefetchDirection { leading, stationary, trailing }

/// Sampling and lookahead bounds for [ScrollPrefetchObserver].
@immutable
final class ScrollPrefetchConfiguration {
  factory ScrollPrefetchConfiguration({
    Duration horizon = const Duration(milliseconds: 250),
    Duration sampleInterval = const Duration(milliseconds: 50),
    double minimumVelocity = 40,
    double maxLookaheadViewports = 4,
    bool emitStationary = true,
  }) {
    if (horizon <= Duration.zero || horizon > const Duration(seconds: 10)) {
      throw ArgumentError.value(
        horizon,
        'horizon',
        'must be positive and at most 10 seconds',
      );
    }
    if (sampleInterval <= Duration.zero ||
        sampleInterval > const Duration(seconds: 1)) {
      throw ArgumentError.value(
        sampleInterval,
        'sampleInterval',
        'must be positive and at most 1 second',
      );
    }
    if (!minimumVelocity.isFinite || minimumVelocity < 0) {
      throw ArgumentError.value(
        minimumVelocity,
        'minimumVelocity',
        'must be finite and non-negative',
      );
    }
    if (!maxLookaheadViewports.isFinite || maxLookaheadViewports <= 0) {
      throw ArgumentError.value(
        maxLookaheadViewports,
        'maxLookaheadViewports',
        'must be finite and positive',
      );
    }
    return ScrollPrefetchConfiguration._(
      horizon: horizon,
      sampleInterval: sampleInterval,
      minimumVelocity: minimumVelocity,
      maxLookaheadViewports: maxLookaheadViewports,
      emitStationary: emitStationary,
    );
  }

  const ScrollPrefetchConfiguration._({
    required this.horizon,
    required this.sampleInterval,
    required this.minimumVelocity,
    required this.maxLookaheadViewports,
    required this.emitStationary,
  });

  final Duration horizon;
  final Duration sampleInterval;
  final double minimumVelocity;
  final double maxLookaheadViewports;
  final bool emitStationary;
}

/// Advisory projection emitted by [ScrollPrefetchObserver].
///
/// This value never starts I/O. Applications decide whether and how to turn a
/// hint into image decoding, pagination, cache warming, or deferred work.
@immutable
final class ScrollPrefetchHint {
  const ScrollPrefetchHint._({
    required this.sequence,
    required this.direction,
    required this.logicalPixels,
    required this.logicalVelocity,
    required this.projectedLogicalPixels,
    required this.viewportExtent,
    required this.maxScrollExtent,
    required this.horizon,
    required this.projectedViewport,
    required this.sweptRegion,
    required this.leadingVisibleTarget,
    required this.trailingVisibleTarget,
  });

  final int sequence;
  final ScrollPrefetchDirection direction;
  final double logicalPixels;
  final double logicalVelocity;
  final double projectedLogicalPixels;
  final double viewportExtent;
  final double maxScrollExtent;
  final Duration horizon;
  final LogicalInterval projectedViewport;
  final LogicalInterval sweptRegion;
  final ScrollVisibleTarget? leadingVisibleTarget;
  final ScrollVisibleTarget? trailingVisibleTarget;

  Duration? estimatedArrivalTo(double logicalPixels) {
    if (!logicalPixels.isFinite) {
      throw ArgumentError.value(
        logicalPixels,
        'logicalPixels',
        'must be finite',
      );
    }
    final double delta = logicalPixels - this.logicalPixels;
    if (logicalVelocity == 0 || delta == 0) {
      return delta == 0 ? Duration.zero : null;
    }
    if (delta.sign != logicalVelocity.sign) {
      return null;
    }
    return Duration(
      microseconds:
          (delta.abs() / logicalVelocity.abs() * Duration.microsecondsPerSecond)
              .round(),
    );
  }

  Duration? get estimatedArrivalToLeadingEdge => estimatedArrivalTo(0);

  Duration? get estimatedArrivalToTrailingEdge =>
      estimatedArrivalTo(maxScrollExtent);
}

/// Opt-in, allocation-bounded prefetch signal derived from controller
/// snapshots. Disposing the observer removes its only controller listener.
final class ScrollPrefetchObserver extends ValueNotifier<ScrollPrefetchHint?> {
  ScrollPrefetchObserver(
    this.controller, {
    ScrollPrefetchConfiguration? configuration,
  })  : configuration = configuration ?? ScrollPrefetchConfiguration(),
        super(null) {
    controller.state.addListener(_handleSnapshot);
  }

  final SeekoController controller;
  final ScrollPrefetchConfiguration configuration;
  Duration? _sampleTime;
  double? _samplePixels;
  var _sequence = 0;
  var _disposed = false;

  void _handleSnapshot() {
    if (_disposed) {
      return;
    }
    final ScrollSnapshot snapshot = controller.state.value;
    if (!controller.hasClients ||
        snapshot.viewportExtent <= 0 ||
        snapshot.maxScrollExtent < 0) {
      _sampleTime = null;
      _samplePixels = null;
      return;
    }
    final Duration now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final Duration? previousTime = _sampleTime;
    final double? previousPixels = _samplePixels;
    if (previousTime == null || previousPixels == null) {
      _sampleTime = now;
      _samplePixels = snapshot.pixels;
      return;
    }
    final Duration elapsed = now - previousTime;
    if (elapsed < configuration.sampleInterval || elapsed <= Duration.zero) {
      return;
    }
    final double seconds =
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    var velocity = (snapshot.pixels - previousPixels) / seconds;
    if (!velocity.isFinite || velocity.abs() < configuration.minimumVelocity) {
      velocity = 0;
    }
    final ScrollPrefetchDirection direction = velocity > 0
        ? ScrollPrefetchDirection.trailing
        : velocity < 0
            ? ScrollPrefetchDirection.leading
            : ScrollPrefetchDirection.stationary;
    _sampleTime = now;
    _samplePixels = snapshot.pixels;
    if (direction == ScrollPrefetchDirection.stationary &&
        !configuration.emitStationary) {
      return;
    }
    final double horizonSeconds =
        configuration.horizon.inMicroseconds / Duration.microsecondsPerSecond;
    final double maximumDelta =
        snapshot.viewportExtent * configuration.maxLookaheadViewports;
    final double projectedDelta =
        (velocity * horizonSeconds).clamp(-maximumDelta, maximumDelta);
    final double projected = (snapshot.pixels + projectedDelta)
        .clamp(0, snapshot.maxScrollExtent)
        .toDouble();
    final double contentEnd =
        snapshot.maxScrollExtent + snapshot.viewportExtent;
    final LogicalInterval projectedViewport = LogicalInterval(
      projected,
      math.min(contentEnd, projected + snapshot.viewportExtent),
    );
    final LogicalInterval sweptRegion = LogicalInterval(
      math.min(snapshot.pixels, projected),
      math.min(
        contentEnd,
        math.max(snapshot.pixels, projected) + snapshot.viewportExtent,
      ),
    );
    final List<ScrollVisibleTarget> visible = snapshot.visibleTargets;
    value = ScrollPrefetchHint._(
      sequence: ++_sequence,
      direction: direction,
      logicalPixels: snapshot.pixels,
      logicalVelocity: velocity,
      projectedLogicalPixels: projected,
      viewportExtent: snapshot.viewportExtent,
      maxScrollExtent: snapshot.maxScrollExtent,
      horizon: configuration.horizon,
      projectedViewport: projectedViewport,
      sweptRegion: sweptRegion,
      leadingVisibleTarget: visible.isEmpty ? null : visible.first,
      trailingVisibleTarget: visible.isEmpty ? null : visible.last,
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    controller.state.removeListener(_handleSnapshot);
    super.dispose();
  }
}
