import 'dart:math' as math;

final class BenchmarkFrameSample {
  const BenchmarkFrameSample({
    required this.frameNumber,
    required this.buildMicros,
    required this.rasterMicros,
    required this.totalMicros,
    required this.vsyncOverheadMicros,
    this.layerCacheCount = 0,
    this.layerCacheBytes = 0,
    this.pictureCacheCount = 0,
    this.pictureCacheBytes = 0,
  })  : assert(buildMicros >= 0),
        assert(rasterMicros >= 0),
        assert(totalMicros >= 0),
        assert(vsyncOverheadMicros >= 0),
        assert(layerCacheCount >= 0),
        assert(layerCacheBytes >= 0),
        assert(pictureCacheCount >= 0),
        assert(pictureCacheBytes >= 0);

  final int frameNumber;
  final int buildMicros;
  final int rasterMicros;
  final int totalMicros;
  final int vsyncOverheadMicros;
  final int layerCacheCount;
  final int layerCacheBytes;
  final int pictureCacheCount;
  final int pictureCacheBytes;

  Map<String, Object?> toJson() => <String, Object?>{
        'frameNumber': frameNumber,
        'buildMicros': buildMicros,
        'rasterMicros': rasterMicros,
        'totalMicros': totalMicros,
        'vsyncOverheadMicros': vsyncOverheadMicros,
        'layerCacheCount': layerCacheCount,
        'layerCacheBytes': layerCacheBytes,
        'pictureCacheCount': pictureCacheCount,
        'pictureCacheBytes': pictureCacheBytes,
      };
}

final class BenchmarkPercentiles {
  const BenchmarkPercentiles({
    required this.p50,
    required this.p95,
    required this.p99,
    required this.max,
  });

  factory BenchmarkPercentiles.fromValues(Iterable<int> values) {
    final List<int> sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    return BenchmarkPercentiles(
      p50: _nearestRank(sorted, 0.50),
      p95: _nearestRank(sorted, 0.95),
      p99: _nearestRank(sorted, 0.99),
      max: sorted.last,
    );
  }

  final int p50;
  final int p95;
  final int p99;
  final int max;

  Map<String, Object?> toJson() => <String, Object?>{
        'p50': p50,
        'p95': p95,
        'p99': p99,
        'max': max,
      };
}

final class BenchmarkRunResult {
  BenchmarkRunResult.fromSamples({
    required this.run,
    required this.elapsed,
    required this.childBuilds,
    required Iterable<BenchmarkFrameSample> samples,
  }) : samples = List<BenchmarkFrameSample>.unmodifiable(samples) {
    if (run <= 0) {
      throw RangeError.value(run, 'run', 'must be positive');
    }
    if (elapsed <= Duration.zero) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must be positive');
    }
    if (childBuilds < 0) {
      throw RangeError.value(
        childBuilds,
        'childBuilds',
        'must not be negative',
      );
    }
    if (this.samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'must not be empty');
    }
    buildMicros = BenchmarkPercentiles.fromValues(
      this.samples.map((BenchmarkFrameSample sample) => sample.buildMicros),
    );
    rasterMicros = BenchmarkPercentiles.fromValues(
      this.samples.map((BenchmarkFrameSample sample) => sample.rasterMicros),
    );
    totalMicros = BenchmarkPercentiles.fromValues(
      this.samples.map((BenchmarkFrameSample sample) => sample.totalMicros),
    );
    within8333Ratio = _ratioWithin(this.samples, 8333);
    within16667Ratio = _ratioWithin(this.samples, 16667);
  }

  final int run;
  final Duration elapsed;
  final int childBuilds;
  final List<BenchmarkFrameSample> samples;
  late final BenchmarkPercentiles buildMicros;
  late final BenchmarkPercentiles rasterMicros;
  late final BenchmarkPercentiles totalMicros;
  late final double within8333Ratio;
  late final double within16667Ratio;

  int get presentedFrames => samples.length;

  Map<String, Object?> toJson() => <String, Object?>{
        'run': run,
        'elapsedMicros': elapsed.inMicroseconds,
        'presentedFrames': presentedFrames,
        'childBuilds': childBuilds,
        'buildMicros': buildMicros.toJson(),
        'rasterMicros': rasterMicros.toJson(),
        'totalMicros': totalMicros.toJson(),
        'within8333Ratio': within8333Ratio,
        'within16667Ratio': within16667Ratio,
        'samples': samples
            .map((BenchmarkFrameSample sample) => sample.toJson())
            .toList(growable: false),
      };
}

final class BenchmarkQualificationMetadata {
  const BenchmarkQualificationMetadata({
    required this.device,
    required this.operatingSystem,
    required this.thermalState,
    required this.powerState,
    required this.refreshRateHz,
    required this.flutterRevision,
    required this.engineRevision,
    required this.buildMode,
    required this.commit,
    required this.seed,
    required this.scenario,
  })  : assert(refreshRateHz >= 120),
        assert(buildMode == 'profile' || buildMode == 'release');

  final String device;
  final String operatingSystem;
  final String thermalState;
  final String powerState;
  final double refreshRateHz;
  final String flutterRevision;
  final String engineRevision;
  final String buildMode;
  final String commit;
  final int seed;
  final String scenario;

  Map<String, Object?> toJson() => <String, Object?>{
        'device': device,
        'operatingSystem': operatingSystem,
        'thermalState': thermalState,
        'powerState': powerState,
        'refreshRateHz': refreshRateHz,
        'flutterRevision': flutterRevision,
        'engineRevision': engineRevision,
        'buildMode': buildMode,
        'commit': commit,
        'seed': seed,
        'scenario': scenario,
      };
}

final class BenchmarkScenarioConfiguration {
  BenchmarkScenarioConfiguration({
    required this.itemCount,
    required this.itemExtent,
    required this.warmUp,
    required this.minimumRunDuration,
    required this.minimumPresentedFrames,
    required this.runCount,
  }) {
    RangeError.checkValueInInterval(itemCount, 1, 1 << 62, 'itemCount');
    if (!itemExtent.isFinite || itemExtent <= 0) {
      throw RangeError.value(itemExtent, 'itemExtent', 'must be positive');
    }
    if (warmUp <= Duration.zero) {
      throw ArgumentError.value(warmUp, 'warmUp', 'must be positive');
    }
    if (minimumRunDuration <= Duration.zero) {
      throw ArgumentError.value(
        minimumRunDuration,
        'minimumRunDuration',
        'must be positive',
      );
    }
    RangeError.checkValueInInterval(
      minimumPresentedFrames,
      1,
      1 << 62,
      'minimumPresentedFrames',
    );
    RangeError.checkValueInInterval(runCount, 1, 1 << 30, 'runCount');
  }

  final int itemCount;
  final double itemExtent;
  final Duration warmUp;
  final Duration minimumRunDuration;
  final int minimumPresentedFrames;
  final int runCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'itemCount': itemCount,
        'itemExtent': itemExtent,
        'warmUpMicros': warmUp.inMicroseconds,
        'minimumRunDurationMicros': minimumRunDuration.inMicroseconds,
        'minimumPresentedFrames': minimumPresentedFrames,
        'runCount': runCount,
      };
}

final class BenchmarkQualificationResult {
  BenchmarkQualificationResult({
    required this.metadata,
    required this.configuration,
    required Iterable<BenchmarkRunResult> runs,
  }) : runs = List<BenchmarkRunResult>.unmodifiable(runs) {
    if (this.runs.length != configuration.runCount) {
      throw ArgumentError.value(
        this.runs.length,
        'runs.length',
        'must equal configuration.runCount',
      );
    }
  }

  final BenchmarkQualificationMetadata metadata;
  final BenchmarkScenarioConfiguration configuration;
  final List<BenchmarkRunResult> runs;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        ...metadata.toJson(),
        'configuration': configuration.toJson(),
        'runs': runs
            .map((BenchmarkRunResult result) => result.toJson())
            .toList(growable: false),
      };
}

int _nearestRank(List<int> sorted, double percentile) {
  final int rank = math.max(1, (percentile * sorted.length).ceil());
  return sorted[rank - 1];
}

double _ratioWithin(List<BenchmarkFrameSample> samples, int budgetMicros) {
  final int within = samples
      .where(
        (BenchmarkFrameSample sample) => sample.totalMicros <= budgetMicros,
      )
      .length;
  return within / samples.length;
}
