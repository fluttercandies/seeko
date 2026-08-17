import 'dart:async';

import '../core/command_model.dart';
import '../core/motion.dart';
import '../core/scroll_placement.dart';
import '../core/scroll_target.dart';
import 'seeko_snapshot.dart';

/// Resolves the semantic target used by a snap transaction.
sealed class SeekoSnapResolver {
  const SeekoSnapResolver._();

  /// Selects the visible key or index whose leading edge is nearest to
  /// [viewportAnchor].
  const factory SeekoSnapResolver.nearestVisible({
    double viewportAnchor,
  }) = NearestVisibleSeekoSnapResolver;

  /// Delegates target selection to caller-owned synchronous or asynchronous
  /// logic.
  factory SeekoSnapResolver.custom(SeekoSnapTargetResolver resolver) =
      CustomSeekoSnapResolver;

  FutureOr<ScrollTarget?> resolve(ScrollSnapshot snapshot);
}

/// Caller-defined snap target lookup.
typedef SeekoSnapTargetResolver = FutureOr<ScrollTarget?> Function(
  ScrollSnapshot snapshot,
);

/// Built-in nearest-visible semantic snap resolver.
final class NearestVisibleSeekoSnapResolver extends SeekoSnapResolver {
  const NearestVisibleSeekoSnapResolver({this.viewportAnchor = 0})
      : assert(viewportAnchor >= 0 && viewportAnchor <= 1),
        super._();

  final double viewportAnchor;

  @override
  ScrollTarget? resolve(ScrollSnapshot snapshot) {
    if (!viewportAnchor.isFinite || viewportAnchor < 0 || viewportAnchor > 1) {
      throw RangeError.value(
        viewportAnchor,
        'viewportAnchor',
        'must be between 0 and 1',
      );
    }
    ScrollVisibleTarget? nearest;
    var nearestDistance = double.infinity;
    for (final ScrollVisibleTarget target in snapshot.visibleTargets) {
      final double distance =
          (target.leadingViewportFraction - viewportAnchor).abs();
      if (distance < nearestDistance) {
        nearest = target;
        nearestDistance = distance;
      }
    }
    final Object? key = nearest?.key;
    if (key != null) {
      return ScrollTarget.key(key);
    }
    final int? index = nearest?.index;
    return index == null
        ? null
        : ScrollTarget.index(index, tracking: IndexTracking.liveSlot);
  }
}

/// Custom snap resolver without retaining widget contexts in the library.
final class CustomSeekoSnapResolver extends SeekoSnapResolver {
  CustomSeekoSnapResolver(this._resolver) : super._();

  final SeekoSnapTargetResolver _resolver;

  @override
  FutureOr<ScrollTarget?> resolve(ScrollSnapshot snapshot) =>
      _resolver(snapshot);
}

/// Optional automatic and manual snap behavior for one controller.
final class SeekoSnapConfiguration {
  const SeekoSnapConfiguration({
    required this.resolver,
    this.placement = const ScrollPlacement.start(),
    this.motion = const ScrollMotion.spring(),
    this.options = const ScrollCommandOptions(),
  });

  final SeekoSnapResolver resolver;
  final ScrollPlacement placement;
  final ScrollMotion motion;
  final ScrollCommandOptions options;
}
