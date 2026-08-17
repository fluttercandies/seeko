import 'dart:math' as math;

import 'benchmark_models.dart';
import 'motion_prototype_models.dart';
import 'motion_prototype_trajectory.dart';

final class MotionPrototypeCapture {
  MotionPrototypeCapture({
    required this.candidate,
    required this.testCase,
    required this.uninterrupted,
    required this.interrupted,
    required Iterable<BenchmarkFrameSample> frameSamples,
    required this.childBuilds,
    required this.peakMemoryBytes,
  }) : frameSamples = List<BenchmarkFrameSample>.unmodifiable(frameSamples) {
    if (uninterrupted.candidate != candidate ||
        interrupted.candidate != candidate) {
      throw ArgumentError(
        'Both traces must use the capture candidate ${candidate.name}.',
      );
    }
    if (uninterrupted.testCase.id != testCase.id ||
        interrupted.testCase.id != testCase.id) {
      throw ArgumentError(
        'Both traces must use the capture case ${testCase.id}.',
      );
    }
    if (uninterrupted.interrupted || !interrupted.interrupted) {
      throw ArgumentError(
        'The capture requires one uninterrupted and one interrupted trace.',
      );
    }
    if (this.frameSamples.isEmpty) {
      throw ArgumentError.value(
        frameSamples,
        'frameSamples',
        'must not be empty',
      );
    }
    if (childBuilds < 0) {
      throw RangeError.value(childBuilds, 'childBuilds');
    }
    if (peakMemoryBytes < 0) {
      throw RangeError.value(peakMemoryBytes, 'peakMemoryBytes');
    }
  }

  final MotionPrototypeCandidate candidate;
  final MotionPrototypeCase testCase;
  final MotionPrototypeTrace uninterrupted;
  final MotionPrototypeTrace interrupted;
  final List<BenchmarkFrameSample> frameSamples;
  final int childBuilds;
  final int peakMemoryBytes;

  late final MotionPrototypeCaseResult result = MotionPrototypeCaseResult(
    testCase: testCase,
    terminalError: uninterrupted.terminalError,
    peakVelocityJumpRatio: math.max(
      uninterrupted.peakVelocityJumpRatio,
      interrupted.peakVelocityJumpRatio,
    ),
    peakAnchorGeometryError: math.max(
      uninterrupted.peakAnchorGeometryError,
      interrupted.peakAnchorGeometryError,
    ),
    blankFrames: uninterrupted.blankFrames + interrupted.blankFrames,
    duplicateFrames:
        uninterrupted.duplicateFrames + interrupted.duplicateFrames,
    reverseFrames: uninterrupted.reverseFrames + interrupted.reverseFrames,
    unintendedOpacityFrames: uninterrupted.unintendedOpacityFrames +
        interrupted.unintendedOpacityFrames,
    interruptionLatencyFrames: interrupted.interruptionLatencyFrames,
    frameCostMicros: BenchmarkPercentiles.fromValues(
      frameSamples.map(
        (BenchmarkFrameSample value) =>
            math.max(value.buildMicros, value.rasterMicros),
      ),
    ).p95.toDouble(),
    childBuilds: childBuilds,
    peakMemoryBytes: peakMemoryBytes,
    visualDiscontinuity: _visualDiscontinuity(
      uninterrupted,
      interrupted,
    ),
    interruptionAndReplanCost:
        interrupted.interruptionLatencyFrames + interrupted.windowRebases / 10,
  );

  Map<String, Object?> toJson() => <String, Object?>{
        'candidate': candidate.name,
        'result': result.toJson(),
        'uninterrupted': _traceJson(uninterrupted),
        'interrupted': _traceJson(interrupted),
        'frameSamples': frameSamples
            .map((BenchmarkFrameSample value) => value.toJson())
            .toList(growable: false),
      };
}

final class MotionPrototypeEvaluationCapture {
  MotionPrototypeEvaluationCapture({
    required this.candidate,
    required Iterable<MotionPrototypeCapture> captures,
  }) : captures = List<MotionPrototypeCapture>.unmodifiable(captures) {
    if (this.captures.isEmpty) {
      throw ArgumentError.value(captures, 'captures', 'must not be empty');
    }
    if (this.captures.any(
          (MotionPrototypeCapture value) => value.candidate != candidate,
        )) {
      throw ArgumentError(
        'Every capture must use candidate ${candidate.name}.',
      );
    }
  }

  final MotionPrototypeCandidate candidate;
  final List<MotionPrototypeCapture> captures;

  late final MotionPrototypeEvaluation evaluation = MotionPrototypeEvaluation(
    candidate: candidate,
    cases: captures.map((MotionPrototypeCapture value) => value.result),
  );

  Map<String, Object?> toJson({required double score}) => <String, Object?>{
        ...evaluation.toJson(),
        'score': score,
        'captures': captures
            .map((MotionPrototypeCapture value) => value.toJson())
            .toList(growable: false),
      };
}

final class MotionPrototypeBlindReview {
  MotionPrototypeBlindReview({
    required this.reviewerId,
    required this.candidate,
    required this.rating,
    required this.notes,
  }) {
    if (reviewerId.trim().isEmpty) {
      throw ArgumentError.value(reviewerId, 'reviewerId', 'must not be empty');
    }
    RangeError.checkValueInInterval(rating, 1, 5, 'rating');
  }

  final String reviewerId;
  final MotionPrototypeCandidate candidate;
  final int rating;
  final String notes;

  Map<String, Object?> toJson() => <String, Object?>{
        'reviewerId': reviewerId,
        'candidate': candidate.name,
        'rating': rating,
        'notes': notes,
      };
}

final class MotionPrototypeQualificationResult {
  MotionPrototypeQualificationResult({
    required this.metadata,
    required Iterable<MotionPrototypeEvaluationCapture> evaluations,
    required this.requiredBlindReviewers,
    required Iterable<MotionPrototypeBlindReview> blindReviews,
  })  : evaluations =
            List<MotionPrototypeEvaluationCapture>.unmodifiable(evaluations),
        blindReviews =
            List<MotionPrototypeBlindReview>.unmodifiable(blindReviews) {
    RangeError.checkValueInInterval(
      requiredBlindReviewers,
      1,
      100,
      'requiredBlindReviewers',
    );
    final Set<MotionPrototypeCandidate> candidates = this
        .evaluations
        .map((MotionPrototypeEvaluationCapture value) => value.candidate)
        .toSet();
    if (candidates.length != MotionPrototypeCandidate.values.length ||
        this.evaluations.length != MotionPrototypeCandidate.values.length) {
      throw ArgumentError(
        'Qualification requires exactly one evaluation for each candidate.',
      );
    }
    final Set<String> reviewers = this
        .blindReviews
        .map((MotionPrototypeBlindReview value) => value.reviewerId)
        .toSet();
    if (reviewers.length != this.blindReviews.length) {
      throw ArgumentError('Blind reviewer ids must be unique.');
    }
  }

  final BenchmarkQualificationMetadata metadata;
  final List<MotionPrototypeEvaluationCapture> evaluations;
  final int requiredBlindReviewers;
  final List<MotionPrototypeBlindReview> blindReviews;

  late final MotionPrototypeComparison comparison = MotionPrototypeComparison(
    evaluations: evaluations.map(
      (MotionPrototypeEvaluationCapture value) => value.evaluation,
    ),
  );

  MotionPrototypeCandidate get winner => comparison.winner.candidate;

  List<MotionPrototypeBlindReview> get winnerReviews => blindReviews
      .where((MotionPrototypeBlindReview value) => value.candidate == winner)
      .toList(growable: false);

  double? get medianWinnerRating {
    if (winnerReviews.isEmpty) {
      return null;
    }
    final List<int> ratings = winnerReviews
        .map((MotionPrototypeBlindReview value) => value.rating)
        .toList(growable: false)
      ..sort();
    final int middle = ratings.length ~/ 2;
    if (ratings.length.isOdd) {
      return ratings[middle].toDouble();
    }
    return (ratings[middle - 1] + ratings[middle]) / 2;
  }

  bool get blindReviewComplete =>
      winnerReviews.length >= requiredBlindReviewers &&
      medianWinnerRating != null &&
      medianWinnerRating! >= 4;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'kind': 'motion-prototype-comparison',
        ...metadata.toJson(),
        'matrixCaseCount': MotionPrototypeMatrix.standard().length,
        'weights': <String, Object?>{
          'frameTime': comparison.weights.frameTime,
          'childBuilds': comparison.weights.childBuilds,
          'peakMemory': comparison.weights.peakMemory,
          'visualContinuity': comparison.weights.visualContinuity,
          'interruptionAndReplan': comparison.weights.interruptionAndReplan,
        },
        'winner': winner.name,
        'evaluations': evaluations
            .map(
              (MotionPrototypeEvaluationCapture value) => value.toJson(
                score: comparison.scoreFor(value.evaluation),
              ),
            )
            .toList(growable: false),
        'requiredBlindReviewers': requiredBlindReviewers,
        'blindReviews': blindReviews
            .map((MotionPrototypeBlindReview value) => value.toJson())
            .toList(growable: false),
        'medianWinnerRating': medianWinnerRating,
        'blindReviewComplete': blindReviewComplete,
      };
}

double _visualDiscontinuity(
  MotionPrototypeTrace uninterrupted,
  MotionPrototypeTrace interrupted,
) {
  final int frameCount = math.max(1, uninterrupted.frames.length);
  final double opacityRatio = uninterrupted.intendedOpacityFrames / frameCount;
  final double duplicateRatio = uninterrupted.duplicateFrames / frameCount;
  return uninterrupted.peakAnchorGeometryError * 2 +
      uninterrupted.peakVelocityJumpRatio +
      opacityRatio +
      duplicateRatio +
      interrupted.peakAnchorGeometryError * 2;
}

Map<String, Object?> _traceJson(MotionPrototypeTrace trace) =>
    <String, Object?>{
      'interrupted': trace.interrupted,
      'targetPixels': trace.targetPixels,
      'terminalError': trace.terminalError,
      'peakVelocityJumpRatio': trace.peakVelocityJumpRatio,
      'peakAnchorGeometryError': trace.peakAnchorGeometryError,
      'childBuilds': trace.childBuilds,
      'peakMemoryBytes': trace.peakMemoryBytes,
      'peakLayerCount': trace.peakLayerCount,
      'windowRebases': trace.windowRebases,
      'blankFrames': trace.blankFrames,
      'duplicateFrames': trace.duplicateFrames,
      'reverseFrames': trace.reverseFrames,
      'intendedOpacityFrames': trace.intendedOpacityFrames,
      'unintendedOpacityFrames': trace.unintendedOpacityFrames,
      'interruptionLatencyFrames': trace.interruptionLatencyFrames,
      'frameCount': trace.frames.length,
    };
