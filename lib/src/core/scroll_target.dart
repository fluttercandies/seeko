import 'package:flutter/widgets.dart';

/// The logical edge of scrollable content.
enum ScrollEdge { leading, trailing }

/// How an index target behaves when data changes after command submission.
enum IndexTracking {
  /// Captures the stable key at submission and follows that item.
  stableKey,

  /// Resolves the numeric slot when the command executes.
  liveSlot,
}

/// A semantic destination understood by a Seeko scroll driver.
sealed class ScrollTarget {
  const ScrollTarget._();

  /// Creates a target at logical content [pixels].
  factory ScrollTarget.offset(double pixels) {
    _requireFinite(pixels, 'pixels');
    return OffsetScrollTarget._(pixels);
  }

  /// Creates a target for an index in the captured data revision.
  factory ScrollTarget.index(
    int index, {
    IndexTracking tracking = IndexTracking.stableKey,
  }) {
    RangeError.checkNotNegative(index, 'index');
    return IndexScrollTarget._(index, tracking);
  }

  /// Creates a target identified by a stable data [key].
  factory ScrollTarget.key(Object key) = KeyScrollTarget._;

  /// Creates a target for an already mounted [BuildContext].
  factory ScrollTarget.mounted(BuildContext context) = MountedScrollTarget._;

  /// Creates a target for a content [edge].
  const factory ScrollTarget.edge(ScrollEdge edge) = EdgeScrollTarget._;

  /// Creates a normalized finite-range target from zero through one.
  factory ScrollTarget.progress(double value) {
    _requireFinite(value, 'value');
    if (value < 0 || value > 1) {
      throw RangeError.value(value, 'value', 'must be between 0 and 1');
    }
    return ProgressScrollTarget._(value);
  }

  /// Creates a driver-specific target.
  const factory ScrollTarget.custom(Object value) = CustomScrollTarget._;

  double? get pixels => null;
  int? get index => null;
  Object? get key => null;
  BuildContext? get context => null;
  ScrollEdge? get edge => null;
  Object? get value => null;
}

final class OffsetScrollTarget extends ScrollTarget {
  const OffsetScrollTarget._(this._pixels) : super._();

  final double _pixels;

  @override
  double get pixels => _pixels;

  @override
  bool operator ==(Object other) =>
      other is OffsetScrollTarget && other.pixels == pixels;

  @override
  int get hashCode => Object.hash(OffsetScrollTarget, pixels);

  @override
  String toString() => 'ScrollTarget.offset($pixels)';
}

final class IndexScrollTarget extends ScrollTarget {
  const IndexScrollTarget._(this._index, this.tracking) : super._();

  final int _index;
  final IndexTracking tracking;

  @override
  int get index => _index;

  @override
  bool operator ==(Object other) =>
      other is IndexScrollTarget &&
      other.index == index &&
      other.tracking == tracking;

  @override
  int get hashCode => Object.hash(IndexScrollTarget, index, tracking);

  @override
  String toString() => tracking == IndexTracking.stableKey
      ? 'ScrollTarget.index($index)'
      : 'ScrollTarget.index($index, tracking: IndexTracking.liveSlot)';
}

final class KeyScrollTarget extends ScrollTarget {
  const KeyScrollTarget._(this._key) : super._();

  final Object _key;

  @override
  Object get key => _key;

  @override
  bool operator ==(Object other) =>
      other is KeyScrollTarget && other.key == key;

  @override
  int get hashCode => Object.hash(KeyScrollTarget, key);

  @override
  String toString() => 'ScrollTarget.key($key)';
}

final class MountedScrollTarget extends ScrollTarget {
  const MountedScrollTarget._(this._context) : super._();

  final BuildContext _context;

  @override
  BuildContext get context => _context;
}

final class EdgeScrollTarget extends ScrollTarget {
  const EdgeScrollTarget._(this._edge) : super._();

  final ScrollEdge _edge;

  @override
  ScrollEdge get edge => _edge;

  @override
  bool operator ==(Object other) =>
      other is EdgeScrollTarget && other.edge == edge;

  @override
  int get hashCode => Object.hash(EdgeScrollTarget, edge);
}

final class ProgressScrollTarget extends ScrollTarget {
  const ProgressScrollTarget._(this._value) : super._();

  final double _value;

  @override
  double get value => _value;

  @override
  bool operator ==(Object other) =>
      other is ProgressScrollTarget && other.value == value;

  @override
  int get hashCode => Object.hash(ProgressScrollTarget, value);
}

final class CustomScrollTarget extends ScrollTarget {
  const CustomScrollTarget._(this._value) : super._();

  final Object _value;

  @override
  Object get value => _value;

  @override
  bool operator ==(Object other) =>
      other is CustomScrollTarget && other.value == value;

  @override
  int get hashCode => Object.hash(CustomScrollTarget, value);
}

void _requireFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
}
