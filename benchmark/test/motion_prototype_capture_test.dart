import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/benchmark_models.dart';
import 'package:seeko_benchmark/src/motion_prototype_capture.dart';
import 'package:seeko_benchmark/src/motion_prototype_models.dart';
import 'package:seeko_benchmark/src/motion_prototype_trajectory.dart';

void main() {
  test('capture derives weighted metrics from raw Flutter evidence', () {
    final MotionPrototypeCase testCase = _case;
    final MotionPrototypeTrajectory trajectory =
        MotionPrototypeTrajectory.forCandidate(
      MotionPrototypeCandidate.virtualWindowRebase,
    );
    final MotionPrototypeCapture capture = MotionPrototypeCapture(
      candidate: MotionPrototypeCandidate.virtualWindowRebase,
      testCase: testCase,
      uninterrupted: trajectory.trace(testCase, viewportExtent: 800),
      interrupted: trajectory.trace(
        testCase,
        viewportExtent: 800,
        interrupt: true,
      ),
      frameSamples: List<BenchmarkFrameSample>.generate(
        20,
        (int index) => BenchmarkFrameSample(
          frameNumber: index,
          buildMicros: 1000 + index * 100,
          rasterMicros: 500,
          totalMicros: 2000 + index * 100,
          vsyncOverheadMicros: 100,
        ),
      ),
      childBuilds: 24,
      peakMemoryBytes: 4096,
    );

    expect(capture.result.frameCostMicros, 2800);
    expect(capture.result.childBuilds, 24);
    expect(capture.result.peakMemoryBytes, 4096);
    expect(capture.result.terminalError, lessThanOrEqualTo(0.5));
    expect(capture.result.interruptionLatencyFrames, lessThanOrEqualTo(1));
    expect(capture.toJson()['frameSamples'], hasLength(20));
  });

  test('qualification result records scores and pending blind review', () {
    final List<MotionPrototypeEvaluationCapture> evaluations =
        MotionPrototypeCandidate.values.map(
      (MotionPrototypeCandidate candidate) {
        final MotionPrototypeTrajectory trajectory =
            MotionPrototypeTrajectory.forCandidate(candidate);
        final MotionPrototypeCapture capture = MotionPrototypeCapture(
          candidate: candidate,
          testCase: _case,
          uninterrupted: trajectory.trace(_case, viewportExtent: 800),
          interrupted: trajectory.trace(
            _case,
            viewportExtent: 800,
            interrupt: true,
          ),
          frameSamples: <BenchmarkFrameSample>[
            const BenchmarkFrameSample(
              frameNumber: 1,
              buildMicros: 1000,
              rasterMicros: 500,
              totalMicros: 2000,
              vsyncOverheadMicros: 100,
            ),
          ],
          childBuilds: switch (candidate) {
            MotionPrototypeCandidate.dualViewportCrossfade => 40,
            MotionPrototypeCandidate.tagSegmentedSearch => 80,
            MotionPrototypeCandidate.virtualWindowRebase => 20,
          },
          peakMemoryBytes: switch (candidate) {
            MotionPrototypeCandidate.dualViewportCrossfade => 6000,
            MotionPrototypeCandidate.tagSegmentedSearch => 4000,
            MotionPrototypeCandidate.virtualWindowRebase => 2000,
          },
        );
        return MotionPrototypeEvaluationCapture(
          candidate: candidate,
          captures: <MotionPrototypeCapture>[capture],
        );
      },
    ).toList(growable: false);

    final MotionPrototypeQualificationResult result =
        MotionPrototypeQualificationResult(
      metadata: _metadata,
      evaluations: evaluations,
      requiredBlindReviewers: 5,
      blindReviews: const <MotionPrototypeBlindReview>[],
    );

    expect(result.toJson()['winner'], isNotNull);
    expect(result.toJson()['blindReviewComplete'], isFalse);
    expect(result.toJson()['requiredBlindReviewers'], 5);
  });
}

final MotionPrototypeCase _case = MotionPrototypeCase(
  distanceViewports: 100,
  extentProfile: MotionExtentProfile.fixed,
  direction: MotionDirection.forward,
  refreshRateHz: 120,
  interruptAt: 0.5,
);

const BenchmarkQualificationMetadata _metadata = BenchmarkQualificationMetadata(
  device: 'test-device',
  operatingSystem: 'test-os',
  thermalState: 'nominal',
  powerState: 'AC / 80%',
  refreshRateHz: 120,
  flutterRevision: '1234567',
  engineRevision: '7654321',
  buildMode: 'profile',
  commit: 'test',
  seed: 24301,
  scenario: 'motion-prototype-comparison',
);
