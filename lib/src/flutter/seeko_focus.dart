import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/command_model.dart';
import '../core/logical_geometry.dart';
import '../core/motion.dart';
import '../core/scroll_placement.dart';
import '../core/scroll_target.dart';
import 'seeko_controller.dart';

typedef SeekoFormErrorPredicate = bool Function();

/// Caller-owned form field metadata used by
/// [SeekoFocusControllerExtension.ensureFirstFormErrorVisible].
@immutable
final class SeekoFormFocusTarget {
  const SeekoFormFocusTarget({
    required this.focusNode,
    required this.hasError,
    this.fallbackTarget,
  });

  final FocusNode focusNode;
  final SeekoFormErrorPredicate hasError;
  final ScrollTarget? fallbackTarget;
}

/// Focus and form reveal helpers that preserve caller ownership of focus nodes.
extension SeekoFocusControllerExtension on SeekoController {
  /// Reveals [focusNode] after focus and keyboard-driven viewport changes have
  /// settled for [stableFrames] consecutive frames.
  ///
  /// No [SeekoTag] is required for an attached focus node. For a lazily built
  /// field, provide [fallbackTarget] so its section can be materialized before
  /// the node is focused and revealed.
  Future<ScrollResult> ensureFocusVisible(
    FocusNode focusNode, {
    bool requestFocus = false,
    ScrollTarget? fallbackTarget,
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollMotion? motion,
    ScrollCommandOptions options = const ScrollCommandOptions(),
    int stableFrames = 2,
    int maxSettleFrames = 8,
  }) async {
    if (stableFrames <= 0) {
      throw RangeError.value(stableFrames, 'stableFrames', 'must be positive');
    }
    if (maxSettleFrames < stableFrames) {
      throw RangeError.value(
        maxSettleFrames,
        'maxSettleFrames',
        'must be greater than or equal to stableFrames',
      );
    }
    if (focusNode.context == null && fallbackTarget != null) {
      final ScrollResult materialized = await _moveFocusTarget(
        fallbackTarget,
        placement: placement,
        motion: motion,
        options: options,
      );
      if (!materialized.isSuccess) {
        return materialized;
      }
    }
    if (requestFocus && !focusNode.hasPrimaryFocus) {
      focusNode.requestFocus();
    }
    await _waitForStableFocusContext(
      focusNode,
      stableFrames: stableFrames,
      maxSettleFrames: maxSettleFrames,
    );
    final BuildContext? focusContext = focusNode.context;
    if (focusContext == null || !focusContext.mounted) {
      throw StateError('The focus node detached before it could be revealed.');
    }
    final BuildContext context = focusContext
            .findAncestorStateOfType<FormFieldState<dynamic>>()
            ?.context ??
        focusContext;
    return _moveFocusTarget(
      ScrollTarget.mounted(context),
      placement: placement,
      motion: motion,
      options: options,
    );
  }

  /// Reveals the first target whose [SeekoFormFocusTarget.hasError] returns
  /// true, or returns `null` when the submitted form has no invalid target.
  Future<ScrollResult?> ensureFirstFormErrorVisible(
    Iterable<SeekoFormFocusTarget> targets, {
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollMotion? motion,
    ScrollCommandOptions options = const ScrollCommandOptions(),
    int stableFrames = 2,
    int maxSettleFrames = 8,
  }) async {
    for (final SeekoFormFocusTarget target in targets) {
      if (!target.hasError()) {
        continue;
      }
      return ensureFocusVisible(
        target.focusNode,
        requestFocus: true,
        fallbackTarget: target.fallbackTarget,
        placement: placement,
        motion: motion,
        options: options,
        stableFrames: stableFrames,
        maxSettleFrames: maxSettleFrames,
      );
    }
    return null;
  }

  Future<ScrollResult> _moveFocusTarget(
    ScrollTarget target, {
    required ScrollPlacement placement,
    required ScrollMotion? motion,
    required ScrollCommandOptions options,
  }) {
    if (motion == null || motion.kind == ScrollMotionKind.instant) {
      return jumpToTarget(target, placement: placement, options: options);
    }
    return animateToTarget(
      target,
      placement: placement,
      motion: motion,
      options: options,
    );
  }

  Future<void> _waitForStableFocusContext(
    FocusNode focusNode, {
    required int stableFrames,
    required int maxSettleFrames,
  }) async {
    _FocusViewportSignature? previous;
    var stableCount = 0;
    for (var frame = 0; frame < maxSettleFrames; frame += 1) {
      await SchedulerBinding.instance.endOfFrame;
      final BuildContext? context = focusNode.context;
      if (context == null || !hasClients || !position.hasContentDimensions) {
        stableCount = 0;
        previous = null;
        continue;
      }
      final ScrollViewportGeometry viewport = ScrollViewportGeometry(
        viewportExtent: position.viewportDimension,
        axis: position.axis,
        axisDirection: position.axisDirection,
      );
      final VisibleRegion region = obstructionResolver?.call(viewport) ??
          VisibleRegion.fromIntervals(<LogicalInterval>[
            LogicalInterval(0, viewport.viewportExtent),
          ]);
      final _FocusViewportSignature current = _FocusViewportSignature(
        viewportExtent: viewport.viewportExtent,
        pixels: position.pixels,
        intervals: region.intervals,
      );
      if (current == previous) {
        stableCount += 1;
      } else {
        previous = current;
        stableCount = 1;
      }
      if (stableCount >= stableFrames) {
        return;
      }
    }
    throw StateError(
      'The focus node did not obtain an attached context and a stable '
      'viewport within $maxSettleFrames frames. Provide a fallbackTarget for '
      'a lazily built field or increase maxSettleFrames.',
    );
  }
}

@immutable
final class _FocusViewportSignature {
  _FocusViewportSignature({
    required this.viewportExtent,
    required this.pixels,
    required List<LogicalInterval> intervals,
  }) : intervals = List<LogicalInterval>.of(intervals, growable: false);

  final double viewportExtent;
  final double pixels;
  final List<LogicalInterval> intervals;

  @override
  bool operator ==(Object other) =>
      other is _FocusViewportSignature &&
      other.viewportExtent == viewportExtent &&
      other.pixels == pixels &&
      listEquals(other.intervals, intervals);

  @override
  int get hashCode =>
      Object.hash(viewportExtent, pixels, Object.hashAll(intervals));
}
