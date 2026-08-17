import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/scroll_sync_coordinator_benchmark.dart';

void main() {
  test('coordinator benchmark covers requested scales and exact fan-out', () {
    final ScrollSyncCoordinatorBenchmarkResult result =
        runScrollSyncCoordinatorBenchmark(
      memberCounts: const <int>[1, 2, 8, 32],
      warmUpIterations: 10,
      measuredIterations: 50,
    );

    expect(
      result.samples.map(
        (ScrollSyncCoordinatorBenchmarkSample sample) => sample.memberCount,
      ),
      <int>[1, 2, 8, 32],
    );
    for (final ScrollSyncCoordinatorBenchmarkSample sample in result.samples) {
      expect(sample.appliesPerPropagation, sample.memberCount - 1);
      expect(sample.measuredIterations, 50);
      expect(sample.p95Micros, greaterThanOrEqualTo(0));
      expect(sample.p99Micros, greaterThanOrEqualTo(sample.p95Micros));
      expect(sample.maxMicros, greaterThanOrEqualTo(sample.p99Micros));
      expect(
        sample.checksum,
        sample.memberCount == 1 ? 0 : isNot(0),
      );
    }
    expect(result.toJson()['schemaVersion'], 1);
  });

  test('coordinator benchmark rejects invalid configurations', () {
    expect(
      () => runScrollSyncCoordinatorBenchmark(
        memberCounts: const <int>[0],
        warmUpIterations: 1,
        measuredIterations: 1,
      ),
      throwsRangeError,
    );
    expect(
      () => runScrollSyncCoordinatorBenchmark(
        memberCounts: const <int>[1],
        warmUpIterations: 0,
        measuredIterations: 1,
      ),
      throwsRangeError,
    );
    expect(
      () => runScrollSyncCoordinatorBenchmark(
        memberCounts: const <int>[1],
        warmUpIterations: 1,
        measuredIterations: 0,
      ),
      throwsRangeError,
    );
  });
}
