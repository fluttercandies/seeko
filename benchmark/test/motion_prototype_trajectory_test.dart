import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/motion_prototype_models.dart';
import 'package:seeko_benchmark/src/motion_prototype_trajectory.dart';

void main() {
  group('motion prototype trajectories', () {
    for (final MotionPrototypeCandidate candidate
        in MotionPrototypeCandidate.values) {
      test('$candidate has a deterministic signed endpoint', () {
        final MotionPrototypeTrajectory trajectory =
            MotionPrototypeTrajectory.forCandidate(candidate);
        for (final MotionDirection direction in MotionDirection.values) {
          final MotionPrototypeCase testCase = MotionPrototypeCase(
            distanceViewports: 100,
            extentProfile: MotionExtentProfile.deterministicDynamic,
            direction: direction,
            refreshRateHz: 120,
            interruptAt: 0.5,
          );

          final MotionPrototypeTrace trace = trajectory.trace(
            testCase,
            viewportExtent: 800,
          );

          expect(trace.frames.first.logicalPixels, 0);
          expect(
            trace.frames.last.logicalPixels,
            closeTo(direction == MotionDirection.forward ? 80000 : -80000, 0.5),
          );
          expect(
              trace.frames.every(
                  (MotionPrototypeFrame value) => value.visibleChildren > 0),
              isTrue);
        }
      });
    }

    test('virtual-window rebase keeps one visual layer and bounded builds', () {
      final MotionPrototypeTrajectory trajectory =
          MotionPrototypeTrajectory.forCandidate(
        MotionPrototypeCandidate.virtualWindowRebase,
      );

      final MotionPrototypeTrace near = trajectory.trace(
        _case(10),
        viewportExtent: 800,
      );
      final MotionPrototypeTrace far = trajectory.trace(
        _case(1000),
        viewportExtent: 800,
      );

      expect(
        far.frames
            .map((MotionPrototypeFrame value) => value.layerCount)
            .toSet(),
        <int>{1},
      );
      expect(far.windowRebases, greaterThan(0));
      expect(far.childBuilds, lessThanOrEqualTo(near.childBuilds * 2));
      expect(far.peakAnchorGeometryError, lessThanOrEqualTo(0.5));
      expect(far.peakVelocityJumpRatio, lessThanOrEqualTo(0.02));
    });

    test('dual viewport crossfade exposes its second layer cost', () {
      final MotionPrototypeTrace trace = MotionPrototypeTrajectory.forCandidate(
        MotionPrototypeCandidate.dualViewportCrossfade,
      ).trace(_case(100), viewportExtent: 800);

      expect(trace.peakLayerCount, 2);
      expect(trace.intendedOpacityFrames, greaterThan(0));
      expect(trace.unintendedOpacityFrames, 0);
    });

    test('segmented search work grows with distance', () {
      final MotionPrototypeTrajectory trajectory =
          MotionPrototypeTrajectory.forCandidate(
        MotionPrototypeCandidate.tagSegmentedSearch,
      );

      final MotionPrototypeTrace near = trajectory.trace(
        _case(10),
        viewportExtent: 800,
      );
      final MotionPrototypeTrace far = trajectory.trace(
        _case(1000),
        viewportExtent: 800,
      );

      expect(far.childBuilds, greaterThan(near.childBuilds * 20));
      expect(far.peakVelocityJumpRatio, greaterThan(0.02));
    });

    test('interruption takes effect no later than the next logical frame', () {
      for (final MotionPrototypeCandidate candidate
          in MotionPrototypeCandidate.values) {
        final MotionPrototypeTrace trace =
            MotionPrototypeTrajectory.forCandidate(candidate).trace(
          _case(1000),
          viewportExtent: 800,
          interrupt: true,
        );

        expect(trace.interruptionLatencyFrames, lessThanOrEqualTo(1));
        expect(trace.frames.last.logicalPixels,
            trace.frames[trace.frames.length - 2].logicalPixels);
      }
    });
  });
}

MotionPrototypeCase _case(double distance) => MotionPrototypeCase(
      distanceViewports: distance,
      extentProfile: MotionExtentProfile.fixed,
      direction: MotionDirection.forward,
      refreshRateHz: 120,
      interruptAt: 0.5,
    );
