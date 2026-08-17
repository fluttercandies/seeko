/// Immutable metrics for one member in a synchronization transaction.
final class SyncMetrics {
  factory SyncMetrics({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
  }) {
    _requireFinite(pixels, 'pixels');
    _requireFinite(minScrollExtent, 'minScrollExtent');
    _requireFinite(maxScrollExtent, 'maxScrollExtent');
    _requireFinite(viewportExtent, 'viewportExtent');
    if (maxScrollExtent < minScrollExtent) {
      throw ArgumentError.value(
        maxScrollExtent,
        'maxScrollExtent',
        'must be greater than or equal to minScrollExtent',
      );
    }
    if (viewportExtent <= 0) {
      throw ArgumentError.value(
        viewportExtent,
        'viewportExtent',
        'must be positive',
      );
    }
    return SyncMetrics._(
      pixels: pixels,
      minScrollExtent: minScrollExtent,
      maxScrollExtent: maxScrollExtent,
      viewportExtent: viewportExtent,
    );
  }

  const SyncMetrics._({
    required this.pixels,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.viewportExtent,
  });

  final double pixels;
  final double minScrollExtent;
  final double maxScrollExtent;
  final double viewportExtent;

  double get scrollRange => maxScrollExtent - minScrollExtent;

  double get progress {
    final double range = scrollRange;
    if (range == 0) {
      return 0;
    }
    return ((pixels - minScrollExtent) / range).clamp(0, 1);
  }
}

/// Result of projecting one member's position into another member.
final class SyncMappingResult {
  const SyncMappingResult({required this.pixels, required this.clamped});

  final double pixels;
  final bool clamped;
}

/// Built-in and caller-defined canonical synchronization domains.
enum ScrollSyncMappingKind {
  pixels,
  progress,
  delta,
  viewportFraction,
  semantic,
  custom,
}

enum ScrollSyncMissingAnchorPolicy {
  hold,
  fallbackProgress,
  desynchronized,
}

typedef ScrollSyncMemberToGroup = double Function(
  SyncMetrics member,
  double? origin,
);

typedef ScrollSyncGroupToMember = double Function(
  double coordinate,
  SyncMetrics member,
  double? origin,
);

/// Maps one member's logical scroll position into another member.
sealed class ScrollSyncMapping {
  const ScrollSyncMapping._(this.kind, {this.isInvertible = true});

  const factory ScrollSyncMapping.pixels() = PixelScrollSyncMapping;
  const factory ScrollSyncMapping.progress() = ProgressScrollSyncMapping;
  const factory ScrollSyncMapping.delta() = DeltaScrollSyncMapping;
  const factory ScrollSyncMapping.viewportFraction() =
      ViewportFractionScrollSyncMapping;
  const factory ScrollSyncMapping.semantic({
    ScrollSyncMissingAnchorPolicy missingAnchorPolicy,
  }) = SemanticScrollSyncMapping;
  factory ScrollSyncMapping.custom({
    required ScrollSyncMemberToGroup memberToGroup,
    required ScrollSyncGroupToMember groupToMember,
    bool isInvertible,
  }) = CustomScrollSyncMapping;

  final ScrollSyncMappingKind kind;
  final bool isInvertible;

  SyncMappingResult map({
    required SyncMetrics source,
    required SyncMetrics follower,
    double? sourceOrigin,
    double? followerOrigin,
  }) {
    final double coordinate = memberToGroup(
      member: source,
      origin: sourceOrigin,
    );
    final double requested = groupToMember(
      coordinate: coordinate,
      member: follower,
      origin: followerOrigin,
    );
    final double pixels = requested.clamp(
      follower.minScrollExtent,
      follower.maxScrollExtent,
    );
    return SyncMappingResult(pixels: pixels, clamped: pixels != requested);
  }

  /// Returns the unclamped follower position in logical coordinates.
  double project({
    required SyncMetrics source,
    required SyncMetrics follower,
    double? sourceOrigin,
    double? followerOrigin,
  }) {
    final double coordinate = memberToGroup(
      member: source,
      origin: sourceOrigin,
    );
    return groupToMember(
      coordinate: coordinate,
      member: follower,
      origin: followerOrigin,
    );
  }

  /// Projects one member into the group's canonical scalar domain.
  double memberToGroup({required SyncMetrics member, double? origin});

  /// Allocation-free value projection used by the strict synchronization
  /// hot path. Built-in mappings override this directly; custom mappings
  /// receive an immutable [SyncMetrics] value.
  double memberValuesToGroup({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) {
    return memberToGroup(
      member: SyncMetrics(
        pixels: pixels,
        minScrollExtent: minScrollExtent,
        maxScrollExtent: maxScrollExtent,
        viewportExtent: viewportExtent,
      ),
      origin: origin,
    );
  }

  /// Projects a canonical scalar coordinate into one member.
  double groupToMember({
    required double coordinate,
    required SyncMetrics member,
    double? origin,
  });

  /// Allocation-free inverse used by the strict synchronization hot path.
  double groupToMemberValues({
    required double coordinate,
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) {
    return groupToMember(
      coordinate: coordinate,
      member: SyncMetrics(
        pixels: pixels,
        minScrollExtent: minScrollExtent,
        maxScrollExtent: maxScrollExtent,
        viewportExtent: viewportExtent,
      ),
      origin: origin,
    );
  }
}

final class PixelScrollSyncMapping extends ScrollSyncMapping {
  const PixelScrollSyncMapping() : super._(ScrollSyncMappingKind.pixels);

  @override
  double memberToGroup({required SyncMetrics member, double? origin}) =>
      member.pixels - member.minScrollExtent;

  @override
  double memberValuesToGroup({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) =>
      pixels - minScrollExtent;

  @override
  double groupToMember({
    required double coordinate,
    required SyncMetrics member,
    double? origin,
  }) =>
      member.minScrollExtent + coordinate;

  @override
  double groupToMemberValues({
    required double coordinate,
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) =>
      minScrollExtent + coordinate;
}

final class ProgressScrollSyncMapping extends ScrollSyncMapping {
  const ProgressScrollSyncMapping() : super._(ScrollSyncMappingKind.progress);

  @override
  double memberToGroup({required SyncMetrics member, double? origin}) =>
      member.progress;

  @override
  double memberValuesToGroup({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) {
    final double range = maxScrollExtent - minScrollExtent;
    return range == 0 ? 0 : ((pixels - minScrollExtent) / range).clamp(0, 1);
  }

  @override
  double groupToMember({
    required double coordinate,
    required SyncMetrics member,
    double? origin,
  }) =>
      member.minScrollExtent + coordinate * member.scrollRange;

  @override
  double groupToMemberValues({
    required double coordinate,
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) =>
      minScrollExtent + coordinate * (maxScrollExtent - minScrollExtent);
}

final class DeltaScrollSyncMapping extends ScrollSyncMapping {
  const DeltaScrollSyncMapping() : super._(ScrollSyncMappingKind.delta);

  @override
  double memberToGroup({required SyncMetrics member, double? origin}) {
    if (origin == null) {
      throw ArgumentError(
        'Delta mapping requires a member origin from the current transaction '
        'epoch.',
      );
    }
    _requireFinite(origin, 'origin');
    return member.pixels - origin;
  }

  @override
  double memberValuesToGroup({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) {
    if (origin == null) {
      throw ArgumentError('Delta mapping requires a member origin.');
    }
    return pixels - origin;
  }

  @override
  double groupToMember({
    required double coordinate,
    required SyncMetrics member,
    double? origin,
  }) {
    if (origin == null) {
      throw ArgumentError(
        'Delta mapping requires a member origin from the current transaction '
        'epoch.',
      );
    }
    _requireFinite(origin, 'origin');
    return origin + coordinate;
  }

  @override
  double groupToMemberValues({
    required double coordinate,
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) {
    if (origin == null) {
      throw ArgumentError('Delta mapping requires a member origin.');
    }
    return origin + coordinate;
  }
}

final class ViewportFractionScrollSyncMapping extends ScrollSyncMapping {
  const ViewportFractionScrollSyncMapping()
      : super._(ScrollSyncMappingKind.viewportFraction);

  @override
  double memberToGroup({required SyncMetrics member, double? origin}) =>
      (member.pixels - member.minScrollExtent) / member.viewportExtent;

  @override
  double memberValuesToGroup({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) =>
      (pixels - minScrollExtent) / viewportExtent;

  @override
  double groupToMember({
    required double coordinate,
    required SyncMetrics member,
    double? origin,
  }) =>
      member.minScrollExtent + coordinate * member.viewportExtent;

  @override
  double groupToMemberValues({
    required double coordinate,
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
    required double viewportExtent,
    double? origin,
  }) =>
      minScrollExtent + coordinate * viewportExtent;
}

final class SemanticScrollSyncMapping extends ScrollSyncMapping {
  const SemanticScrollSyncMapping({
    this.missingAnchorPolicy = ScrollSyncMissingAnchorPolicy.hold,
  }) : super._(ScrollSyncMappingKind.semantic);

  final ScrollSyncMissingAnchorPolicy missingAnchorPolicy;

  @override
  double memberToGroup({required SyncMetrics member, double? origin}) {
    throw UnsupportedError(
      'Semantic mapping uses ScrollSemanticAnchor rather than scalar metrics.',
    );
  }

  @override
  double groupToMember({
    required double coordinate,
    required SyncMetrics member,
    double? origin,
  }) {
    throw UnsupportedError(
      'Semantic mapping uses ScrollSemanticAnchor rather than scalar metrics.',
    );
  }
}

final class CustomScrollSyncMapping extends ScrollSyncMapping {
  CustomScrollSyncMapping({
    required ScrollSyncMemberToGroup memberToGroup,
    required ScrollSyncGroupToMember groupToMember,
    bool isInvertible = true,
  })  : _memberToGroup = memberToGroup,
        _groupToMember = groupToMember,
        super._(
          ScrollSyncMappingKind.custom,
          isInvertible: isInvertible,
        );

  final ScrollSyncMemberToGroup _memberToGroup;
  final ScrollSyncGroupToMember _groupToMember;

  @override
  double memberToGroup({required SyncMetrics member, double? origin}) {
    final double coordinate = _memberToGroup(member, origin);
    _requireFinite(coordinate, 'custom memberToGroup result');
    return coordinate;
  }

  @override
  double groupToMember({
    required double coordinate,
    required SyncMetrics member,
    double? origin,
  }) {
    _requireFinite(coordinate, 'coordinate');
    final double pixels = _groupToMember(coordinate, member, origin);
    _requireFinite(pixels, 'custom groupToMember result');
    return pixels;
  }
}

void _requireFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
}
