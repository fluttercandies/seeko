import 'dart:math' as math;

import 'logical_geometry.dart';

/// The algorithm used to place a target inside the effective viewport.
enum ScrollPlacementMode { exact, nearest, visible }

/// Selects the unobstructed viewport interval used for exact placement.
sealed class ScrollViewportInterval {
  const ScrollViewportInterval._();

  const factory ScrollViewportInterval.largest() =
      LargestScrollViewportInterval._;

  const factory ScrollViewportInterval.at(int index) =
      IndexedScrollViewportInterval._;
}

final class LargestScrollViewportInterval extends ScrollViewportInterval {
  const LargestScrollViewportInterval._() : super._();
}

final class IndexedScrollViewportInterval extends ScrollViewportInterval {
  const IndexedScrollViewportInterval._(this.index)
      : assert(index >= 0),
        super._();

  final int index;

  @override
  bool operator ==(Object other) =>
      other is IndexedScrollViewportInterval && other.index == index;

  @override
  int get hashCode => index;
}

/// Describes target and viewport anchors in logical leading-to-trailing space.
final class ScrollPlacement {
  const ScrollPlacement._({
    required this.mode,
    required this.targetAnchor,
    required this.viewportAnchor,
    required this.offset,
    required this.viewportInterval,
  });

  const ScrollPlacement.start()
      : this._(
          mode: ScrollPlacementMode.exact,
          targetAnchor: 0,
          viewportAnchor: 0,
          offset: 0,
          viewportInterval: const ScrollViewportInterval.largest(),
        );

  const ScrollPlacement.center()
      : this._(
          mode: ScrollPlacementMode.exact,
          targetAnchor: 0.5,
          viewportAnchor: 0.5,
          offset: 0,
          viewportInterval: const ScrollViewportInterval.largest(),
        );

  const ScrollPlacement.end()
      : this._(
          mode: ScrollPlacementMode.exact,
          targetAnchor: 1,
          viewportAnchor: 1,
          offset: 0,
          viewportInterval: const ScrollViewportInterval.largest(),
        );

  const ScrollPlacement.nearest()
      : this._(
          mode: ScrollPlacementMode.nearest,
          targetAnchor: 0.5,
          viewportAnchor: 0.5,
          offset: 0,
          viewportInterval: const ScrollViewportInterval.largest(),
        );

  const ScrollPlacement.visible()
      : this._(
          mode: ScrollPlacementMode.visible,
          targetAnchor: 0.5,
          viewportAnchor: 0.5,
          offset: 0,
          viewportInterval: const ScrollViewportInterval.largest(),
        );

  factory ScrollPlacement.exact({
    required double targetAnchor,
    required double viewportAnchor,
    double offset = 0,
    ScrollViewportInterval viewportInterval =
        const ScrollViewportInterval.largest(),
  }) {
    if (!targetAnchor.isFinite || targetAnchor < 0 || targetAnchor > 1) {
      throw RangeError.value(
        targetAnchor,
        'targetAnchor',
        'must be between 0 and 1',
      );
    }
    if (!viewportAnchor.isFinite || viewportAnchor < 0 || viewportAnchor > 1) {
      throw RangeError.value(
        viewportAnchor,
        'viewportAnchor',
        'must be between 0 and 1',
      );
    }
    if (!offset.isFinite) {
      throw ArgumentError.value(offset, 'offset', 'must be finite');
    }
    return ScrollPlacement._(
      mode: ScrollPlacementMode.exact,
      targetAnchor: targetAnchor,
      viewportAnchor: viewportAnchor,
      offset: offset,
      viewportInterval: viewportInterval,
    );
  }

  final ScrollPlacementMode mode;
  final double targetAnchor;
  final double viewportAnchor;
  final double offset;
  final ScrollViewportInterval viewportInterval;

  @override
  bool operator ==(Object other) =>
      other is ScrollPlacement &&
      other.mode == mode &&
      other.targetAnchor == targetAnchor &&
      other.viewportAnchor == viewportAnchor &&
      other.offset == offset &&
      other.viewportInterval == viewportInterval;

  @override
  int get hashCode =>
      Object.hash(mode, targetAnchor, viewportAnchor, offset, viewportInterval);
}

/// The logical position selected for a target placement request.
final class ScrollPlacementResolution {
  const ScrollPlacementResolution({
    required this.pixels,
    required this.alreadySatisfied,
  });

  /// Content-logical pixels that place the target in the effective viewport.
  final double pixels;

  /// Whether [pixels] equals the current position because the placement was
  /// already satisfied.
  final bool alreadySatisfied;
}

/// Resolves [placement] against unobstructed viewport intervals.
///
/// [target] is expressed in content-logical coordinates. The intervals in
/// [visibleRegion] are viewport-local logical coordinates, before adding
/// [currentPixels]. When several intervals are usable, exact placement uses
/// the largest interval while nearest/visible placement chooses the smallest
/// logical movement.
ScrollPlacementResolution resolveScrollPlacement({
  required ScrollPlacement placement,
  required LogicalInterval target,
  required VisibleRegion visibleRegion,
  required double currentPixels,
}) {
  if (!currentPixels.isFinite) {
    throw ArgumentError.value(
      currentPixels,
      'currentPixels',
      'must be finite',
    );
  }
  if (visibleRegion.intervals.isEmpty) {
    throw StateError('The effective viewport has no visible interval.');
  }

  return switch (placement.mode) {
    ScrollPlacementMode.exact => _resolveExactPlacement(
        placement: placement,
        target: target,
        viewport: _selectViewportInterval(placement, visibleRegion),
        currentPixels: currentPixels,
      ),
    ScrollPlacementMode.nearest => _resolveVisibilityPlacement(
        target: target,
        visibleRegion: visibleRegion,
        currentPixels: currentPixels,
        requireFullVisibility: true,
      ),
    ScrollPlacementMode.visible => _resolveVisibilityPlacement(
        target: target,
        visibleRegion: visibleRegion,
        currentPixels: currentPixels,
        requireFullVisibility: false,
      ),
  };
}

LogicalInterval _selectViewportInterval(
  ScrollPlacement placement,
  VisibleRegion visibleRegion,
) {
  return switch (placement.viewportInterval) {
    LargestScrollViewportInterval() => visibleRegion.largestInterval!,
    IndexedScrollViewportInterval(:final int index) =>
      visibleRegion.intervals[RangeError.checkValidIndex(
        index,
        visibleRegion.intervals,
        'viewportInterval.index',
      )],
  };
}

ScrollPlacementResolution _resolveExactPlacement({
  required ScrollPlacement placement,
  required LogicalInterval target,
  required LogicalInterval viewport,
  required double currentPixels,
}) {
  final double targetPoint =
      target.start + target.extent * placement.targetAnchor;
  final double viewportPoint =
      viewport.start + viewport.extent * placement.viewportAnchor;
  final double pixels = targetPoint - viewportPoint + placement.offset;
  return ScrollPlacementResolution(
    pixels: pixels,
    alreadySatisfied: pixels == currentPixels,
  );
}

ScrollPlacementResolution _resolveVisibilityPlacement({
  required LogicalInterval target,
  required VisibleRegion visibleRegion,
  required double currentPixels,
  required bool requireFullVisibility,
}) {
  double? bestPixels;
  double bestDistance = double.infinity;
  for (final LogicalInterval viewport in visibleRegion.intervals) {
    final double currentTargetStart = target.start - currentPixels;
    final double currentTargetEnd = target.end - currentPixels;
    final bool satisfied = requireFullVisibility
        ? currentTargetStart >= viewport.start &&
            currentTargetEnd <= viewport.end
        : math.min(currentTargetEnd, viewport.end) >
            math.max(currentTargetStart, viewport.start);
    if (satisfied) {
      return ScrollPlacementResolution(
        pixels: currentPixels,
        alreadySatisfied: true,
      );
    }

    final double leadingAligned = target.start - viewport.start;
    final double trailingAligned = target.end - viewport.end;
    final double candidate;
    if (target.extent <= viewport.extent && requireFullVisibility) {
      candidate = currentPixels.clamp(
        math.min(trailingAligned, leadingAligned),
        math.max(trailingAligned, leadingAligned),
      );
    } else {
      final double leadingDistance = (leadingAligned - currentPixels).abs();
      final double trailingDistance = (trailingAligned - currentPixels).abs();
      candidate =
          leadingDistance < trailingDistance ? leadingAligned : trailingAligned;
    }
    final double distance = (candidate - currentPixels).abs();
    if (distance < bestDistance) {
      bestPixels = candidate;
      bestDistance = distance;
    }
  }

  return ScrollPlacementResolution(
    pixels: bestPixels!,
    alreadySatisfied: false,
  );
}
