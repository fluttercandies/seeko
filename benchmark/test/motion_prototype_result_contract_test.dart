import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/motion_prototype_result_contract.dart';

void main() {
  test('result contract accepts the complete frozen comparison envelope', () {
    final Map<String, Object?> result = _result();

    MotionPrototypeResultContract.validate(result, repeats: 1);

    final String report = MotionPrototypeResultContract.markdownReport(
      result,
      rawResultPath: '/tmp/motion.json',
    );
    expect(report, contains('virtualWindowRebase'));
    expect(report, contains('Blind review: pending (0/5)'));
    expect(report, contains('/tmp/motion.json'));
    expect(report, contains('Child-build scaling by distance'));
    expect(report, contains('1000 viewport'));
  });

  test('result contract rejects a partial matrix', () {
    final Map<String, Object?> result = _result();
    final List<Object?> evaluations = result['evaluations']! as List<Object?>;
    final Map<String, Object?> first =
        evaluations.first! as Map<String, Object?>;
    (first['captures']! as List<Object?>).removeLast();

    expect(
      () => MotionPrototypeResultContract.validate(result, repeats: 1),
      throwsFormatException,
    );
  });

  test('result contract rejects captures that reused all prior child state',
      () {
    final Map<String, Object?> result = _result();
    final List<Object?> evaluations = result['evaluations']! as List<Object?>;
    final Map<String, Object?> first =
        evaluations.first! as Map<String, Object?>;
    final Map<String, Object?> capture =
        (first['captures']! as List<Object?>).first! as Map<String, Object?>;
    (capture['result']! as Map<String, Object?>)['childBuilds'] = 0;

    expect(
      () => MotionPrototypeResultContract.validate(result, repeats: 1),
      throwsFormatException,
    );
  });

  test('result contract rejects a passing candidate with distance-scaled work',
      () {
    final Map<String, Object?> result = _result();
    final List<Object?> evaluations = result['evaluations']! as List<Object?>;
    final Map<String, Object?> winner =
        evaluations.last! as Map<String, Object?>;
    for (final Object? captureValue in winner['captures']! as List<Object?>) {
      final Map<String, Object?> capture =
          captureValue! as Map<String, Object?>;
      final Map<String, Object?> captureResult =
          capture['result']! as Map<String, Object?>;
      final Map<String, Object?> testCase =
          captureResult['case']! as Map<String, Object?>;
      if (testCase['distanceViewports'] == 1000) {
        captureResult['childBuilds'] = 1000;
      }
    }

    expect(
      () => MotionPrototypeResultContract.validate(result, repeats: 1),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _result() => <String, Object?>{
      'schemaVersion': 1,
      'kind': 'motion-prototype-comparison',
      'device': 'MacBookPro18,4 / Apple M1 Max / 32 GB',
      'operatingSystem': 'macOS 26.6',
      'thermalState': 'nominal',
      'powerState': 'AC / 80%',
      'refreshRateHz': 120,
      'flutterRevision': '1234567',
      'engineRevision': '7654321',
      'buildMode': 'profile',
      'commit': 'test',
      'seed': 24301,
      'scenario': 'motion-prototype-comparison',
      'matrixCaseCount': 120,
      'weights': <String, Object?>{
        'frameTime': 0.30,
        'childBuilds': 0.20,
        'peakMemory': 0.15,
        'visualContinuity': 0.20,
        'interruptionAndReplan': 0.15,
      },
      'winner': 'virtualWindowRebase',
      'evaluations': <Object?>[
        _evaluation('dualViewportCrossfade', 0, false),
        _evaluation('tagSegmentedSearch', 0, false),
        _evaluation('virtualWindowRebase', 100, true),
      ],
      'requiredBlindReviewers': 5,
      'blindReviews': <Object?>[],
      'medianWinnerRating': null,
      'blindReviewComplete': false,
    };

Map<String, Object?> _evaluation(
  String candidate,
  double score,
  bool passes,
) =>
    <String, Object?>{
      'candidate': candidate,
      'passesHardGates': passes,
      'hardGateFailures': passes ? <Object?>[] : <Object?>['continuity'],
      'frameCostMicros': 3000,
      'childBuilds': 20,
      'peakMemoryBytes': 2000,
      'visualDiscontinuity': 0.1,
      'interruptionAndReplanCost': 1,
      'score': score,
      'cases': <Object?>[],
      'captures': List<Object?>.generate(
        120,
        (int index) => <String, Object?>{
          'candidate': candidate,
          'result': <String, Object?>{
            'childBuilds': 20,
            'case': <String, Object?>{
              'distanceViewports': <double>[0.5, 2, 10, 100, 1000][index % 5],
            },
          },
          'uninterrupted': <String, Object?>{},
          'interrupted': <String, Object?>{},
          'frameSamples': <Object?>[
            <String, Object?>{'frameNumber': index},
          ],
        },
      ),
    };
