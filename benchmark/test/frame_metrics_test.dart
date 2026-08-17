import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/benchmark_models.dart';

void main() {
  test('run summary reports deterministic percentile and frame-budget data',
      () {
    final List<BenchmarkFrameSample> samples = <BenchmarkFrameSample>[
      const BenchmarkFrameSample(
        frameNumber: 1,
        buildMicros: 100,
        rasterMicros: 500,
        totalMicros: 1000,
        vsyncOverheadMicros: 20,
      ),
      const BenchmarkFrameSample(
        frameNumber: 2,
        buildMicros: 200,
        rasterMicros: 600,
        totalMicros: 8000,
        vsyncOverheadMicros: 30,
      ),
      const BenchmarkFrameSample(
        frameNumber: 3,
        buildMicros: 300,
        rasterMicros: 700,
        totalMicros: 9000,
        vsyncOverheadMicros: 40,
      ),
      const BenchmarkFrameSample(
        frameNumber: 4,
        buildMicros: 400,
        rasterMicros: 800,
        totalMicros: 17000,
        vsyncOverheadMicros: 50,
      ),
    ];

    final BenchmarkRunResult result = BenchmarkRunResult.fromSamples(
      run: 1,
      elapsed: const Duration(seconds: 30),
      childBuilds: 24,
      samples: samples,
    );

    expect(result.presentedFrames, 4);
    expect(result.buildMicros.p50, 200);
    expect(result.buildMicros.p95, 400);
    expect(result.buildMicros.p99, 400);
    expect(result.rasterMicros.p50, 600);
    expect(result.totalMicros.p95, 17000);
    expect(result.within8333Ratio, 0.5);
    expect(result.within16667Ratio, 0.75);
    expect(result.childBuilds, 24);
    expect(result.toJson()['presentedFrames'], 4);
    expect(
      (result.toJson()['samples']! as List<Object?>).length,
      samples.length,
    );
  });

  test('qualification result preserves required reproducibility metadata', () {
    final BenchmarkQualificationResult result = BenchmarkQualificationResult(
      metadata: const BenchmarkQualificationMetadata(
        device: 'MacBookPro18,4 / Apple M1 Max / 32 GB',
        operatingSystem: 'macOS 26.6 (25G72)',
        thermalState: 'nominal',
        powerState: 'AC / battery 80%',
        refreshRateHz: 120,
        flutterRevision: '559ffa3f75e7402d65a8def9c28389a9b2e6fe42',
        engineRevision: '4c525dac5ebe5971c5708ef73558ed8edcf4a362',
        buildMode: 'profile',
        commit: 'unversioned-worktree',
        seed: 24301,
        scenario: 'native-list-view-builder-fixed-extent',
      ),
      configuration: BenchmarkScenarioConfiguration(
        itemCount: 1000000,
        itemExtent: 56,
        warmUp: Duration(seconds: 5),
        minimumRunDuration: Duration(seconds: 30),
        minimumPresentedFrames: 3600,
        runCount: 1,
      ),
      runs: <BenchmarkRunResult>[
        BenchmarkRunResult.fromSamples(
          run: 1,
          elapsed: const Duration(seconds: 30),
          childBuilds: 1,
          samples: const <BenchmarkFrameSample>[
            BenchmarkFrameSample(
              frameNumber: 1,
              buildMicros: 100,
              rasterMicros: 200,
              totalMicros: 300,
              vsyncOverheadMicros: 10,
            ),
          ],
        ),
      ],
    );

    final Map<String, Object?> json = result.toJson();
    expect(json['schemaVersion'], 1);
    expect(json['refreshRateHz'], 120);
    expect(json['flutterRevision'], startsWith('559ffa3'));
    expect(json['engineRevision'], startsWith('4c525da'));
    expect(json['scenario'], 'native-list-view-builder-fixed-extent');
    expect((json['runs']! as List<Object?>).length, 1);
  });
}
