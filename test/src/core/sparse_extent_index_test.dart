import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/src/core/sparse_extent_index.dart';

void main() {
  test('sparse index updates and inverse queries match a naive model', () {
    const int count = 2000;
    final List<double> model = List<double>.filled(count, 48);
    final SparseExtentIndex index = SparseExtentIndex(
      itemCount: count,
      estimatedExtent: 48,
      blockSize: 64,
    );
    final Random random = Random(712367);

    for (var operation = 0; operation < 100000; operation += 1) {
      if (random.nextBool()) {
        final int target = random.nextInt(count);
        final double extent = 16 + random.nextInt(160).toDouble();
        model[target] = extent;
        index.update(target, extent);
      } else {
        final int target = random.nextInt(count + 1);
        final double expected =
            model.take(target).fold<double>(0, (a, b) => a + b);
        expect(index.offsetOf(target), closeTo(expected, 1e-7));
        if (expected > 0) {
          final int found = index.indexAtOffset(expected - 0.001);
          expect(found, (target - 1).clamp(0, count - 1));
        }
      }
    }
    expect(index.measuredCount, lessThanOrEqualTo(count));
  });

  test('million-item index allocates only measured blocks', () {
    final SparseExtentIndex index = SparseExtentIndex(
      itemCount: 1000000,
      estimatedExtent: 52,
      blockSize: 128,
    );
    index.update(12, 70);
    index.update(999999, 31);
    expect(index.allocatedBlockCount, 2);
    expect(index.offsetOf(1000000), closeTo(52000000 + 18 - 21, 1e-6));
  });

  test('insert remove and move preserve measured extents', () {
    final SparseExtentIndex index = SparseExtentIndex(
      itemCount: 6,
      estimatedExtent: 10,
    );
    index.update(1, 20);
    index.update(4, 40);
    index.insert(2, 2);
    expect(index.itemCount, 8);
    expect(index.extentOf(1), 20);
    expect(index.extentOf(6), 40);
    index.remove(0, 2);
    expect(index.itemCount, 6);
    expect(index.extentOf(4), 40);
    index.move(4, 1, 1);
    expect(index.extentOf(1), 40);
    expect(index.offsetOf(6), 90);
  });

  test('invalidate drops only measurements inside the changed range', () {
    final SparseExtentIndex index = SparseExtentIndex(
      itemCount: 6,
      estimatedExtent: 10,
    );
    index.update(1, 20);
    index.update(3, 30);
    index.update(5, 50);

    index.invalidate(2, 3);

    expect(index.extentOf(1), 20);
    expect(index.extentOf(3), 10);
    expect(index.extentOf(5), 50);
    expect(index.measuredCount, 2);
  });
}
