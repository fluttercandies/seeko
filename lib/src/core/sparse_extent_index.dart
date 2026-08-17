import 'dart:math' as math;

/// An implicit sparse segment tree for measured and estimated item extents.
///
/// Unmeasured consecutive items occupy a single run. Measured items are
/// represented independently, so memory grows with measurements and structural
/// edits rather than the logical item count.
final class SparseExtentIndex {
  SparseExtentIndex({
    required int itemCount,
    required this.estimatedExtent,
    this.blockSize = 128,
  }) {
    RangeError.checkNotNegative(itemCount, 'itemCount');
    if (!estimatedExtent.isFinite || estimatedExtent <= 0) {
      throw ArgumentError.value(
        estimatedExtent,
        'estimatedExtent',
        'must be finite and positive',
      );
    }
    RangeError.checkValueInInterval(blockSize, 8, 4096, 'blockSize');
    if (itemCount > 0) {
      _root = _newNode(itemCount, estimatedExtent, false);
    }
  }

  final double estimatedExtent;

  /// Retained as an observable tuning unit for diagnostics compatibility.
  final int blockSize;

  _ExtentNode? _root;
  int _prioritySeed = 0;

  int get itemCount => _root?.subtreeCount ?? 0;
  int get measuredCount => _root?.subtreeMeasuredCount ?? 0;
  double get totalExtent => _root?.subtreeExtent ?? 0;
  double get measuredExtent => _root?.subtreeMeasuredExtent ?? 0;
  double get estimatedExtentTotal => totalExtent - measuredExtent;

  /// Number of sparse measured regions currently retained.
  int get allocatedBlockCount => _countMeasuredRuns(_root);

  void update(int index, double extent) {
    RangeError.checkValidIndex(index, this, 'index', itemCount);
    if (!extent.isFinite || extent < 0) {
      throw ArgumentError.value(
        extent,
        'extent',
        'must be finite and non-negative',
      );
    }
    final _Split before = _split(_root, index);
    final _Split selected = _split(before.right, 1);
    _root = _join(
      _join(before.left, _newNode(1, extent, true)),
      selected.right,
    );
  }

  void insert(int index, int count) {
    RangeError.checkValueInInterval(index, 0, itemCount, 'index');
    RangeError.checkValueInInterval(count, 1, 0x7fffffff, 'count');
    final _Split split = _split(_root, index);
    _root = _join(
      _join(split.left, _newNode(count, estimatedExtent, false)),
      split.right,
    );
  }

  void remove(int index, int count) {
    _checkSpan(index, count);
    final _Split before = _split(_root, index);
    final _Split removed = _split(before.right, count);
    _root = _join(before.left, removed.right);
  }

  /// Discards measurements for a contiguous range without changing indexes.
  void invalidate(int index, int count) {
    _checkSpan(index, count);
    final _Split before = _split(_root, index);
    final _Split invalidated = _split(before.right, count);
    _root = _join(
      _join(before.left, _newNode(count, estimatedExtent, false)),
      invalidated.right,
    );
  }

  /// Moves [count] items so the first moved item lands at [to] in the list
  /// after the source range has been removed.
  void move(int from, int to, int count) {
    _checkSpan(from, count);
    final int remainingCount = itemCount - count;
    RangeError.checkValueInInterval(to, 0, remainingCount, 'to');
    if (from == to || count == 0) {
      return;
    }
    final _Split before = _split(_root, from);
    final _Split selected = _split(before.right, count);
    final _ExtentNode? without = _join(before.left, selected.right);
    final _Split destination = _split(without, to);
    _root = _join(_join(destination.left, selected.left), destination.right);
  }

  double offsetOf(int index) {
    RangeError.checkValueInInterval(index, 0, itemCount, 'index');
    var remaining = index;
    var result = 0.0;
    var node = _root;
    while (node != null && remaining > 0) {
      final int leftCount = node.left?.subtreeCount ?? 0;
      if (remaining <= leftCount) {
        node = node.left;
        continue;
      }
      result += node.left?.subtreeExtent ?? 0;
      remaining -= leftCount;
      final int within = math.min(remaining, node.runLength);
      result += within * node.extent;
      remaining -= within;
      if (remaining == 0) {
        break;
      }
      node = node.right;
    }
    return result;
  }

  double extentOf(int index) {
    RangeError.checkValidIndex(index, this, 'index', itemCount);
    var remaining = index;
    var node = _root;
    while (node != null) {
      final int leftCount = node.left?.subtreeCount ?? 0;
      if (remaining < leftCount) {
        node = node.left;
      } else if (remaining < leftCount + node.runLength) {
        return node.extent;
      } else {
        remaining -= leftCount + node.runLength;
        node = node.right;
      }
    }
    throw StateError('extent tree is inconsistent');
  }

  int indexAtOffset(double offset) {
    if (!offset.isFinite) {
      throw ArgumentError.value(offset, 'offset', 'must be finite');
    }
    if (itemCount == 0 || offset <= 0) {
      return 0;
    }
    final double total = _root!.subtreeExtent;
    if (offset >= total) {
      return itemCount - 1;
    }
    var precedingCount = 0;
    var remaining = offset;
    var node = _root;
    while (node != null) {
      final double leftExtent = node.left?.subtreeExtent ?? 0;
      final int leftCount = node.left?.subtreeCount ?? 0;
      if (remaining < leftExtent) {
        node = node.left;
        continue;
      }
      remaining -= leftExtent;
      precedingCount += leftCount;
      final double runExtent = node.extent * node.runLength;
      if (remaining < runExtent || node.extent == 0) {
        final int within = node.extent == 0
            ? 0
            : (remaining / node.extent).floor().clamp(0, node.runLength - 1);
        return precedingCount + within;
      }
      remaining -= runExtent;
      precedingCount += node.runLength;
      node = node.right;
    }
    return itemCount - 1;
  }

  void _checkSpan(int index, int count) {
    RangeError.checkNotNegative(index, 'index');
    RangeError.checkValueInInterval(count, 1, 0x7fffffff, 'count');
    if (index + count > itemCount) {
      throw RangeError.range(index + count, 0, itemCount, 'index + count');
    }
  }

  _ExtentNode _newNode(int length, double extent, bool measured) {
    _prioritySeed += 1;
    final int mixed = (_prioritySeed * 0x9e3779b1) & 0x7fffffff;
    return _ExtentNode(length, extent, measured, mixed);
  }

  _Split _split(_ExtentNode? root, int count) {
    if (root == null) {
      return const _Split(null, null);
    }
    final int leftCount = root.left?.subtreeCount ?? 0;
    if (count < leftCount) {
      final _Split split = _split(root.left, count);
      root.left = split.right;
      root.refresh();
      return _Split(split.left, root);
    }
    if (count > leftCount + root.runLength) {
      final _Split split = _split(
        root.right,
        count - leftCount - root.runLength,
      );
      root.right = split.left;
      root.refresh();
      return _Split(root, split.right);
    }
    if (count == leftCount) {
      final _ExtentNode? left = root.left;
      root.left = null;
      root.refresh();
      return _Split(left, root);
    }
    if (count == leftCount + root.runLength) {
      final _ExtentNode? right = root.right;
      root.right = null;
      root.refresh();
      return _Split(root, right);
    }

    final int leftRunLength = count - leftCount;
    final int rightRunLength = root.runLength - leftRunLength;
    final _ExtentNode leftRun =
        _newNode(leftRunLength, root.extent, root.measured);
    final _ExtentNode rightRun =
        _newNode(rightRunLength, root.extent, root.measured);
    leftRun.left = root.left;
    rightRun.right = root.right;
    leftRun.refresh();
    rightRun.refresh();
    return _Split(leftRun, rightRun);
  }

  _ExtentNode? _join(_ExtentNode? left, _ExtentNode? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    if (left.priority >= right.priority) {
      left.right = _join(left.right, right);
      left.refresh();
      return left;
    }
    right.left = _join(left, right.left);
    right.refresh();
    return right;
  }
}

final class _ExtentNode {
  _ExtentNode(this.runLength, this.extent, this.measured, this.priority) {
    refresh();
  }

  final int runLength;
  final double extent;
  final bool measured;
  final int priority;
  _ExtentNode? left;
  _ExtentNode? right;
  late int subtreeCount;
  late int subtreeMeasuredCount;
  late double subtreeExtent;
  late double subtreeMeasuredExtent;

  void refresh() {
    subtreeCount =
        (left?.subtreeCount ?? 0) + runLength + (right?.subtreeCount ?? 0);
    subtreeMeasuredCount = (left?.subtreeMeasuredCount ?? 0) +
        (measured ? runLength : 0) +
        (right?.subtreeMeasuredCount ?? 0);
    subtreeExtent = (left?.subtreeExtent ?? 0) +
        runLength * extent +
        (right?.subtreeExtent ?? 0);
    subtreeMeasuredExtent = (left?.subtreeMeasuredExtent ?? 0) +
        (measured ? runLength * extent : 0) +
        (right?.subtreeMeasuredExtent ?? 0);
  }
}

final class _Split {
  const _Split(this.left, this.right);
  final _ExtentNode? left;
  final _ExtentNode? right;
}

int _countMeasuredRuns(_ExtentNode? node) {
  if (node == null) {
    return 0;
  }
  return _countMeasuredRuns(node.left) +
      (node.measured ? 1 : 0) +
      _countMeasuredRuns(node.right);
}
