import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/g6_core_benchmark.dart';

void main() {
  test('G6 benchmark covers two-dimensional, open, table, and tree paths', () {
    final G6CoreBenchmarkResult result = runG6CoreBenchmark(
      warmUpIterations: 10,
      measuredIterations: 50,
      openItemCount: 200,
    );

    expect(
      result.samples.map((G6CoreBenchmarkSample sample) => sample.name),
      <String>[
        'two-dimensional-million-by-million-geometry',
        'two-dimensional-variable-extent-lookup',
        'table-million-row-cell-resolution',
        'table-column-resize-mutation',
        'open-data-bidirectional-offset-resolution',
        'tree-visible-row-resolution',
        'tree-expand-collapse-mutation',
      ],
    );
    for (final G6CoreBenchmarkSample sample in result.samples) {
      expect(sample.operations, 50);
      expect(sample.p50Micros, greaterThanOrEqualTo(0));
      expect(sample.p95Micros, greaterThanOrEqualTo(sample.p50Micros));
      expect(sample.p99Micros, greaterThanOrEqualTo(sample.p95Micros));
      expect(sample.maxMicros, greaterThanOrEqualTo(sample.p99Micros));
      expect(sample.checksum, isNot(0));
    }
    expect(result.toJson()['schemaVersion'], 1);
  });

  test('G6 benchmark rejects unbounded configurations', () {
    expect(
      () => runG6CoreBenchmark(
        warmUpIterations: 0,
        measuredIterations: 1,
        openItemCount: 1,
      ),
      throwsRangeError,
    );
    expect(
      () => runG6CoreBenchmark(
        warmUpIterations: 1,
        measuredIterations: 0,
        openItemCount: 1,
      ),
      throwsRangeError,
    );
    expect(
      () => runG6CoreBenchmark(
        warmUpIterations: 1,
        measuredIterations: 1,
        openItemCount: 0,
      ),
      throwsRangeError,
    );
  });
}
