import 'dart:typed_data';

// This workspace-only harness must measure the exact production kernel while
// keeping it out of Seeko's stable public API.
// ignore: implementation_imports
import 'package:seeko/src/core/scroll_sync_coordinator_kernel.dart';

final class ScrollSyncCoordinatorBenchmarkSample {
  const ScrollSyncCoordinatorBenchmarkSample({
    required this.memberCount,
    required this.measuredIterations,
    required this.appliesPerPropagation,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
    required this.maxMicros,
    required this.checksum,
  });

  final int memberCount;
  final int measuredIterations;
  final int appliesPerPropagation;
  final double p50Micros;
  final double p95Micros;
  final double p99Micros;
  final double maxMicros;
  final double checksum;

  Map<String, Object?> toJson() => <String, Object?>{
        'memberCount': memberCount,
        'measuredIterations': measuredIterations,
        'appliesPerPropagation': appliesPerPropagation,
        'p50Micros': p50Micros,
        'p95Micros': p95Micros,
        'p99Micros': p99Micros,
        'maxMicros': maxMicros,
        'checksum': checksum,
      };
}

final class ScrollSyncCoordinatorBenchmarkResult {
  ScrollSyncCoordinatorBenchmarkResult({
    required this.stopwatchFrequency,
    required this.warmUpIterations,
    required List<ScrollSyncCoordinatorBenchmarkSample> samples,
  }) : samples = List<ScrollSyncCoordinatorBenchmarkSample>.unmodifiable(
          samples,
        );

  final int stopwatchFrequency;
  final int warmUpIterations;
  final List<ScrollSyncCoordinatorBenchmarkSample> samples;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'runtime': const bool.fromEnvironment('dart.vm.product')
            ? 'aot-product'
            : 'jit',
        'stopwatchFrequency': stopwatchFrequency,
        'warmUpIterations': warmUpIterations,
        'samples': samples
            .map(
              (ScrollSyncCoordinatorBenchmarkSample sample) => sample.toJson(),
            )
            .toList(growable: false),
      };
}

ScrollSyncCoordinatorBenchmarkResult runScrollSyncCoordinatorBenchmark({
  Iterable<int> memberCounts = const <int>[
    1,
    2,
    8,
    32,
    128,
    512,
    1024,
  ],
  int warmUpIterations = 10000,
  int measuredIterations = 100000,
}) {
  if (warmUpIterations <= 0) {
    throw RangeError.value(
      warmUpIterations,
      'warmUpIterations',
      'must be positive',
    );
  }
  if (measuredIterations <= 0) {
    throw RangeError.value(
      measuredIterations,
      'measuredIterations',
      'must be positive',
    );
  }
  final List<int> scales = List<int>.unmodifiable(memberCounts);
  if (scales.isEmpty) {
    throw ArgumentError.value(
        memberCounts, 'memberCounts', 'must not be empty');
  }
  for (final int memberCount in scales) {
    if (memberCount <= 0) {
      throw RangeError.value(
        memberCount,
        'memberCounts',
        'must contain only positive values',
      );
    }
  }

  final List<ScrollSyncCoordinatorBenchmarkSample> samples =
      <ScrollSyncCoordinatorBenchmarkSample>[];
  for (final int memberCount in scales) {
    final ScrollSyncCoordinatorKernel kernel = ScrollSyncCoordinatorKernel();
    final List<_BenchmarkParticipant> members =
        List<_BenchmarkParticipant>.generate(
      memberCount,
      (int index) => _BenchmarkParticipant(index),
      growable: false,
    );
    for (final _BenchmarkParticipant member in members) {
      kernel.add(member);
    }
    final _BenchmarkParticipant source = members.first;
    for (var iteration = 0; iteration < warmUpIterations; iteration += 1) {
      final int applied = kernel.propagate(
        source: source,
        coordinate: (iteration & 1023) / 1023,
        transactionId: iteration + 1,
      );
      if (applied != memberCount - 1) {
        throw StateError(
          'Warm-up fan-out mismatch for $memberCount members: $applied.',
        );
      }
    }

    final Int64List elapsedTicks = Int64List(measuredIterations);
    final Stopwatch stopwatch = Stopwatch()..start();
    for (var iteration = 0; iteration < measuredIterations; iteration += 1) {
      final int before = stopwatch.elapsedTicks;
      final int applied = kernel.propagate(
        source: source,
        coordinate: ((iteration + 1) & 1023) / 1023,
        transactionId: warmUpIterations + iteration + 1,
      );
      final int after = stopwatch.elapsedTicks;
      if (applied != memberCount - 1) {
        throw StateError(
          'Measured fan-out mismatch for $memberCount members: $applied.',
        );
      }
      elapsedTicks[iteration] = after - before;
    }
    stopwatch.stop();
    final Int64List sortedTicks = Int64List.fromList(elapsedTicks)..sort();
    var checksum = 0.0;
    for (final _BenchmarkParticipant member in members) {
      checksum += member.accumulator;
    }
    samples.add(
      ScrollSyncCoordinatorBenchmarkSample(
        memberCount: memberCount,
        measuredIterations: measuredIterations,
        appliesPerPropagation: memberCount - 1,
        p50Micros: _ticksToMicros(
          _nearestRank(sortedTicks, 0.50),
        ),
        p95Micros: _ticksToMicros(
          _nearestRank(sortedTicks, 0.95),
        ),
        p99Micros: _ticksToMicros(
          _nearestRank(sortedTicks, 0.99),
        ),
        maxMicros: _ticksToMicros(sortedTicks.last),
        checksum: checksum,
      ),
    );
  }
  return ScrollSyncCoordinatorBenchmarkResult(
    stopwatchFrequency: Stopwatch().frequency,
    warmUpIterations: warmUpIterations,
    samples: samples,
  );
}

int _nearestRank(Int64List sorted, double percentile) {
  final int index = (percentile * sorted.length).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

double _ticksToMicros(int ticks) =>
    ticks * Duration.microsecondsPerSecond / Stopwatch().frequency;

final class _BenchmarkParticipant implements ScrollSyncCoordinatorParticipant {
  _BenchmarkParticipant(this.id);

  final int id;
  double accumulator = 0;

  @override
  bool get participatesInFollowerPropagation => true;

  @override
  @pragma('vm:never-inline')
  bool applyCanonicalCoordinate({
    required double coordinate,
    required int transactionId,
  }) {
    accumulator += coordinate + transactionId + id;
    return true;
  }
}
