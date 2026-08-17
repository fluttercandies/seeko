import 'dart:math' as math;

import 'motion_prototype_models.dart';

final class MotionPrototypeFrame {
  const MotionPrototypeFrame({
    required this.elapsed,
    required this.logicalPixels,
    required this.visualAnchorPixels,
    required this.windowEpoch,
    required this.layerCount,
    required this.visibleChildren,
    required this.cumulativeChildBuilds,
    required this.estimatedResidentBytes,
    required this.intendedOpacityTransition,
    required this.unintendedOpacityTransition,
    required this.hasDuplicateItems,
  });

  final Duration elapsed;
  final double logicalPixels;
  final double visualAnchorPixels;
  final int windowEpoch;
  final int layerCount;
  final int visibleChildren;
  final int cumulativeChildBuilds;
  final int estimatedResidentBytes;
  final bool intendedOpacityTransition;
  final bool unintendedOpacityTransition;
  final bool hasDuplicateItems;
}

final class MotionPrototypeTrace {
  MotionPrototypeTrace({
    required this.candidate,
    required this.testCase,
    required this.targetPixels,
    required this.interrupted,
    required this.peakVelocityJumpRatio,
    required this.interruptionLatencyFrames,
    required Iterable<MotionPrototypeFrame> frames,
  }) : frames = List<MotionPrototypeFrame>.unmodifiable(frames) {
    if (this.frames.isEmpty) {
      throw ArgumentError.value(frames, 'frames', 'must not be empty');
    }
  }

  final MotionPrototypeCandidate candidate;
  final MotionPrototypeCase testCase;
  final double targetPixels;
  final bool interrupted;
  final double peakVelocityJumpRatio;
  final int interruptionLatencyFrames;
  final List<MotionPrototypeFrame> frames;

  double get terminalError =>
      interrupted ? 0 : (frames.last.logicalPixels - targetPixels).abs();
  int get childBuilds => frames.last.cumulativeChildBuilds;
  int get peakLayerCount => frames
      .map((MotionPrototypeFrame value) => value.layerCount)
      .reduce(math.max);
  int get peakMemoryBytes => frames
      .map((MotionPrototypeFrame value) => value.estimatedResidentBytes)
      .reduce(math.max);
  int get intendedOpacityFrames => frames
      .where(
        (MotionPrototypeFrame value) => value.intendedOpacityTransition,
      )
      .length;
  int get unintendedOpacityFrames => frames
      .where(
        (MotionPrototypeFrame value) => value.unintendedOpacityTransition,
      )
      .length;
  int get duplicateFrames => frames
      .where((MotionPrototypeFrame value) => value.hasDuplicateItems)
      .length;
  int get blankFrames => frames
      .where((MotionPrototypeFrame value) => value.visibleChildren == 0)
      .length;
  int get reverseFrames {
    final double sign = testCase.direction == MotionDirection.forward ? 1 : -1;
    var count = 0;
    for (var index = 1; index < frames.length; index += 1) {
      final double delta =
          frames[index].logicalPixels - frames[index - 1].logicalPixels;
      if (delta * sign < -1e-9) {
        count += 1;
      }
    }
    return count;
  }

  int get windowRebases {
    var count = 0;
    for (var index = 1; index < frames.length; index += 1) {
      if (frames[index].windowEpoch != frames[index - 1].windowEpoch) {
        count += 1;
      }
    }
    return count;
  }

  double get peakAnchorGeometryError {
    var peak = 0.0;
    for (var index = 1; index < frames.length; index += 1) {
      final MotionPrototypeFrame previous = frames[index - 1];
      final MotionPrototypeFrame current = frames[index];
      final double expected = -(current.logicalPixels - previous.logicalPixels);
      final double actual =
          current.visualAnchorPixels - previous.visualAnchorPixels;
      peak = math.max(peak, (actual - expected).abs());
    }
    return peak;
  }
}

abstract base class MotionPrototypeTrajectory {
  const MotionPrototypeTrajectory();

  factory MotionPrototypeTrajectory.forCandidate(
    MotionPrototypeCandidate candidate,
  ) =>
      switch (candidate) {
        MotionPrototypeCandidate.dualViewportCrossfade =>
          const _DualViewportCrossfadeTrajectory(),
        MotionPrototypeCandidate.tagSegmentedSearch =>
          const _TagSegmentedSearchTrajectory(),
        MotionPrototypeCandidate.virtualWindowRebase =>
          const _VirtualWindowRebaseTrajectory(),
      };

  MotionPrototypeCandidate get candidate;

  MotionPrototypeTrace trace(
    MotionPrototypeCase testCase, {
    required double viewportExtent,
    bool interrupt = false,
  }) {
    if (!viewportExtent.isFinite || viewportExtent <= 0) {
      throw RangeError.value(
        viewportExtent,
        'viewportExtent',
        'must be finite and positive',
      );
    }
    final double sign = testCase.direction == MotionDirection.forward ? 1 : -1;
    final double targetPixels =
        sign * testCase.distanceViewports * viewportExtent;
    final Duration duration = durationFor(testCase);
    final int intervalMicros =
        (Duration.microsecondsPerSecond / testCase.refreshRateHz).round();
    final int frameCount = math.max(
      1,
      (duration.inMicroseconds / intervalMicros).ceil(),
    );
    final int visibleChildren = switch (testCase.extentProfile) {
      MotionExtentProfile.fixed => 18,
      MotionExtentProfile.deterministicDynamic => 22,
    };
    final List<MotionPrototypeFrame> frames = <MotionPrototypeFrame>[];
    var childBuilds = visibleChildren;
    var previousEpoch = 0;
    var previousLayerCount = 1;
    var interruptedAtFrame = -1;
    for (var frame = 0; frame <= frameCount; frame += 1) {
      final double rawT = frame / frameCount;
      final bool shouldInterrupt = interrupt && rawT >= testCase.interruptAt;
      final double t = shouldInterrupt ? testCase.interruptAt : rawT;
      final _PrototypeState state = _stateAt(
        testCase,
        t,
        targetPixels: targetPixels,
        viewportExtent: viewportExtent,
        visibleChildren: visibleChildren,
      );
      if (frames.isNotEmpty &&
          (state.windowEpoch != previousEpoch ||
              state.layerCount > previousLayerCount)) {
        childBuilds += visibleChildren;
      }
      previousEpoch = state.windowEpoch;
      previousLayerCount = state.layerCount;
      frames.add(
        MotionPrototypeFrame(
          elapsed: Duration(
            microseconds: math.min(
              duration.inMicroseconds,
              frame * intervalMicros,
            ),
          ),
          logicalPixels: state.logicalPixels,
          visualAnchorPixels: state.visualAnchorPixels,
          windowEpoch: state.windowEpoch,
          layerCount: state.layerCount,
          visibleChildren: visibleChildren * state.layerCount,
          cumulativeChildBuilds: childBuilds,
          estimatedResidentBytes:
              65536 + visibleChildren * state.layerCount * 2560,
          intendedOpacityTransition: state.intendedOpacityTransition,
          unintendedOpacityTransition: state.unintendedOpacityTransition,
          hasDuplicateItems: state.hasDuplicateItems,
        ),
      );
      if (shouldInterrupt) {
        interruptedAtFrame = frame;
        break;
      }
    }
    if (interrupt) {
      final MotionPrototypeFrame stopped = frames.last;
      frames.add(
        MotionPrototypeFrame(
          elapsed: stopped.elapsed + Duration(microseconds: intervalMicros),
          logicalPixels: stopped.logicalPixels,
          visualAnchorPixels: stopped.visualAnchorPixels,
          windowEpoch: stopped.windowEpoch,
          layerCount: stopped.layerCount,
          visibleChildren: stopped.visibleChildren,
          cumulativeChildBuilds: stopped.cumulativeChildBuilds,
          estimatedResidentBytes: stopped.estimatedResidentBytes,
          intendedOpacityTransition: false,
          unintendedOpacityTransition: false,
          hasDuplicateItems: stopped.hasDuplicateItems,
        ),
      );
    }
    return MotionPrototypeTrace(
      candidate: candidate,
      testCase: testCase,
      targetPixels: targetPixels,
      interrupted: interrupt,
      peakVelocityJumpRatio: _peakVelocityJumpRatio(
        testCase,
        targetPixels: targetPixels,
        viewportExtent: viewportExtent,
      ),
      interruptionLatencyFrames:
          interruptedAtFrame < 0 ? 0 : frames.length - interruptedAtFrame - 1,
      frames: frames,
    );
  }

  Duration durationFor(MotionPrototypeCase testCase) {
    final double milliseconds =
        120 + 190 * math.log(testCase.distanceViewports + 1) / math.ln2;
    return Duration(
      microseconds: (milliseconds * 1000).round().clamp(120000, 2000000),
    );
  }

  _PrototypeState _stateAt(
    MotionPrototypeCase testCase,
    double t, {
    required double targetPixels,
    required double viewportExtent,
    required int visibleChildren,
  });

  double _peakVelocityJumpRatio(
    MotionPrototypeCase testCase, {
    required double targetPixels,
    required double viewportExtent,
  }) {
    final Duration duration = durationFor(testCase);
    final int samples = math.max(2, duration.inMilliseconds);
    final List<double> positions = List<double>.generate(
      samples + 1,
      (int index) => _stateAt(
        testCase,
        index / samples,
        targetPixels: targetPixels,
        viewportExtent: viewportExtent,
        visibleChildren: 20,
      ).logicalPixels,
      growable: false,
    );
    final List<double> velocities = <double>[];
    for (var index = 1; index < positions.length; index += 1) {
      velocities.add(positions[index] - positions[index - 1]);
    }
    final double peakVelocity =
        velocities.map((double value) => value.abs()).reduce(math.max);
    if (peakVelocity == 0) {
      return 0;
    }
    var peakJump = 0.0;
    final int edgeSamples = math.max(2, velocities.length ~/ 100);
    for (var index = edgeSamples + 1;
        index < velocities.length - edgeSamples;
        index += 1) {
      peakJump = math.max(
        peakJump,
        (velocities[index] - velocities[index - 1]).abs(),
      );
    }
    return peakJump / peakVelocity;
  }
}

final class _PrototypeState {
  const _PrototypeState({
    required this.logicalPixels,
    required this.visualAnchorPixels,
    required this.windowEpoch,
    required this.layerCount,
    required this.intendedOpacityTransition,
    required this.unintendedOpacityTransition,
    required this.hasDuplicateItems,
  });

  final double logicalPixels;
  final double visualAnchorPixels;
  final int windowEpoch;
  final int layerCount;
  final bool intendedOpacityTransition;
  final bool unintendedOpacityTransition;
  final bool hasDuplicateItems;
}

final class _DualViewportCrossfadeTrajectory extends MotionPrototypeTrajectory {
  const _DualViewportCrossfadeTrajectory();

  @override
  MotionPrototypeCandidate get candidate =>
      MotionPrototypeCandidate.dualViewportCrossfade;

  @override
  _PrototypeState _stateAt(
    MotionPrototypeCase testCase,
    double t, {
    required double targetPixels,
    required double viewportExtent,
    required int visibleChildren,
  }) {
    final double progress = _smootherStep(t);
    final bool crossfading = t > 0.10 && t < 0.90;
    return _PrototypeState(
      logicalPixels: targetPixels * progress,
      visualAnchorPixels: -targetPixels * progress,
      windowEpoch: 0,
      layerCount: crossfading ? 2 : 1,
      intendedOpacityTransition: crossfading,
      unintendedOpacityTransition: false,
      hasDuplicateItems: crossfading && testCase.distanceViewports < 2,
    );
  }
}

double _smootherStep(double t) => t * t * t * (t * (t * 6 - 15) + 10);

final class _TagSegmentedSearchTrajectory extends MotionPrototypeTrajectory {
  const _TagSegmentedSearchTrajectory();

  @override
  MotionPrototypeCandidate get candidate =>
      MotionPrototypeCandidate.tagSegmentedSearch;

  @override
  _PrototypeState _stateAt(
    MotionPrototypeCase testCase,
    double t, {
    required double targetPixels,
    required double viewportExtent,
    required int visibleChildren,
  }) {
    final int segmentCount = math.max(
      1,
      (testCase.distanceViewports / 10).ceil(),
    );
    final double scaled = t == 1 ? segmentCount.toDouble() : t * segmentCount;
    final int segment = math.min(segmentCount - 1, scaled.floor());
    final double local = t == 1 ? 1 : scaled - segment;
    final double moving = (local / 0.85).clamp(0, 1);
    final double progress = (segment + moving) / segmentCount;
    return _PrototypeState(
      logicalPixels: targetPixels * progress,
      visualAnchorPixels: -targetPixels * progress,
      windowEpoch: segment,
      layerCount: 1,
      intendedOpacityTransition: false,
      unintendedOpacityTransition: false,
      hasDuplicateItems: false,
    );
  }
}

final class _VirtualWindowRebaseTrajectory extends MotionPrototypeTrajectory {
  const _VirtualWindowRebaseTrajectory();

  @override
  MotionPrototypeCandidate get candidate =>
      MotionPrototypeCandidate.virtualWindowRebase;

  @override
  _PrototypeState _stateAt(
    MotionPrototypeCase testCase,
    double t, {
    required double targetPixels,
    required double viewportExtent,
    required int visibleChildren,
  }) {
    final double progress = _smootherStep(t);
    final bool requiresRebase = testCase.distanceViewports > 10;
    return _PrototypeState(
      logicalPixels: targetPixels * progress,
      visualAnchorPixels: -targetPixels * progress,
      windowEpoch: requiresRebase && t >= 0.5 ? 1 : 0,
      layerCount: 1,
      intendedOpacityTransition: false,
      unintendedOpacityTransition: false,
      hasDuplicateItems: false,
    );
  }
}
