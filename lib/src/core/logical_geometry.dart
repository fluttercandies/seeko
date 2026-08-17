import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Converts Flutter position pixels to stable logical leading coordinates.
final class LogicalAxisGeometry {
  LogicalAxisGeometry({
    required this.axisDirection,
    required this.minScrollExtent,
    required this.maxScrollExtent,
  }) {
    if (!minScrollExtent.isFinite || !maxScrollExtent.isFinite) {
      throw ArgumentError('scroll extents must be finite');
    }
    if (maxScrollExtent < minScrollExtent) {
      throw ArgumentError('maxScrollExtent must not precede minScrollExtent');
    }
  }

  final AxisDirection axisDirection;
  final double minScrollExtent;
  final double maxScrollExtent;

  Axis get axis => axisDirectionToAxis(axisDirection);
  double get extent => maxScrollExtent - minScrollExtent;

  double physicalToLogical(double physicalPixels) {
    return physicalPixels - minScrollExtent;
  }

  double logicalToPhysical(double logicalPixels) {
    return minScrollExtent + logicalPixels;
  }
}

/// A half-open interval along the logical scroll axis.
final class LogicalInterval {
  const LogicalInterval(this.start, this.end)
      : assert(start >= 0),
        assert(end >= start);

  final double start;
  final double end;

  double get extent => end - start;

  double intersectionExtent(LogicalInterval other) {
    return math.max(0, math.min(end, other.end) - math.max(start, other.start));
  }

  @override
  bool operator ==(Object other) =>
      other is LogicalInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// A normalized collection of unobstructed viewport intervals.
final class VisibleRegion {
  VisibleRegion._(this.intervals);

  factory VisibleRegion.fromIntervals(Iterable<LogicalInterval> intervals) {
    final List<LogicalInterval> sorted = intervals.toList()
      ..sort(
          (LogicalInterval a, LogicalInterval b) => a.start.compareTo(b.start));
    final List<LogicalInterval> merged = <LogicalInterval>[];
    for (final LogicalInterval interval in sorted) {
      if (interval.extent == 0) {
        continue;
      }
      if (merged.isEmpty || interval.start > merged.last.end) {
        merged.add(interval);
      } else {
        final LogicalInterval previous = merged.removeLast();
        merged.add(
          LogicalInterval(previous.start, math.max(previous.end, interval.end)),
        );
      }
    }
    return VisibleRegion._(List<LogicalInterval>.unmodifiable(merged));
  }

  final List<LogicalInterval> intervals;

  LogicalInterval? get largestInterval {
    if (intervals.isEmpty) {
      return null;
    }
    var result = intervals.first;
    for (final LogicalInterval interval in intervals.skip(1)) {
      if (interval.extent > result.extent) {
        result = interval;
      }
    }
    return result;
  }

  double visibleFraction(LogicalInterval target) {
    if (target.extent == 0) {
      return intervals.any(
        (LogicalInterval interval) =>
            target.start >= interval.start && target.start <= interval.end,
      )
          ? 1
          : 0;
    }
    final double visible = intervals.fold<double>(
      0,
      (double total, LogicalInterval interval) =>
          total + target.intersectionExtent(interval),
    );
    return (visible / target.extent).clamp(0, 1);
  }
}
