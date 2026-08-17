/// Selects the semantic anchor preserved across data and extent changes.
sealed class AnchorPolicy {
  const AnchorPolicy._();

  /// Allows content mutations to keep Flutter's current numeric pixels.
  const factory AnchorPolicy.none() = NoAnchorPolicy;

  /// Preserves the first item intersecting the effective viewport.
  const factory AnchorPolicy.firstVisible() = FirstVisibleAnchorPolicy;

  /// Preserves [key], even when it is currently outside the viewport.
  factory AnchorPolicy.explicitKey(Object key) = ExplicitKeyAnchorPolicy;

  /// Follows the trailing edge while the user remains within the threshold.
  factory AnchorPolicy.trailingEdge({double followThreshold}) =
      TrailingEdgeAnchorPolicy;

  /// Preserves the first visible item and chooses its nearest neighbor if it
  /// is deleted.
  const factory AnchorPolicy.nearest() = NearestAnchorPolicy;

  Object? get key => null;
  double? get followThreshold => null;
}

final class NoAnchorPolicy extends AnchorPolicy {
  const NoAnchorPolicy() : super._();

  @override
  bool operator ==(Object other) => other is NoAnchorPolicy;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class FirstVisibleAnchorPolicy extends AnchorPolicy {
  const FirstVisibleAnchorPolicy() : super._();

  @override
  bool operator ==(Object other) => other is FirstVisibleAnchorPolicy;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class ExplicitKeyAnchorPolicy extends AnchorPolicy {
  ExplicitKeyAnchorPolicy(this._key) : super._();

  final Object _key;

  @override
  Object get key => _key;

  @override
  bool operator ==(Object other) =>
      other is ExplicitKeyAnchorPolicy && other.key == key;

  @override
  int get hashCode => Object.hash(ExplicitKeyAnchorPolicy, key);
}

final class TrailingEdgeAnchorPolicy extends AnchorPolicy {
  factory TrailingEdgeAnchorPolicy({double followThreshold = 80}) {
    if (!followThreshold.isFinite) {
      throw ArgumentError.value(
        followThreshold,
        'followThreshold',
        'must be finite',
      );
    }
    if (followThreshold < 0) {
      throw RangeError.value(
        followThreshold,
        'followThreshold',
        'must be non-negative',
      );
    }
    return TrailingEdgeAnchorPolicy._(followThreshold);
  }

  const TrailingEdgeAnchorPolicy._(this._followThreshold) : super._();

  final double _followThreshold;

  @override
  double get followThreshold => _followThreshold;

  @override
  bool operator ==(Object other) =>
      other is TrailingEdgeAnchorPolicy &&
      other.followThreshold == followThreshold;

  @override
  int get hashCode => Object.hash(TrailingEdgeAnchorPolicy, followThreshold);
}

final class NearestAnchorPolicy extends AnchorPolicy {
  const NearestAnchorPolicy() : super._();

  @override
  bool operator ==(Object other) => other is NearestAnchorPolicy;

  @override
  int get hashCode => runtimeType.hashCode;
}
