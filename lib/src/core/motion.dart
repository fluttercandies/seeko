import 'dart:math' as math;

import 'package:flutter/animation.dart';

enum ScrollMotionKind { adaptive, duration, velocity, spring, instant }

final class ScrollMotion {
  const ScrollMotion.adaptive()
      : kind = ScrollMotionKind.adaptive,
        duration = null,
        curve = null,
        maxVelocity = null;

  const ScrollMotion.duration({
    required Duration this.duration,
    required Curve this.curve,
  })  : kind = ScrollMotionKind.duration,
        maxVelocity = null;

  const ScrollMotion.velocity({required double pixelsPerSecond})
      : kind = ScrollMotionKind.velocity,
        duration = null,
        curve = null,
        maxVelocity = pixelsPerSecond;

  const ScrollMotion.spring()
      : kind = ScrollMotionKind.spring,
        duration = null,
        curve = null,
        maxVelocity = null;

  const ScrollMotion.instant()
      : kind = ScrollMotionKind.instant,
        duration = Duration.zero,
        curve = Curves.linear,
        maxVelocity = null;

  final ScrollMotionKind kind;
  final Duration? duration;
  final Curve? curve;
  final double? maxVelocity;
}

final class ScrollMotionPlan {
  const ScrollMotionPlan({
    required this.distance,
    required this.duration,
    required this.curve,
    required this.frameInterval,
    required this.requiresWindowRebase,
  });

  final double distance;
  final Duration duration;
  final Curve curve;
  final Duration frameInterval;
  final bool requiresWindowRebase;

  double positionAt(Duration elapsed) {
    if (duration == Duration.zero) {
      return distance;
    }
    final double t =
        (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0, 1);
    return distance * curve.transform(t);
  }
}

final class AdaptiveMotionPlanner {
  const AdaptiveMotionPlanner();

  ScrollMotionPlan plan({
    required double distance,
    required double viewportExtent,
    required Duration frameInterval,
    ScrollMotion motion = const ScrollMotion.adaptive(),
    bool reducedMotion = false,
  }) {
    if (!distance.isFinite) {
      throw ArgumentError.value(distance, 'distance', 'must be finite');
    }
    if (!viewportExtent.isFinite || viewportExtent <= 0) {
      throw ArgumentError.value(
        viewportExtent,
        'viewportExtent',
        'must be finite and positive',
      );
    }
    if (frameInterval <= Duration.zero) {
      throw ArgumentError.value(
        frameInterval,
        'frameInterval',
        'must be positive',
      );
    }
    if (reducedMotion ||
        motion.kind == ScrollMotionKind.instant ||
        distance == 0) {
      return ScrollMotionPlan(
        distance: distance,
        duration: Duration.zero,
        curve: Curves.linear,
        frameInterval: frameInterval,
        requiresWindowRebase: distance.abs() > viewportExtent * 10,
      );
    }

    final double viewports = distance.abs() / viewportExtent;
    late final Duration duration;
    late final Curve curve;
    switch (motion.kind) {
      case ScrollMotionKind.duration:
        duration = motion.duration!;
        if (duration <= Duration.zero ||
            duration > const Duration(seconds: 10)) {
          throw ArgumentError.value(
              duration, 'duration', 'must be in (0, 10s]');
        }
        curve = motion.curve!;
      case ScrollMotionKind.velocity:
        final double velocity = motion.maxVelocity!;
        if (!velocity.isFinite || velocity <= 0) {
          throw ArgumentError.value(
            velocity,
            'pixelsPerSecond',
            'must be finite and positive',
          );
        }
        duration = Duration(
          microseconds: ((distance.abs() / velocity) * 1000000)
              .round()
              .clamp(120000, 2000000),
        );
        curve = const _SmootherStepCurve();
      case ScrollMotionKind.spring:
        duration = Duration(
          microseconds: (180000 + math.min(viewports, 2) * 90000).round(),
        );
        curve = const _AnalyticEaseOutCubicCurve();
      case ScrollMotionKind.adaptive:
        final double milliseconds =
            120 + 190 * math.log(viewports + 1) / math.ln2;
        duration = Duration(
          microseconds: (milliseconds * 1000).round().clamp(120000, 2000000),
        );
        curve = const _SmootherStepCurve();
      case ScrollMotionKind.instant:
        throw StateError('instant motion is handled before planning');
    }
    return ScrollMotionPlan(
      distance: distance,
      duration: duration,
      curve: curve,
      frameInterval: frameInterval,
      requiresWindowRebase: viewports > 10,
    );
  }
}

final class _SmootherStepCurve extends Curve {
  const _SmootherStepCurve();

  @override
  double transformInternal(double t) {
    return t * t * t * (t * (t * 6 - 15) + 10);
  }
}

final class _AnalyticEaseOutCubicCurve extends Curve {
  const _AnalyticEaseOutCubicCurve();

  @override
  double transformInternal(double t) {
    final double inverse = 1 - t;
    return 1 - inverse * inverse * inverse;
  }
}
