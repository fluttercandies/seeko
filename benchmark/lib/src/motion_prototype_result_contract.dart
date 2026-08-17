import 'motion_prototype_models.dart';

abstract final class MotionPrototypeResultContract {
  static const Set<String> _candidateNames = <String>{
    'dualViewportCrossfade',
    'tagSegmentedSearch',
    'virtualWindowRebase',
  };

  static void validate(
    Map<String, Object?> result, {
    required int repeats,
  }) {
    if (result['error'] != null) {
      throw FormatException('Motion prototype failed: ${result['error']}');
    }
    if (result['schemaVersion'] != 1 ||
        result['kind'] != 'motion-prototype-comparison') {
      throw const FormatException(
        'Motion prototype result has an unsupported schema envelope.',
      );
    }
    if (result['matrixCaseCount'] != 120) {
      throw const FormatException(
        'Motion prototype result must use all 120 frozen matrix cases.',
      );
    }
    if (repeats < 1 || repeats > 5) {
      throw RangeError.range(repeats, 1, 5, 'repeats');
    }
    _validateWeights(_object(result, 'weights'));
    final List<Object?> evaluations = _list(result, 'evaluations');
    if (evaluations.length != _candidateNames.length) {
      throw const FormatException(
        'Motion prototype result must contain exactly three evaluations.',
      );
    }
    final Set<String> foundCandidates = <String>{};
    var passingCandidates = 0;
    for (final Object? value in evaluations) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Each evaluation must be an object.');
      }
      final String candidate = _string(value, 'candidate');
      if (!_candidateNames.contains(candidate) ||
          !foundCandidates.add(candidate)) {
        throw FormatException('Invalid or duplicate candidate: $candidate.');
      }
      if (value['passesHardGates'] == true) {
        passingCandidates += 1;
      }
      final Object? score = value['score'];
      if (score is! num || !score.toDouble().isFinite || score < 0) {
        throw FormatException('$candidate score must be non-negative.');
      }
      final List<Object?> captures = _list(value, 'captures');
      final int expectedCaptures = 120 * repeats;
      if (captures.length != expectedCaptures) {
        throw FormatException(
          '$candidate must contain $expectedCaptures captures; '
          'got ${captures.length}.',
        );
      }
      final Map<double, List<double>> buildsByDistance =
          <double, List<double>>{};
      for (final Object? captureValue in captures) {
        if (captureValue is! Map<String, Object?>) {
          throw FormatException('$candidate capture must be an object.');
        }
        final Map<String, Object?> captureResult =
            _object(captureValue, 'result');
        final Object? childBuilds = captureResult['childBuilds'];
        if (childBuilds is! num || childBuilds <= 0) {
          throw FormatException(
            '$candidate capture must rebuild a fresh bounded child window.',
          );
        }
        final Map<String, Object?> testCase = _object(captureResult, 'case');
        final Object? distanceValue = testCase['distanceViewports'];
        if (distanceValue is! num ||
            !distanceValue.toDouble().isFinite ||
            distanceValue <= 0) {
          throw FormatException(
            '$candidate capture distanceViewports must be positive.',
          );
        }
        buildsByDistance
            .putIfAbsent(distanceValue.toDouble(), () => <double>[])
            .add(childBuilds.toDouble());
        final List<Object?> samples = _list(captureValue, 'frameSamples');
        if (samples.isEmpty) {
          throw FormatException('$candidate capture has no FrameTiming data.');
        }
      }
      if (value['passesHardGates'] == true &&
          !motionPrototypeHasDistanceIndependentBuildWork(
            buildsByDistance,
          )) {
        throw FormatException(
          '$candidate cannot pass hard gates because child build work grows '
          'with skipped distance.',
        );
      }
    }
    if (passingCandidates == 0) {
      throw const FormatException('No candidate passed every hard gate.');
    }
    final String winner = _string(result, 'winner');
    if (!foundCandidates.contains(winner)) {
      throw FormatException('Winner $winner is not an evaluated candidate.');
    }
    final int requiredReviewers = _integer(result, 'requiredBlindReviewers');
    if (requiredReviewers != 5) {
      throw const FormatException('Blind review must require five reviewers.');
    }
    _list(result, 'blindReviews');
    if (result['blindReviewComplete'] is! bool) {
      throw const FormatException('blindReviewComplete must be a boolean.');
    }
  }

  static String markdownReport(
    Map<String, Object?> result, {
    required String rawResultPath,
  }) {
    final List<Object?> evaluations = _list(result, 'evaluations');
    final List<Object?> reviews = _list(result, 'blindReviews');
    final int requiredReviewers = _integer(result, 'requiredBlindReviewers');
    final String reviewState =
        result['blindReviewComplete'] == true ? 'complete' : 'pending';
    final StringBuffer buffer = StringBuffer()
      ..writeln('# Long-distance motion prototype comparison')
      ..writeln()
      ..writeln('- Device: ${result['device']}')
      ..writeln('- OS: ${result['operatingSystem']}')
      ..writeln('- Display: ${result['refreshRateHz']} Hz')
      ..writeln('- Flutter: ${result['flutterRevision']}')
      ..writeln('- Engine: ${result['engineRevision']}')
      ..writeln('- Winner by automated gates/weights: `${result['winner']}`')
      ..writeln(
        '- Blind review: $reviewState '
        '(${reviews.length}/$requiredReviewers)',
      )
      ..writeln('- Raw result: `$rawResultPath`')
      ..writeln()
      ..writeln(
        '> Automated selection is provisional until the winner receives '
        'five independent blind reviews with median rating >= 4/5.',
      )
      ..writeln()
      ..writeln(
        '| Candidate | Hard gates | Score | Frame P95 ms | '
        'Avg child builds | Avg peak memory MiB | Visual cost | Interrupt cost |',
      )
      ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final Object? value in evaluations) {
      final Map<String, Object?> evaluation = value! as Map<String, Object?>;
      final bool passed = evaluation['passesHardGates']! as bool;
      buffer.writeln(
        '| ${evaluation['candidate']} | ${passed ? 'pass' : 'fail'} | '
        '${_fixed(evaluation['score'], 2)} | '
        '${_millis(evaluation['frameCostMicros'])} | '
        '${_fixed(evaluation['childBuilds'], 1)} | '
        '${_mebibytes(evaluation['peakMemoryBytes'])} | '
        '${_fixed(evaluation['visualDiscontinuity'], 4)} | '
        '${_fixed(evaluation['interruptionAndReplanCost'], 3)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Child-build scaling by distance')
      ..writeln()
      ..writeln(
        '| Candidate | 0.5 viewport | 2 viewport | 10 viewport | '
        '100 viewport | 1000 viewport |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
    for (final Object? value in evaluations) {
      final Map<String, Object?> evaluation = value! as Map<String, Object?>;
      final Map<double, List<double>> buildsByDistance =
          <double, List<double>>{};
      for (final Object? captureValue in _list(evaluation, 'captures')) {
        final Map<String, Object?> capture =
            captureValue! as Map<String, Object?>;
        final Map<String, Object?> captureResult = _object(capture, 'result');
        final Map<String, Object?> testCase = _object(captureResult, 'case');
        final double distance =
            (testCase['distanceViewports']! as num).toDouble();
        final double childBuilds =
            (captureResult['childBuilds']! as num).toDouble();
        buildsByDistance.putIfAbsent(distance, () => <double>[]).add(
              childBuilds,
            );
      }
      buffer.writeln(
        '| ${evaluation['candidate']} | '
        '${_averageFixed(buildsByDistance[0.5])} | '
        '${_averageFixed(buildsByDistance[2])} | '
        '${_averageFixed(buildsByDistance[10])} | '
        '${_averageFixed(buildsByDistance[100])} | '
        '${_averageFixed(buildsByDistance[1000])} |',
      );
    }
    return buffer.toString();
  }

  static void _validateWeights(Map<String, Object?> weights) {
    const Map<String, double> expected = <String, double>{
      'frameTime': 0.30,
      'childBuilds': 0.20,
      'peakMemory': 0.15,
      'visualContinuity': 0.20,
      'interruptionAndReplan': 0.15,
    };
    for (final MapEntry<String, double> entry in expected.entries) {
      if (weights[entry.key] != entry.value) {
        throw FormatException(
          'Weight ${entry.key} must remain ${entry.value}.',
        );
      }
    }
  }
}

Map<String, Object?> _object(Map<String, Object?> source, String key) {
  final Object? value = source[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('$key must be an object.');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> source, String key) {
  final Object? value = source[key];
  if (value is! List<Object?>) {
    throw FormatException('$key must be an array.');
  }
  return value;
}

String _string(Map<String, Object?> source, String key) {
  final Object? value = source[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

int _integer(Map<String, Object?> source, String key) {
  final Object? value = source[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

String _fixed(Object? value, int digits) =>
    (value! as num).toDouble().toStringAsFixed(digits);

String _millis(Object? micros) =>
    ((micros! as num).toDouble() / 1000).toStringAsFixed(3);

String _mebibytes(Object? bytes) =>
    ((bytes! as num).toDouble() / (1024 * 1024)).toStringAsFixed(3);

String _averageFixed(List<double>? values) {
  if (values == null || values.isEmpty) {
    throw const FormatException(
      'Every candidate must capture each frozen viewport distance.',
    );
  }
  final double total = values.fold(
    0,
    (double sum, double value) => sum + value,
  );
  return (total / values.length).toStringAsFixed(1);
}
