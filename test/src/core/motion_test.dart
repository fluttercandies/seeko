import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('adaptive motion is bounded and monotonic over extreme distances', () {
    const AdaptiveMotionPlanner planner = AdaptiveMotionPlanner();
    for (final double viewports in <double>[0.5, 2, 10, 100, 1000]) {
      final ScrollMotionPlan plan = planner.plan(
        distance: viewports * 800,
        viewportExtent: 800,
        frameInterval: const Duration(microseconds: 8333),
      );
      expect(plan.duration >= const Duration(milliseconds: 120), isTrue);
      expect(plan.duration <= const Duration(seconds: 2), isTrue);
      var previous = plan.positionAt(Duration.zero);
      for (var milliseconds = 1;
          milliseconds <= plan.duration.inMilliseconds;
          milliseconds += 1) {
        final double current =
            plan.positionAt(Duration(milliseconds: milliseconds));
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
      expect(plan.positionAt(plan.duration), closeTo(viewports * 800, 1e-6));
    }
  });

  test('reduced motion uses an instant plan', () {
    const AdaptiveMotionPlanner planner = AdaptiveMotionPlanner();
    final ScrollMotionPlan plan = planner.plan(
      distance: -12000,
      viewportExtent: 800,
      frameInterval: const Duration(microseconds: 16667),
      reducedMotion: true,
    );
    expect(plan.duration, Duration.zero);
    expect(plan.positionAt(Duration.zero), -12000);
  });

  test('explicit duration retains caller curve and signed endpoint', () {
    const AdaptiveMotionPlanner planner = AdaptiveMotionPlanner();
    final ScrollMotionPlan plan = planner.plan(
      distance: -500,
      viewportExtent: 500,
      frameInterval: const Duration(microseconds: 8333),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    expect(plan.duration, const Duration(milliseconds: 300));
    expect(plan.positionAt(const Duration(milliseconds: 150)), -250);
    expect(plan.positionAt(plan.duration), -500);
  });

  test('adaptive trajectory has no quantized one millisecond velocity jumps',
      () {
    const AdaptiveMotionPlanner planner = AdaptiveMotionPlanner();
    final ScrollMotionPlan plan = planner.plan(
      distance: 800000,
      viewportExtent: 800,
      frameInterval: const Duration(microseconds: 8333),
    );
    final List<double> positions = <double>[];
    for (var milliseconds = 0;
        milliseconds <= plan.duration.inMilliseconds;
        milliseconds += 1) {
      positions.add(plan.positionAt(Duration(milliseconds: milliseconds)));
    }
    final List<double> velocities = <double>[];
    for (var index = 1; index < positions.length; index += 1) {
      velocities.add(positions[index] - positions[index - 1]);
    }
    final double peakVelocity = velocities
        .map((double value) => value.abs())
        .reduce((double a, double b) => a > b ? a : b);
    var peakJump = 0.0;
    final int endpointSamples = velocities.length ~/ 100;
    for (var index = endpointSamples + 1;
        index < velocities.length - endpointSamples;
        index += 1) {
      final double jump = (velocities[index] - velocities[index - 1]).abs();
      if (jump > peakJump) {
        peakJump = jump;
      }
    }

    expect(peakJump / peakVelocity, lessThanOrEqualTo(0.02));
  });
}
