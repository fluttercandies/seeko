import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('driver resolution validates capability before execution', () async {
    final _PixelDriver driver = _PixelDriver();
    expect(
      await driver.resolve(ScrollTarget.index(2)),
      const ScrollResolution.unsupported(),
    );
    final ScrollResolution resolution =
        await driver.resolve(ScrollTarget.offset(42));
    expect(resolution.isResolved, isTrue);
    expect(resolution.logicalPixels, 42);
    expect(resolution.clamped, isFalse);
    final ScrollDriverResult result = await driver.jump(resolution);
    expect(result.finalLogicalPixels, 42);
    expect(result.outcome, ScrollOutcome.completed);
  });

  test('driver resolutions preserve boundary metadata', () {
    final ScrollResolution resolution = ScrollResolution.resolved(
      target: ScrollTarget.offset(100),
      logicalPixels: 80,
      mode: ScrollResolutionMode.exact,
      clamped: true,
      clampReason: 'finite extent',
    );

    expect(resolution.clamped, isTrue);
    expect(resolution.clampReason, 'finite extent');
  });

  test('deterministic clock advances waiters in chronological order', () async {
    final DeterministicScrollClock clock = DeterministicScrollClock();
    final List<int> completed = <int>[];
    unawaited(
      clock.delay(const Duration(milliseconds: 20)).then(
            (_) => completed.add(20),
          ),
    );
    unawaited(
      clock.delay(const Duration(milliseconds: 10)).then(
            (_) => completed.add(10),
          ),
    );
    clock.elapse(const Duration(milliseconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(completed, <int>[10]);
    expect(clock.now, const Duration(milliseconds: 10));
    clock.elapse(const Duration(milliseconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(completed, <int>[10, 20]);
  });
}

final class _PixelDriver implements ScrollDriver {
  @override
  ScrollCapabilities get capabilities => ScrollCapabilities.pixel;

  @override
  Future<ScrollResolution> resolve(ScrollTarget target) async {
    if (target is! OffsetScrollTarget) {
      return const ScrollResolution.unsupported();
    }
    return ScrollResolution.resolved(
      target: target,
      logicalPixels: target.pixels,
      mode: ScrollResolutionMode.exact,
    );
  }

  @override
  ScrollMotionPlan planMotion(
    ScrollResolution resolution,
    ScrollMotion motion,
  ) {
    return ScrollMotionPlan(
      distance: resolution.logicalPixels!,
      duration: Duration.zero,
      curve: Curves.linear,
      frameInterval: const Duration(milliseconds: 16),
      requiresWindowRebase: false,
    );
  }

  @override
  Future<ScrollDriverResult> jump(ScrollResolution resolution) async {
    return ScrollDriverResult(
      finalLogicalPixels: resolution.logicalPixels!,
      finalError: 0,
    );
  }

  @override
  Future<ScrollDriverResult> animate(
    ScrollResolution resolution,
    ScrollMotionPlan plan,
  ) async {
    return jump(resolution);
  }

  @override
  Future<ScrollDriverResult> stabilize(
    ScrollTarget target,
    ScrollResolution initialResolution,
    ScrollDriverResult initialResult, {
    required ScrollExecutionPolicy executionPolicy,
    ScrollMotion? correctionMotion,
  }) async {
    return initialResult;
  }

  @override
  void stop(ScrollStopReason reason) {}
}
