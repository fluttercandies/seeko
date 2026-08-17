import 'dart:math' as math;

import 'motion_prototype_models.dart';

final class MotionPrototypeItemGeometry {
  const MotionPrototypeItemGeometry({
    required this.index,
    required this.leading,
    required this.extent,
  });

  final int index;
  final double leading;
  final double extent;

  double get trailing => leading + extent;
}

final class MotionPrototypeContent {
  MotionPrototypeContent(this.profile)
      : _periodExtents = List<double>.generate(
          _periodLength,
          (int index) => _dynamicExtent(index),
          growable: false,
        ) {
    _periodExtent = _periodExtents.fold(
      0,
      (double total, double value) => total + value,
    );
  }

  static const int itemCount = 1000000;
  static const int _periodLength = 64;
  static const double _fixedExtent = 56;

  final MotionExtentProfile profile;
  final List<double> _periodExtents;
  late final double _periodExtent;

  double extentForIndex(int index) {
    RangeError.checkValueInInterval(index, 0, itemCount - 1, 'index');
    return switch (profile) {
      MotionExtentProfile.fixed => _fixedExtent,
      MotionExtentProfile.deterministicDynamic =>
        _periodExtents[index % _periodLength],
    };
  }

  double offsetForIndex(int index) {
    RangeError.checkValueInInterval(index, 0, itemCount - 1, 'index');
    if (profile == MotionExtentProfile.fixed) {
      return index * _fixedExtent;
    }
    final int cycles = index ~/ _periodLength;
    final int remainder = index % _periodLength;
    var offset = cycles * _periodExtent;
    for (var current = 0; current < remainder; current += 1) {
      offset += _periodExtents[current];
    }
    return offset;
  }

  double get contentExtent =>
      offsetForIndex(itemCount - 1) + extentForIndex(itemCount - 1);

  int indexAtOffset(double offset) {
    if (!offset.isFinite || offset < 0 || offset >= contentExtent) {
      throw RangeError.value(
        offset,
        'offset',
        'must be finite and inside [0, $contentExtent)',
      );
    }
    if (profile == MotionExtentProfile.fixed) {
      return (offset / _fixedExtent).floor();
    }
    final int cycles = (offset / _periodExtent).floor();
    final int cycleStartIndex = cycles * _periodLength;
    var remaining = offset - cycles * _periodExtent;
    for (var current = 0; current < _periodLength; current += 1) {
      final double extent = _periodExtents[current];
      if (remaining < extent) {
        return math.min(itemCount - 1, cycleStartIndex + current);
      }
      remaining -= extent;
    }
    return math.min(itemCount - 1, cycleStartIndex + _periodLength - 1);
  }

  List<MotionPrototypeItemGeometry> itemsCovering(
    double contentOffset, {
    required double viewportExtent,
    required double overscan,
  }) {
    if (!contentOffset.isFinite ||
        contentOffset < 0 ||
        contentOffset >= contentExtent) {
      throw RangeError.value(
        contentOffset,
        'contentOffset',
        'must be finite and inside [0, $contentExtent)',
      );
    }
    if (!viewportExtent.isFinite || viewportExtent <= 0) {
      throw RangeError.value(
        viewportExtent,
        'viewportExtent',
        'must be finite and positive',
      );
    }
    if (!overscan.isFinite || overscan < 0) {
      throw RangeError.value(
        overscan,
        'overscan',
        'must be finite and non-negative',
      );
    }
    final double coveredLeading = math.max(0, contentOffset - overscan);
    final double coveredTrailing = math.min(
      contentExtent,
      contentOffset + viewportExtent + overscan,
    );
    var index = indexAtOffset(coveredLeading);
    final List<MotionPrototypeItemGeometry> result =
        <MotionPrototypeItemGeometry>[];
    var leading = offsetForIndex(index);
    while (index < itemCount && leading < coveredTrailing) {
      final double extent = extentForIndex(index);
      result.add(
        MotionPrototypeItemGeometry(
          index: index,
          leading: leading - contentOffset,
          extent: extent,
        ),
      );
      leading += extent;
      index += 1;
    }
    return List<MotionPrototypeItemGeometry>.unmodifiable(result);
  }

  static double _dynamicExtent(int index) => 40 + ((index * 37 + 11) % 8) * 8;
}
