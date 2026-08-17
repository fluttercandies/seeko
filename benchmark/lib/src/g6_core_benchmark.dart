import 'dart:typed_data';

import 'package:seeko/seeko.dart';

final class G6CoreBenchmarkSample {
  const G6CoreBenchmarkSample({
    required this.name,
    required this.operations,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
    required this.maxMicros,
    required this.checksum,
  });

  final String name;
  final int operations;
  final double p50Micros;
  final double p95Micros;
  final double p99Micros;
  final double maxMicros;
  final double checksum;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'operations': operations,
        'p50Micros': p50Micros,
        'p95Micros': p95Micros,
        'p99Micros': p99Micros,
        'maxMicros': maxMicros,
        'checksum': checksum,
      };
}

final class G6CoreBenchmarkResult {
  G6CoreBenchmarkResult({
    required this.warmUpIterations,
    required List<G6CoreBenchmarkSample> samples,
  }) : samples = List<G6CoreBenchmarkSample>.unmodifiable(samples);

  final int warmUpIterations;
  final List<G6CoreBenchmarkSample> samples;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'runtime': const bool.fromEnvironment('dart.vm.product')
            ? 'aot-product'
            : 'jit',
        'stopwatchFrequency': Stopwatch().frequency,
        'warmUpIterations': warmUpIterations,
        'samples': samples
            .map((G6CoreBenchmarkSample sample) => sample.toJson())
            .toList(growable: false),
      };
}

G6CoreBenchmarkResult runG6CoreBenchmark({
  int warmUpIterations = 10000,
  int measuredIterations = 100000,
  int openItemCount = 100000,
}) {
  _checkPositive(warmUpIterations, 'warmUpIterations');
  _checkPositive(measuredIterations, 'measuredIterations');
  _checkPositive(openItemCount, 'openItemCount');

  final SeekoFiniteTwoDimensionalLayout twoDimensional =
      SeekoFiniteTwoDimensionalLayout.fixed(
    rowCount: 1000000,
    columnCount: 1000000,
    rowExtent: 28,
    columnExtent: 96,
  );
  double twoDimensionalQuery(int iteration) {
    final int row = _mix(iteration) % 1000000;
    final int column = _mix(iteration + 17) % 1000000;
    final SeekoCellGeometry geometry = twoDimensional.geometryFor(
      SeekoCellCoordinate(row, column),
    );
    return geometry.left + geometry.top + geometry.width + geometry.height;
  }

  final SeekoFiniteTwoDimensionalLayout variableTwoDimensional =
      SeekoFiniteTwoDimensionalLayout.variable(
    rowExtents: List<double>.generate(
      100000,
      (int row) => 24 + (row % 13),
      growable: false,
    ),
    columnExtents: List<double>.generate(
      4096,
      (int column) => 72 + (column % 9) * 4,
      growable: false,
    ),
  );
  double variableTwoDimensionalQuery(int iteration) {
    final double rowOffset = (_mix(iteration + 19) / 0x7fffffff) *
        variableTwoDimensional.totalHeight;
    final double columnOffset =
        (_mix(iteration + 23) / 0x7fffffff) * variableTwoDimensional.totalWidth;
    final int row = variableTwoDimensional.rowAtOffset(rowOffset);
    final int column = variableTwoDimensional.columnAtOffset(columnOffset);
    return variableTwoDimensional.rowOffset(row) +
        variableTwoDimensional.columnOffset(column);
  }

  final List<SeekoTableColumn<int>> columns =
      List<SeekoTableColumn<int>>.generate(
    64,
    (int column) => SeekoTableColumn<int>(
      key: column,
      width: 72 + (column % 7) * 8,
    ),
    growable: false,
  );
  final SeekoTableLayout<int, int> table = SeekoTableLayout<int, int>(
    rowCount: 1000000,
    columns: columns,
    rowKeyAt: (int row) => row,
    rowIndexOf: (int row) => row >= 0 && row < 1000000 ? row : null,
    rowExtent: 32,
    frozenPanes: const SeekoFrozenPaneConfiguration(
      rows: 1,
      columns: 2,
    ),
  );
  double tableQuery(int iteration) {
    final int row = _mix(iteration + 31) % 1000000;
    final int column = _mix(iteration + 47) % columns.length;
    final SeekoCellGeometry geometry = table.geometryFor(
      SeekoCellCoordinate(row, column),
    );
    final Object key = table.keyAt(row, column);
    final SeekoCellCoordinate coordinate = table.coordinateOfKey(key)!;
    return geometry.left + geometry.top + coordinate.row + coordinate.column;
  }

  var resizedColumnWidth = 96.0;
  double tableResize(int iteration) {
    resizedColumnWidth = resizedColumnWidth == 96 ? 104 : 96;
    final double delta = table.resizeColumn(0, resizedColumnWidth);
    return delta + table.totalWidth + (iteration.isEven ? 1 : -1);
  }

  final int firstOpenIndex = -(openItemCount ~/ 2);
  final List<SeekoOpenItem<int>> openItems = List<SeekoOpenItem<int>>.generate(
    openItemCount,
    (int position) {
      final int logicalIndex = firstOpenIndex + position;
      return SeekoOpenItem<int>(
        logicalIndex: logicalIndex,
        key: logicalIndex,
        extent: 24 + (position % 11),
      );
    },
    growable: false,
  );
  final SeekoOpenDataController<int> openData = SeekoOpenDataController<int>();
  openData.applyPage(
    SeekoOpenPage<int>(
      items: openItems,
      hasMoreBefore: true,
      hasMoreAfter: true,
      revision: 1,
    ),
  );
  openData.offsetOf(firstOpenIndex);
  double openDataQuery(int iteration) {
    final int logicalIndex =
        firstOpenIndex + (_mix(iteration + 71) % openItemCount);
    final SeekoOpenResolution<int> resolution =
        openData.resolveIndex(logicalIndex);
    return resolution.contentOffset! + resolution.item!.extent;
  }

  final Map<int, SeekoTreeNodeDescriptor<int>> treeNodes =
      <int, SeekoTreeNodeDescriptor<int>>{};
  const int rootCount = 100;
  const int childCount = 100;
  for (var root = 0; root < rootCount; root += 1) {
    final int rootKey = root * (childCount + 1);
    final List<int> children = List<int>.generate(
      childCount,
      (int child) => rootKey + child + 1,
      growable: false,
    );
    treeNodes[rootKey] = SeekoTreeNodeDescriptor<int>(
      key: rootKey,
      children: children,
    );
    for (final int child in children) {
      treeNodes[child] = SeekoTreeNodeDescriptor<int>(
        key: child,
        children: const <int>[],
        extent: 28 + (child % 5),
      );
    }
  }
  final List<int> roots = List<int>.generate(
    rootCount,
    (int root) => root * (childCount + 1),
    growable: false,
  );
  final SeekoTreeTableController<int> tree = SeekoTreeTableController<int>(
    roots: roots,
    resolveNode: (int key) => treeNodes[key]!,
    initiallyExpanded: roots,
  );
  double treeQuery(int iteration) {
    final int visibleIndex = _mix(iteration + 97) % tree.visibleRowCount;
    final int key = tree.visibleRows[visibleIndex].key;
    return tree.offsetOf(key)! + tree.indexOf(key)!;
  }

  double treeMutation(int iteration) {
    final int root = roots[iteration % roots.length];
    final SeekoTreeMutationResult<int> result = tree.toggle(root);
    return result.visibleRowCount + result.pixelCorrection;
  }

  final List<G6CoreBenchmarkSample> samples = <G6CoreBenchmarkSample>[
    _measure(
      name: 'two-dimensional-million-by-million-geometry',
      warmUpIterations: warmUpIterations,
      measuredIterations: measuredIterations,
      operation: twoDimensionalQuery,
    ),
    _measure(
      name: 'two-dimensional-variable-extent-lookup',
      warmUpIterations: warmUpIterations,
      measuredIterations: measuredIterations,
      operation: variableTwoDimensionalQuery,
    ),
    _measure(
      name: 'table-million-row-cell-resolution',
      warmUpIterations: warmUpIterations,
      measuredIterations: measuredIterations,
      operation: tableQuery,
    ),
    _measure(
      name: 'table-column-resize-mutation',
      warmUpIterations: warmUpIterations,
      measuredIterations: measuredIterations,
      operation: tableResize,
    ),
    _measure(
      name: 'open-data-bidirectional-offset-resolution',
      warmUpIterations: warmUpIterations,
      measuredIterations: measuredIterations,
      operation: openDataQuery,
    ),
    _measure(
      name: 'tree-visible-row-resolution',
      warmUpIterations: warmUpIterations,
      measuredIterations: measuredIterations,
      operation: treeQuery,
    ),
    _measure(
      name: 'tree-expand-collapse-mutation',
      warmUpIterations: warmUpIterations,
      measuredIterations: measuredIterations,
      operation: treeMutation,
    ),
  ];
  tree.dispose();
  table.dispose();
  openData.dispose();
  return G6CoreBenchmarkResult(
    warmUpIterations: warmUpIterations,
    samples: samples,
  );
}

typedef _Operation = double Function(int iteration);

G6CoreBenchmarkSample _measure({
  required String name,
  required int warmUpIterations,
  required int measuredIterations,
  required _Operation operation,
}) {
  var checksum = 0.0;
  for (var iteration = 0; iteration < warmUpIterations; iteration += 1) {
    checksum += operation(iteration);
  }
  final Int64List elapsedTicks = Int64List(measuredIterations);
  final Stopwatch stopwatch = Stopwatch()..start();
  for (var iteration = 0; iteration < measuredIterations; iteration += 1) {
    final int before = stopwatch.elapsedTicks;
    checksum += operation(iteration + warmUpIterations);
    elapsedTicks[iteration] = stopwatch.elapsedTicks - before;
  }
  stopwatch.stop();
  elapsedTicks.sort();
  return G6CoreBenchmarkSample(
    name: name,
    operations: measuredIterations,
    p50Micros: _ticksToMicros(_nearestRank(elapsedTicks, 0.50)),
    p95Micros: _ticksToMicros(_nearestRank(elapsedTicks, 0.95)),
    p99Micros: _ticksToMicros(_nearestRank(elapsedTicks, 0.99)),
    maxMicros: _ticksToMicros(elapsedTicks.last),
    checksum: checksum,
  );
}

int _mix(int value) {
  var mixed = value * 1103515245 + 12345;
  mixed ^= mixed >>> 16;
  return mixed & 0x7fffffff;
}

int _nearestRank(Int64List sorted, double percentile) {
  final int index = (percentile * sorted.length).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

double _ticksToMicros(int ticks) =>
    ticks * Duration.microsecondsPerSecond / Stopwatch().frequency;

void _checkPositive(int value, String name) {
  if (value <= 0) {
    throw RangeError.value(value, name, 'must be positive');
  }
}
