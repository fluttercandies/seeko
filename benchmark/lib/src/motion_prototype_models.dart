enum MotionPrototypeCandidate {
  dualViewportCrossfade,
  tagSegmentedSearch,
  virtualWindowRebase,
}

enum MotionExtentProfile { fixed, deterministicDynamic }

enum MotionDirection { forward, reverse }

const double motionPrototypeMaxFarBuildGrowth = 2;

bool motionPrototypeHasDistanceIndependentBuildWork(
  Map<double, List<double>> buildsByDistance,
) {
  final List<double> distances = buildsByDistance.keys
      .where((double distance) => distance >= 10)
      .toList()
    ..sort();
  if (distances.length < 2) {
    return true;
  }
  final double baselineDistance = distances.first;
  final double farthestDistance = distances.last;
  if (farthestDistance < baselineDistance * 10) {
    return true;
  }
  final double baselineBuilds = _average(
    buildsByDistance[baselineDistance]!,
  );
  final double farthestBuilds = _average(
    buildsByDistance[farthestDistance]!,
  );
  if (baselineBuilds == 0) {
    return farthestBuilds == 0;
  }
  return farthestBuilds <= baselineBuilds * motionPrototypeMaxFarBuildGrowth;
}

enum MotionPrototypeHardGate {
  termination,
  terminalAccuracy,
  trajectoryContinuity,
  visualAnchorContinuity,
  distanceIndependentBuildWork,
  noBlankFrames,
  noDuplicateFrames,
  noReverseFrames,
  noUnintendedOpacity,
  interruptionLatency,
}

final class MotionPrototypeCase {
  MotionPrototypeCase({
    required this.distanceViewports,
    required this.extentProfile,
    required this.direction,
    required this.refreshRateHz,
    required this.interruptAt,
  }) {
    if (!distanceViewports.isFinite || distanceViewports <= 0) {
      throw RangeError.value(
        distanceViewports,
        'distanceViewports',
        'must be finite and positive',
      );
    }
    if (refreshRateHz != 60 && refreshRateHz != 120) {
      throw RangeError.value(
        refreshRateHz,
        'refreshRateHz',
        'must be 60 or 120',
      );
    }
    if (!interruptAt.isFinite || interruptAt <= 0 || interruptAt >= 1) {
      throw RangeError.value(
        interruptAt,
        'interruptAt',
        'must be inside (0, 1)',
      );
    }
  }

  final double distanceViewports;
  final MotionExtentProfile extentProfile;
  final MotionDirection direction;
  final int refreshRateHz;
  final double interruptAt;

  String get id {
    final String distance = distanceViewports.toString().replaceAll('.', 'p');
    final int interruptPercent = (interruptAt * 100).round();
    return '${distance}v-${extentProfile.name}-${direction.name}-'
        '${refreshRateHz}hz-i$interruptPercent';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'distanceViewports': distanceViewports,
        'extentProfile': extentProfile.name,
        'direction': direction.name,
        'refreshRateHz': refreshRateHz,
        'interruptAt': interruptAt,
      };
}

abstract final class MotionPrototypeMatrix {
  static List<MotionPrototypeCase> standard() {
    final List<MotionPrototypeCase> result = <MotionPrototypeCase>[];
    for (final double distance in <double>[0.5, 2, 10, 100, 1000]) {
      for (final MotionExtentProfile extentProfile
          in MotionExtentProfile.values) {
        for (final MotionDirection direction in MotionDirection.values) {
          for (final int refreshRateHz in <int>[60, 120]) {
            for (final double interruptAt in <double>[0.25, 0.5, 0.75]) {
              result.add(
                MotionPrototypeCase(
                  distanceViewports: distance,
                  extentProfile: extentProfile,
                  direction: direction,
                  refreshRateHz: refreshRateHz,
                  interruptAt: interruptAt,
                ),
              );
            }
          }
        }
      }
    }
    return List<MotionPrototypeCase>.unmodifiable(result);
  }
}

final class MotionPrototypeCaseResult {
  MotionPrototypeCaseResult({
    required this.testCase,
    required this.terminalError,
    required this.peakVelocityJumpRatio,
    required this.blankFrames,
    required this.duplicateFrames,
    required this.reverseFrames,
    required this.unintendedOpacityFrames,
    required this.interruptionLatencyFrames,
    required this.frameCostMicros,
    required this.childBuilds,
    required this.peakMemoryBytes,
    required this.visualDiscontinuity,
    required this.interruptionAndReplanCost,
    this.terminated = true,
    this.peakAnchorGeometryError = 0,
  }) {
    _checkFiniteNonNegative(terminalError, 'terminalError');
    _checkFiniteNonNegative(
      peakVelocityJumpRatio,
      'peakVelocityJumpRatio',
    );
    _checkNonNegative(blankFrames, 'blankFrames');
    _checkNonNegative(duplicateFrames, 'duplicateFrames');
    _checkNonNegative(reverseFrames, 'reverseFrames');
    _checkNonNegative(unintendedOpacityFrames, 'unintendedOpacityFrames');
    _checkNonNegative(
      interruptionLatencyFrames,
      'interruptionLatencyFrames',
    );
    _checkFiniteNonNegative(frameCostMicros, 'frameCostMicros');
    _checkNonNegative(childBuilds, 'childBuilds');
    _checkNonNegative(peakMemoryBytes, 'peakMemoryBytes');
    _checkFiniteNonNegative(visualDiscontinuity, 'visualDiscontinuity');
    _checkFiniteNonNegative(
      interruptionAndReplanCost,
      'interruptionAndReplanCost',
    );
    _checkFiniteNonNegative(
      peakAnchorGeometryError,
      'peakAnchorGeometryError',
    );
  }

  final MotionPrototypeCase testCase;
  final bool terminated;
  final double terminalError;
  final double peakVelocityJumpRatio;
  final double peakAnchorGeometryError;
  final int blankFrames;
  final int duplicateFrames;
  final int reverseFrames;
  final int unintendedOpacityFrames;
  final int interruptionLatencyFrames;
  final double frameCostMicros;
  final int childBuilds;
  final int peakMemoryBytes;
  final double visualDiscontinuity;
  final double interruptionAndReplanCost;

  Set<MotionPrototypeHardGate> get hardGateFailures {
    final Set<MotionPrototypeHardGate> failures = <MotionPrototypeHardGate>{};
    if (!terminated) {
      failures.add(MotionPrototypeHardGate.termination);
    }
    if (terminalError > 0.5) {
      failures.add(MotionPrototypeHardGate.terminalAccuracy);
    }
    if (peakVelocityJumpRatio > 0.02) {
      failures.add(MotionPrototypeHardGate.trajectoryContinuity);
    }
    if (peakAnchorGeometryError > 0.5) {
      failures.add(MotionPrototypeHardGate.visualAnchorContinuity);
    }
    if (blankFrames != 0) {
      failures.add(MotionPrototypeHardGate.noBlankFrames);
    }
    if (duplicateFrames != 0) {
      failures.add(MotionPrototypeHardGate.noDuplicateFrames);
    }
    if (reverseFrames != 0) {
      failures.add(MotionPrototypeHardGate.noReverseFrames);
    }
    if (unintendedOpacityFrames != 0) {
      failures.add(MotionPrototypeHardGate.noUnintendedOpacity);
    }
    if (interruptionLatencyFrames > 1) {
      failures.add(MotionPrototypeHardGate.interruptionLatency);
    }
    return failures;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'case': testCase.toJson(),
        'terminated': terminated,
        'terminalError': terminalError,
        'peakVelocityJumpRatio': peakVelocityJumpRatio,
        'peakAnchorGeometryError': peakAnchorGeometryError,
        'blankFrames': blankFrames,
        'duplicateFrames': duplicateFrames,
        'reverseFrames': reverseFrames,
        'unintendedOpacityFrames': unintendedOpacityFrames,
        'interruptionLatencyFrames': interruptionLatencyFrames,
        'frameCostMicros': frameCostMicros,
        'childBuilds': childBuilds,
        'peakMemoryBytes': peakMemoryBytes,
        'visualDiscontinuity': visualDiscontinuity,
        'interruptionAndReplanCost': interruptionAndReplanCost,
        'hardGateFailures': hardGateFailures
            .map((MotionPrototypeHardGate value) => value.name)
            .toList(growable: false),
      };
}

final class MotionPrototypeEvaluation {
  MotionPrototypeEvaluation({
    required this.candidate,
    required Iterable<MotionPrototypeCaseResult> cases,
  }) : cases = List<MotionPrototypeCaseResult>.unmodifiable(cases) {
    if (this.cases.isEmpty) {
      throw ArgumentError.value(cases, 'cases', 'must not be empty');
    }
  }

  final MotionPrototypeCandidate candidate;
  final List<MotionPrototypeCaseResult> cases;

  Set<MotionPrototypeHardGate> get hardGateFailures {
    final Set<MotionPrototypeHardGate> failures = cases.fold(
      <MotionPrototypeHardGate>{},
      (
        Set<MotionPrototypeHardGate> accumulated,
        MotionPrototypeCaseResult result,
      ) =>
          accumulated..addAll(result.hardGateFailures),
    );
    if (!_hasDistanceIndependentBuildWork) {
      failures.add(MotionPrototypeHardGate.distanceIndependentBuildWork);
    }
    return failures;
  }

  bool get _hasDistanceIndependentBuildWork {
    final Map<double, List<double>> buildsByDistance = <double, List<double>>{};
    for (final MotionPrototypeCaseResult result in cases) {
      final double distance = result.testCase.distanceViewports;
      if (distance < 10) {
        continue;
      }
      buildsByDistance
          .putIfAbsent(distance, () => <double>[])
          .add(result.childBuilds.toDouble());
    }
    return motionPrototypeHasDistanceIndependentBuildWork(buildsByDistance);
  }

  bool get passesHardGates => hardGateFailures.isEmpty;
  double get frameCostMicros => _average(
        cases.map((MotionPrototypeCaseResult value) => value.frameCostMicros),
      );
  double get childBuilds => _average(
        cases.map(
          (MotionPrototypeCaseResult value) => value.childBuilds.toDouble(),
        ),
      );
  double get peakMemoryBytes => _average(
        cases.map(
          (MotionPrototypeCaseResult value) => value.peakMemoryBytes.toDouble(),
        ),
      );
  double get visualDiscontinuity => _average(
        cases.map(
          (MotionPrototypeCaseResult value) => value.visualDiscontinuity,
        ),
      );
  double get interruptionAndReplanCost => _average(
        cases.map(
          (MotionPrototypeCaseResult value) => value.interruptionAndReplanCost,
        ),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'candidate': candidate.name,
        'passesHardGates': passesHardGates,
        'hardGateFailures': hardGateFailures
            .map((MotionPrototypeHardGate value) => value.name)
            .toList(growable: false),
        'frameCostMicros': frameCostMicros,
        'childBuilds': childBuilds,
        'peakMemoryBytes': peakMemoryBytes,
        'visualDiscontinuity': visualDiscontinuity,
        'interruptionAndReplanCost': interruptionAndReplanCost,
        'cases': cases
            .map((MotionPrototypeCaseResult value) => value.toJson())
            .toList(growable: false),
      };
}

final class MotionPrototypeScoreWeights {
  const MotionPrototypeScoreWeights({
    required this.frameTime,
    required this.childBuilds,
    required this.peakMemory,
    required this.visualContinuity,
    required this.interruptionAndReplan,
  });

  static const MotionPrototypeScoreWeights frozen = MotionPrototypeScoreWeights(
    frameTime: 0.30,
    childBuilds: 0.20,
    peakMemory: 0.15,
    visualContinuity: 0.20,
    interruptionAndReplan: 0.15,
  );

  final double frameTime;
  final double childBuilds;
  final double peakMemory;
  final double visualContinuity;
  final double interruptionAndReplan;

  @override
  bool operator ==(Object other) =>
      other is MotionPrototypeScoreWeights &&
      other.frameTime == frameTime &&
      other.childBuilds == childBuilds &&
      other.peakMemory == peakMemory &&
      other.visualContinuity == visualContinuity &&
      other.interruptionAndReplan == interruptionAndReplan;

  @override
  int get hashCode => Object.hash(
        frameTime,
        childBuilds,
        peakMemory,
        visualContinuity,
        interruptionAndReplan,
      );
}

final class MotionPrototypeComparison {
  MotionPrototypeComparison({
    required Iterable<MotionPrototypeEvaluation> evaluations,
    this.weights = MotionPrototypeScoreWeights.frozen,
  }) : evaluations = List<MotionPrototypeEvaluation>.unmodifiable(
          evaluations,
        ) {
    if (this.evaluations.isEmpty) {
      throw ArgumentError.value(
        evaluations,
        'evaluations',
        'must not be empty',
      );
    }
    final Set<MotionPrototypeCandidate> candidates = this
        .evaluations
        .map((MotionPrototypeEvaluation value) => value.candidate)
        .toSet();
    if (candidates.length != this.evaluations.length) {
      throw ArgumentError.value(
        evaluations,
        'evaluations',
        'must contain each candidate at most once',
      );
    }
    if (!this.evaluations.any(
          (MotionPrototypeEvaluation value) => value.passesHardGates,
        )) {
      throw StateError('At least one prototype must pass every hard gate.');
    }
  }

  final List<MotionPrototypeEvaluation> evaluations;
  final MotionPrototypeScoreWeights weights;

  MotionPrototypeEvaluation get winner {
    final List<MotionPrototypeEvaluation> eligible = evaluations
        .where((MotionPrototypeEvaluation value) => value.passesHardGates)
        .toList(growable: false);
    return eligible.reduce(
      (MotionPrototypeEvaluation best, MotionPrototypeEvaluation candidate) =>
          scoreFor(candidate) > scoreFor(best) ? candidate : best,
    );
  }

  double scoreFor(MotionPrototypeEvaluation evaluation) {
    if (!evaluation.passesHardGates) {
      return 0;
    }
    final List<MotionPrototypeEvaluation> eligible = evaluations
        .where((MotionPrototypeEvaluation value) => value.passesHardGates)
        .toList(growable: false);
    return 100 *
        (weights.frameTime *
                _lowerIsBetter(
                    evaluation.frameCostMicros,
                    eligible,
                    (MotionPrototypeEvaluation value) =>
                        value.frameCostMicros) +
            weights.childBuilds *
                _lowerIsBetter(evaluation.childBuilds, eligible,
                    (MotionPrototypeEvaluation value) => value.childBuilds) +
            weights.peakMemory *
                _lowerIsBetter(
                    evaluation.peakMemoryBytes,
                    eligible,
                    (MotionPrototypeEvaluation value) =>
                        value.peakMemoryBytes) +
            weights.visualContinuity *
                _lowerIsBetter(
                    evaluation.visualDiscontinuity,
                    eligible,
                    (MotionPrototypeEvaluation value) =>
                        value.visualDiscontinuity) +
            weights.interruptionAndReplan *
                _lowerIsBetter(
                  evaluation.interruptionAndReplanCost,
                  eligible,
                  (MotionPrototypeEvaluation value) =>
                      value.interruptionAndReplanCost,
                ));
  }
}

double _average(Iterable<double> values) {
  var total = 0.0;
  var count = 0;
  for (final double value in values) {
    total += value;
    count += 1;
  }
  return total / count;
}

double _lowerIsBetter(
  double value,
  List<MotionPrototypeEvaluation> evaluations,
  double Function(MotionPrototypeEvaluation value) select,
) {
  final Iterable<double> values = evaluations.map(select);
  final double minimum = values.reduce((double a, double b) => a < b ? a : b);
  final double maximum = values.reduce((double a, double b) => a > b ? a : b);
  if (maximum == minimum) {
    return 1;
  }
  return (maximum - value) / (maximum - minimum);
}

void _checkFiniteNonNegative(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw RangeError.value(value, name, 'must be finite and non-negative');
  }
}

void _checkNonNegative(int value, String name) {
  if (value < 0) {
    throw RangeError.value(value, name, 'must be non-negative');
  }
}
