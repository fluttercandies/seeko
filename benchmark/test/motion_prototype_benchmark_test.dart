import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/benchmark_models.dart';
import 'package:seeko_benchmark/src/motion_prototype_benchmark.dart';
import 'package:seeko_benchmark/src/motion_prototype_models.dart';

void main() {
  testWidgets('motion benchmark exposes the real prototype viewport', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MotionPrototypeBenchmark(
          metadata: _metadata,
          repeats: 1,
          autorun: false,
          exitOnComplete: false,
          cases: <MotionPrototypeCase>[_case],
          candidates: const <MotionPrototypeCandidate>[
            MotionPrototypeCandidate.virtualWindowRebase,
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('motion-prototype-viewport')), findsOneWidget);
    expect(find.textContaining('virtualWindowRebase'), findsOneWidget);
    expect(find.textContaining(_case.id), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion benchmark rejects an empty matrix before running', (
    WidgetTester tester,
  ) async {
    expect(
      () => MotionPrototypeBenchmark(
        metadata: _metadata,
        repeats: 1,
        autorun: false,
        exitOnComplete: false,
        cases: const <MotionPrototypeCase>[],
      ),
      throwsArgumentError,
    );
  });
}

final MotionPrototypeCase _case = MotionPrototypeCase(
  distanceViewports: 1000,
  extentProfile: MotionExtentProfile.deterministicDynamic,
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
