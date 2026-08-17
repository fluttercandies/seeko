import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/motion_prototype_models.dart';

void main() {
  test('qualification matrix covers every required motion dimension', () {
    final List<MotionPrototypeCase> cases = MotionPrototypeMatrix.standard();

    expect(cases, hasLength(120));
    expect(
      cases.map((MotionPrototypeCase value) => value.distanceViewports).toSet(),
      <double>{0.5, 2, 10, 100, 1000},
    );
    expect(
      cases.map((MotionPrototypeCase value) => value.extentProfile).toSet(),
      MotionExtentProfile.values.toSet(),
    );
    expect(
      cases.map((MotionPrototypeCase value) => value.direction).toSet(),
      MotionDirection.values.toSet(),
    );
    expect(
      cases.map((MotionPrototypeCase value) => value.refreshRateHz).toSet(),
      <int>{60, 120},
    );
    expect(
      cases.map((MotionPrototypeCase value) => value.interruptAt).toSet(),
      <double>{0.25, 0.5, 0.75},
    );
    expect(cases.map((MotionPrototypeCase value) => value.id).toSet(),
        hasLength(120));
  });

  test('hard gates reject an otherwise fast prototype', () {
    final MotionPrototypeEvaluation evaluation = MotionPrototypeEvaluation(
      candidate: MotionPrototypeCandidate.virtualWindowRebase,
      cases: <MotionPrototypeCaseResult>[
        _result(
          terminalError: 0.6,
          peakVelocityJumpRatio: 0.01,
        ),
      ],
    );

    expect(evaluation.passesHardGates, isFalse);
    expect(
      evaluation.hardGateFailures,
      contains(MotionPrototypeHardGate.terminalAccuracy),
    );
  });

  test('hard gates cover continuity, rendering, and interruption', () {
    final MotionPrototypeEvaluation evaluation = MotionPrototypeEvaluation(
      candidate: MotionPrototypeCandidate.dualViewportCrossfade,
      cases: <MotionPrototypeCaseResult>[
        _result(
          peakVelocityJumpRatio: 0.021,
          blankFrames: 1,
          duplicateFrames: 1,
          reverseFrames: 1,
          unintendedOpacityFrames: 1,
          interruptionLatencyFrames: 2,
        ),
      ],
    );

    expect(
      evaluation.hardGateFailures,
      <MotionPrototypeHardGate>{
        MotionPrototypeHardGate.trajectoryContinuity,
        MotionPrototypeHardGate.noBlankFrames,
        MotionPrototypeHardGate.noDuplicateFrames,
        MotionPrototypeHardGate.noReverseFrames,
        MotionPrototypeHardGate.noUnintendedOpacity,
        MotionPrototypeHardGate.interruptionLatency,
      },
    );
  });

  test('hard gates reject child work that grows with skipped distance', () {
    final MotionPrototypeEvaluation evaluation = MotionPrototypeEvaluation(
      candidate: MotionPrototypeCandidate.tagSegmentedSearch,
      cases: <MotionPrototypeCaseResult>[
        _result(testCase: _caseAtDistance(10), childBuilds: 100),
        _result(testCase: _caseAtDistance(1000), childBuilds: 1000),
      ],
    );

    expect(evaluation.passesHardGates, isFalse);
    expect(
      evaluation.hardGateFailures,
      contains(MotionPrototypeHardGate.distanceIndependentBuildWork),
    );
  });

  test('hard gates allow bounded windows across skipped distance', () {
    final MotionPrototypeEvaluation evaluation = MotionPrototypeEvaluation(
      candidate: MotionPrototypeCandidate.virtualWindowRebase,
      cases: <MotionPrototypeCaseResult>[
        _result(testCase: _caseAtDistance(10), childBuilds: 100),
        _result(testCase: _caseAtDistance(1000), childBuilds: 110),
      ],
    );

    expect(
      evaluation.hardGateFailures,
      isNot(contains(MotionPrototypeHardGate.distanceIndependentBuildWork)),
    );
  });

  test('comparison applies the frozen weighted score', () {
    final MotionPrototypeComparison comparison = MotionPrototypeComparison(
      evaluations: <MotionPrototypeEvaluation>[
        MotionPrototypeEvaluation(
          candidate: MotionPrototypeCandidate.dualViewportCrossfade,
          cases: <MotionPrototypeCaseResult>[
            _result(
              frameCostMicros: 7000,
              childBuilds: 60,
              peakMemoryBytes: 600,
              visualDiscontinuity: 0.4,
              interruptionAndReplanCost: 2,
            ),
          ],
        ),
        MotionPrototypeEvaluation(
          candidate: MotionPrototypeCandidate.tagSegmentedSearch,
          cases: <MotionPrototypeCaseResult>[
            _result(
              frameCostMicros: 5000,
              childBuilds: 100,
              peakMemoryBytes: 400,
              visualDiscontinuity: 0.6,
              interruptionAndReplanCost: 3,
            ),
          ],
        ),
        MotionPrototypeEvaluation(
          candidate: MotionPrototypeCandidate.virtualWindowRebase,
          cases: <MotionPrototypeCaseResult>[
            _result(
              frameCostMicros: 3000,
              childBuilds: 20,
              peakMemoryBytes: 200,
              visualDiscontinuity: 0.2,
              interruptionAndReplanCost: 1,
            ),
          ],
        ),
      ],
    );

    expect(
      comparison.winner.candidate,
      MotionPrototypeCandidate.virtualWindowRebase,
    );
    expect(comparison.scoreFor(comparison.winner), 100);
    expect(
      comparison.weights,
      const MotionPrototypeScoreWeights(
        frameTime: 0.30,
        childBuilds: 0.20,
        peakMemory: 0.15,
        visualContinuity: 0.20,
        interruptionAndReplan: 0.15,
      ),
    );
  });
}

MotionPrototypeCaseResult _result({
  MotionPrototypeCase? testCase,
  double terminalError = 0.1,
  double peakVelocityJumpRatio = 0.01,
  int blankFrames = 0,
  int duplicateFrames = 0,
  int reverseFrames = 0,
  int unintendedOpacityFrames = 0,
  int interruptionLatencyFrames = 1,
  double frameCostMicros = 4000,
  int childBuilds = 40,
  int peakMemoryBytes = 300,
  double visualDiscontinuity = 0.3,
  double interruptionAndReplanCost = 1.5,
}) {
  return MotionPrototypeCaseResult(
    testCase: testCase ?? MotionPrototypeMatrix.standard().first,
    terminalError: terminalError,
    peakVelocityJumpRatio: peakVelocityJumpRatio,
    blankFrames: blankFrames,
    duplicateFrames: duplicateFrames,
    reverseFrames: reverseFrames,
    unintendedOpacityFrames: unintendedOpacityFrames,
    interruptionLatencyFrames: interruptionLatencyFrames,
    frameCostMicros: frameCostMicros,
    childBuilds: childBuilds,
    peakMemoryBytes: peakMemoryBytes,
    visualDiscontinuity: visualDiscontinuity,
    interruptionAndReplanCost: interruptionAndReplanCost,
  );
}

MotionPrototypeCase _caseAtDistance(double distanceViewports) =>
    MotionPrototypeCase(
      distanceViewports: distanceViewports,
      extentProfile: MotionExtentProfile.fixed,
      direction: MotionDirection.forward,
      refreshRateHz: 120,
      interruptAt: 0.5,
    );
