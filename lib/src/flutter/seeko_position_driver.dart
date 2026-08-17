// The public diagnostics constructors intentionally keep a same-name
// parameter for source compatibility with the published value API.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/capability.dart';
import '../core/command_model.dart';
import '../core/driver.dart';
import '../core/logical_geometry.dart';
import '../core/motion.dart';
import '../core/scroll_placement.dart';
import '../core/scroll_target.dart';
import 'seeko_timeline.dart';

typedef ScrollPositionCommit = bool Function(VoidCallback callback);
typedef MountedTargetLookup = FutureOr<BuildContext?> Function(
  ScrollTarget target,
);
typedef TargetRegistryProbe = bool Function(ScrollTarget target);
typedef PositionAnimator = Future<void> Function(
  double physicalPixels,
  Duration duration,
  Curve curve,
);
typedef PositionStopper = void Function(ScrollPosition position);
typedef PositionVisibleRegionResolver = VisibleRegion Function(
  ScrollPosition position,
);
typedef IndexedTargetResolver = FutureOr<SeekoIndexedTargetResolution?>
    Function(ScrollTarget target);

Map<String, Object?> _resolverDiagnostics(
  String resolverKind, {
  Object? error,
  StackTrace? stackTrace,
  String? reason,
}) {
  return <String, Object?>{
    'resolverKind': resolverKind,
    if (reason != null) 'reason': reason,
    if (error != null) ...<String, Object?>{
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    },
  };
}

abstract interface class SeekoIndexedMotionCoordinator {
  void beginWindowRebase({
    required double startPhysicalPixels,
    required double targetPhysicalPixels,
    required double viewportExtent,
  });

  void endWindowRebase();
}

final class SeekoIndexedTargetResolution {
  const SeekoIndexedTargetResolution.resolved({
    required this.targetInterval,
    required this.dataRevision,
    this.diagnostics,
  }) : status = ScrollResolutionStatus.resolved;

  const SeekoIndexedTargetResolution.targetNotLoaded()
      : status = ScrollResolutionStatus.targetNotLoaded,
        targetInterval = null,
        dataRevision = null,
        diagnostics = null;

  const SeekoIndexedTargetResolution.targetDeleted()
      : status = ScrollResolutionStatus.targetDeleted,
        targetInterval = null,
        dataRevision = null,
        diagnostics = null;

  const SeekoIndexedTargetResolution.targetOutOfRange()
      : status = ScrollResolutionStatus.targetOutOfRange,
        targetInterval = null,
        dataRevision = null,
        diagnostics = null;

  const SeekoIndexedTargetResolution.resolverRejected({
    Map<String, Object?>? diagnostics,
  })  : status = ScrollResolutionStatus.resolverRejected,
        targetInterval = null,
        dataRevision = null,
        diagnostics = diagnostics;

  const SeekoIndexedTargetResolution.unsupported({
    Map<String, Object?>? diagnostics,
  })  : status = ScrollResolutionStatus.unsupported,
        targetInterval = null,
        dataRevision = null,
        diagnostics = diagnostics;

  final ScrollResolutionStatus status;
  final LogicalInterval? targetInterval;
  final int? dataRevision;
  final Map<String, Object?>? diagnostics;
}

/// The L1/L2 driver for one captured Flutter [ScrollPosition].
///
/// It owns target resolution and physical position writes. Command ordering,
/// deadlines, result identity, and conflict policies remain controller-level
/// concerns shared by every future driver.
final class SeekoPositionDriver implements ScrollDriver {
  SeekoPositionDriver({
    required this.position,
    required this.capabilities,
    required this.resolutionMode,
    required this.placement,
    required this.boundaryPolicy,
    required this.cancellationToken,
    required this.commit,
    required this.isCurrentPosition,
    required this.mountedContextFor,
    required this.hasRegistryFor,
    required this.frameInterval,
    required this.reducedMotion,
    this.visibleRegionResolver,
    this.indexedTargetResolver,
    this.customTargetResolver,
    this.indexedMotionCoordinator,
    PositionAnimator? positionAnimator,
    PositionStopper? positionStopper,
  })  : _positionAnimator = positionAnimator,
        _positionStopper = positionStopper;

  final ScrollPosition position;

  @override
  final ScrollCapabilities capabilities;

  final ScrollResolutionMode resolutionMode;
  final ScrollPlacement placement;
  final ScrollBoundaryPolicy boundaryPolicy;
  final ScrollCancellationToken cancellationToken;
  final ScrollPositionCommit commit;
  final bool Function() isCurrentPosition;
  final MountedTargetLookup mountedContextFor;
  final TargetRegistryProbe hasRegistryFor;
  final Duration frameInterval;
  final bool reducedMotion;
  final PositionVisibleRegionResolver? visibleRegionResolver;
  final IndexedTargetResolver? indexedTargetResolver;
  final ScrollCustomTargetResolver? customTargetResolver;
  final SeekoIndexedMotionCoordinator? indexedMotionCoordinator;
  final PositionAnimator? _positionAnimator;
  final PositionStopper? _positionStopper;

  LogicalAxisGeometry get _geometry => LogicalAxisGeometry(
        axisDirection: position.axisDirection,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
      );

  double get logicalPixels => _geometry.physicalToLogical(position.pixels);

  @override
  Future<ScrollResolution> resolve(ScrollTarget target) async {
    final SeekoTimelineTask? timeline = kReleaseMode
        ? null
        : SeekoTimeline.start(
            'Seeko.resolve',
            arguments: <String, Object?>{
              'target': target.runtimeType.toString(),
              'axis': position.axis.name,
            },
          );
    try {
      return await _resolve(target);
    } finally {
      timeline?.finish();
    }
  }

  Future<ScrollResolution> _resolve(ScrollTarget target) async {
    if (!_isUsable) {
      return const ScrollResolution.targetDeleted();
    }
    final BuildContext? mounted = await mountedContextFor(target);
    if (!_isUsable) {
      return const ScrollResolution.targetDeleted();
    }
    if (mounted != null) {
      if (!mounted.mounted) {
        return const ScrollResolution.targetDeleted();
      }
      return _resolveMounted(target, mounted);
    }
    if (target is CustomScrollTarget) {
      final ScrollCustomTargetResolver? resolver = customTargetResolver;
      if (resolver == null) {
        return const ScrollResolution.unsupported();
      }
      late final ScrollCustomTargetResolution custom;
      try {
        custom = await resolver(target);
      } on Object catch (error, stackTrace) {
        return ScrollResolution.resolverRejected(
          diagnostics: _resolverDiagnostics(
            'customTarget',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
      if (!_isUsable) {
        return const ScrollResolution.targetDeleted();
      }
      return _resolveCustom(target, custom);
    }
    final SeekoIndexedTargetResolution? indexed;
    try {
      indexed = await indexedTargetResolver?.call(target);
    } on Object catch (error, stackTrace) {
      return ScrollResolution.resolverRejected(
        diagnostics: _resolverDiagnostics(
          'indexedTarget',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!_isUsable) {
      return const ScrollResolution.targetDeleted();
    }
    if (indexed != null) {
      return _resolveIndexed(target, indexed);
    }
    if (target is KeyScrollTarget || target is IndexScrollTarget) {
      return hasRegistryFor(target)
          ? const ScrollResolution.targetNotLoaded()
          : const ScrollResolution.unsupported();
    }
    return _resolveNumeric(target);
  }

  @override
  ScrollMotionPlan planMotion(
    ScrollResolution resolution,
    ScrollMotion motion,
  ) {
    if (kReleaseMode) {
      return _planMotion(resolution, motion);
    }
    return SeekoTimeline.sync(
      'Seeko.plan',
      () => _planMotion(resolution, motion),
      arguments: <String, Object?>{
        'motion': motion.kind.name,
        'resolution': resolution.mode.name,
      },
    );
  }

  ScrollMotionPlan _planMotion(
    ScrollResolution resolution,
    ScrollMotion motion,
  ) {
    if (!resolution.isResolved) {
      throw StateError('Cannot plan motion for an unresolved target.');
    }
    return const AdaptiveMotionPlanner().plan(
      distance: resolution.logicalPixels! - logicalPixels,
      viewportExtent: position.viewportDimension,
      frameInterval: frameInterval,
      motion: motion,
      reducedMotion: reducedMotion,
    );
  }

  @override
  Future<ScrollDriverResult> jump(ScrollResolution resolution) async {
    if (!_isUsable) {
      return _terminalResult(_cancelledOutcome);
    }
    if (!resolution.isResolved) {
      return _terminalResult(_outcomeForResolution(resolution.status));
    }
    final double physical = _geometry.logicalToPhysical(
      resolution.logicalPixels!,
    );
    if (!commit(() => position.jumpTo(physical))) {
      return _terminalResult(_cancelledOutcome);
    }
    if (boundaryPolicy == ScrollBoundaryPolicy.allowPhysicsOverscroll) {
      return _waitForPhysicsSettle(resolution);
    }
    return _resultFor(resolution);
  }

  @override
  Future<ScrollDriverResult> animate(
    ScrollResolution resolution,
    ScrollMotionPlan plan,
  ) async {
    if (!_isUsable) {
      return _terminalResult(_cancelledOutcome);
    }
    if (!resolution.isResolved) {
      return _terminalResult(_outcomeForResolution(resolution.status));
    }
    final double physical = _geometry.logicalToPhysical(
      resolution.logicalPixels!,
    );
    var usedCompletionFallback = false;
    if (plan.duration == Duration.zero) {
      if (!commit(() => position.jumpTo(physical))) {
        return _terminalResult(_cancelledOutcome);
      }
    } else {
      final SeekoIndexedMotionCoordinator? windowRebase =
          plan.requiresWindowRebase ? indexedMotionCoordinator : null;
      windowRebase?.beginWindowRebase(
        startPhysicalPixels: position.pixels,
        targetPhysicalPixels: physical,
        viewportExtent: position.viewportDimension,
      );
      final Completer<_PositionAnimationCompletion> cancelled =
          Completer<_PositionAnimationCompletion>();
      void stopActivity() {
        if (!cancelled.isCompleted) {
          cancelled.complete(_PositionAnimationCompletion.cancelled);
        }
        if (cancellationToken.reason == ScrollStopReason.userInteraction) {
          return;
        }
        if (position.context.notificationContext != null) {
          final PositionStopper? positionStopper = _positionStopper;
          if (positionStopper == null) {
            position.jumpTo(position.pixels);
          } else {
            positionStopper(position);
          }
        }
      }

      cancellationToken.addListener(stopActivity);
      try {
        if (cancellationToken.isCancelled) {
          return _terminalResult(_cancelledOutcome);
        }
        Future<void>? animation;
        if (!commit(() {
          animation = _positionAnimator?.call(
                physical,
                plan.duration,
                plan.curve,
              ) ??
              position.animateTo(
                physical,
                duration: plan.duration,
                curve: plan.curve,
              );
        })) {
          return _terminalResult(_cancelledOutcome);
        }
        final Future<_PositionAnimationCompletion> animationCompleted =
            animation!.then(
          (_) => _PositionAnimationCompletion.completed,
        );
        final Completer<_PositionAnimationCompletion> watchdog =
            Completer<_PositionAnimationCompletion>();
        final Duration twoFrames = Duration(
          microseconds: frameInterval.inMicroseconds * 2,
        );
        const Duration minimumCompositorGrace = Duration(milliseconds: 50);
        final Duration watchdogDelay = plan.duration +
            (twoFrames > minimumCompositorGrace
                ? twoFrames
                : minimumCompositorGrace);
        final Timer watchdogTimer = Timer(watchdogDelay, () {
          watchdog.complete(_PositionAnimationCompletion.watchdog);
        });
        try {
          _PositionAnimationCompletion completion =
              await Future.any<_PositionAnimationCompletion>(
            <Future<_PositionAnimationCompletion>>[
              animationCompleted,
              cancelled.future,
              watchdog.future,
            ],
          );
          if (completion == _PositionAnimationCompletion.watchdog) {
            final double arrivalError =
                (logicalPixels - resolution.logicalPixels!).abs();
            final bool preservePhysicsSettle =
                boundaryPolicy == ScrollBoundaryPolicy.allowPhysicsOverscroll &&
                    position.isScrollingNotifier.value &&
                    arrivalError > 0.5;
            if (preservePhysicsSettle) {
              completion = await Future.any<_PositionAnimationCompletion>(
                <Future<_PositionAnimationCompletion>>[
                  animationCompleted,
                  cancelled.future,
                ],
              );
            } else {
              usedCompletionFallback = true;
              if (!commit(() {
                final double currentPhysical = _geometry.logicalToPhysical(
                  resolution.logicalPixels!,
                );
                position.jumpTo(
                  currentPhysical
                      .clamp(
                        position.minScrollExtent,
                        position.maxScrollExtent,
                      )
                      .toDouble(),
                );
              })) {
                return _terminalResult(_cancelledOutcome);
              }
            }
          }
          if (completion == _PositionAnimationCompletion.cancelled) {
            return _terminalResult(_cancelledOutcome);
          }
        } finally {
          watchdogTimer.cancel();
        }
      } finally {
        cancellationToken.removeListener(stopActivity);
        windowRebase?.endWindowRebase();
      }
    }
    if (!_isUsable) {
      return _terminalResult(_cancelledOutcome);
    }
    if (boundaryPolicy == ScrollBoundaryPolicy.allowPhysicsOverscroll) {
      final ScrollDriverResult settled = await _waitForPhysicsSettle(
        resolution,
      );
      return usedCompletionFallback
          ? settled.copyWith(
              diagnostics: const <String, Object?>{
                'animationCompletionFallback': true,
              },
            )
          : settled;
    }
    return _resultFor(
      resolution,
      diagnostics: usedCompletionFallback
          ? const <String, Object?>{'animationCompletionFallback': true}
          : null,
    );
  }

  @override
  Future<ScrollDriverResult> stabilize(
    ScrollTarget target,
    ScrollResolution initialResolution,
    ScrollDriverResult initialResult, {
    required ScrollExecutionPolicy executionPolicy,
    ScrollMotion? correctionMotion,
  }) async {
    if (!initialResolution.isResolved || !initialResult.isSuccess) {
      return initialResult;
    }
    var resolution = initialResolution;
    var result = initialResult;
    var stableSamples = 0;
    var replans = initialResult.replanCount;
    var corrections = initialResult.correctionCount;
    var sample = _layoutSample(resolution);

    while (stableSamples < executionPolicy.settleSamples) {
      if (!await _waitForLayoutFrame()) {
        return _terminalResult(_cancelledOutcome);
      }
      final ScrollResolution nextResolution =
          SchedulerBinding.instance.framesEnabled
              ? await resolve(target)
              : resolution;
      if (!nextResolution.isResolved) {
        return _terminalResult(
          _outcomeForResolution(nextResolution.status),
          replanCount: replans,
          correctionCount: corrections,
        );
      }
      final _PositionLayoutSample nextSample = _layoutSample(nextResolution);
      final bool resolutionChanged = nextSample.resolutionChangedFrom(sample);
      if (resolutionChanged) {
        replans += 1;
        if (replans > executionPolicy.maxReplans) {
          return _layoutUnstableResult(
            resolution: nextResolution,
            replanCount: replans,
            correctionCount: corrections,
            exhausted: 'maxReplans',
          );
        }
        resolution = nextResolution;
        sample = nextSample;
        stableSamples = 0;
      }

      final bool stableClampedAchievement =
          result.outcome == ScrollOutcome.clamped && !resolutionChanged;
      final double expectedPixels = stableClampedAchievement
          ? result.finalLogicalPixels
          : nextResolution.logicalPixels!;
      final double error = (logicalPixels - expectedPixels).abs();
      if (error > executionPolicy.targetTolerance) {
        corrections += 1;
        if (corrections > executionPolicy.maxCorrections) {
          return _layoutUnstableResult(
            resolution: nextResolution,
            replanCount: replans,
            correctionCount: corrections,
            exhausted: 'maxCorrections',
          );
        }
        final ScrollDriverResult corrected = await _correct(
          nextResolution,
          correctionMotion,
          correction: corrections,
        );
        if (!corrected.isSuccess) {
          return corrected.copyWith(
            replanCount: replans,
            correctionCount: corrections,
            endRevision: nextResolution.dataRevision,
          );
        }
        result = corrected;
        resolution = nextResolution;
        sample = _layoutSample(nextResolution);
        stableSamples = 0;
        continue;
      }
      if (!stableClampedAchievement) {
        result = _resultFor(nextResolution);
      }
      stableSamples = resolutionChanged ? 1 : stableSamples + 1;
      resolution = nextResolution;
      sample = nextSample;
    }
    return result.copyWith(
      replanCount: replans,
      correctionCount: corrections,
      endRevision: resolution.dataRevision,
    );
  }

  Future<ScrollDriverResult> _correct(
    ScrollResolution resolution,
    ScrollMotion? motion, {
    required int correction,
  }) async {
    final SeekoTimelineTask? timeline = kReleaseMode
        ? null
        : SeekoTimeline.start(
            'Seeko.correct',
            arguments: <String, Object?>{
              'correction': correction,
              'motion': motion?.kind.name ?? ScrollMotionKind.instant.name,
            },
          );
    try {
      if (motion == null || motion.kind == ScrollMotionKind.instant) {
        return await jump(resolution);
      }
      final ScrollMotion boundedCorrection = _boundedCorrectionMotion(motion);
      return await animate(
        resolution,
        planMotion(resolution, boundedCorrection),
      );
    } finally {
      timeline?.finish();
    }
  }

  ScrollMotion _boundedCorrectionMotion(ScrollMotion requested) {
    const Duration maximumCorrectionDuration = Duration(milliseconds: 180);
    if (requested
        case ScrollMotion(
          kind: ScrollMotionKind.duration,
          duration: final Duration duration,
        ) when duration > maximumCorrectionDuration) {
      return const ScrollMotion.duration(
        duration: maximumCorrectionDuration,
        curve: Curves.easeOutCubic,
      );
    }
    return requested;
  }

  @override
  void stop(ScrollStopReason reason) {
    if (_isPositionCurrent && position.context.notificationContext != null) {
      final PositionStopper? positionStopper = _positionStopper;
      if (positionStopper == null) {
        position.jumpTo(position.pixels);
      } else {
        positionStopper(position);
      }
    }
  }

  ScrollResolution _resolveNumeric(ScrollTarget target) {
    late final double requested;
    if (target case OffsetScrollTarget(:final double pixels)) {
      requested = pixels;
    } else if (target case EdgeScrollTarget(:final ScrollEdge edge)) {
      requested = edge == ScrollEdge.leading ? 0 : _geometry.extent;
    } else if (target case ProgressScrollTarget(:final double value)) {
      requested = _geometry.extent * value;
    } else {
      return const ScrollResolution.unsupported();
    }
    return _resolveRequestedPixels(target, requested);
  }

  ScrollResolution _resolveMounted(
    ScrollTarget requestedTarget,
    BuildContext context,
  ) {
    final RenderObject? object = context.findRenderObject();
    if (object == null || !object.attached) {
      return const ScrollResolution.targetDeleted();
    }
    final RenderAbstractViewport? viewport =
        RenderAbstractViewport.maybeOf(object);
    if (viewport == null) {
      return const ScrollResolution.targetDeleted();
    }
    final ScrollableState? targetScrollable = Scrollable.maybeOf(
      context,
      axis: position.axis,
    );
    if (targetScrollable == null ||
        !identical(targetScrollable.position, position)) {
      return const ScrollResolution.resolverRejected();
    }
    final Rect rect = MatrixUtils.transformRect(
      object.getTransformTo(viewport),
      object.paintBounds,
    );
    final double targetExtent =
        position.axis == Axis.horizontal ? rect.width : rect.height;
    final double paintStart = switch (position.axisDirection) {
      AxisDirection.down => rect.top,
      AxisDirection.up => position.viewportDimension - rect.bottom,
      AxisDirection.right => rect.left,
      AxisDirection.left => position.viewportDimension - rect.right,
    };
    final double start = logicalPixels + paintStart;
    final LogicalInterval target = LogicalInterval(start, start + targetExtent);
    try {
      final VisibleRegion visible = visibleRegionResolver?.call(position) ??
          VisibleRegion.fromIntervals(<LogicalInterval>[
            LogicalInterval(0, position.viewportDimension),
          ]);
      if (!_validVisibleRegion(visible)) {
        return ScrollResolution.resolverRejected(
          diagnostics: _resolverDiagnostics(
            'obstruction',
            reason: 'invalidVisibleRegion',
          ),
        );
      }
      final ScrollPlacementResolution placementResolution =
          resolveScrollPlacement(
        placement: placement,
        target: target,
        visibleRegion: visible,
        currentPixels: logicalPixels,
      );
      return _resolveRequestedPixels(
        requestedTarget,
        placementResolution.pixels,
      );
    } on Object catch (error, stackTrace) {
      return ScrollResolution.resolverRejected(
        diagnostics: _resolverDiagnostics(
          'mountedPlacement',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  ScrollResolution _resolveIndexed(
    ScrollTarget requestedTarget,
    SeekoIndexedTargetResolution indexed,
  ) {
    switch (indexed.status) {
      case ScrollResolutionStatus.targetNotLoaded:
        return const ScrollResolution.targetNotLoaded();
      case ScrollResolutionStatus.targetDeleted:
        return const ScrollResolution.targetDeleted();
      case ScrollResolutionStatus.targetOutOfRange:
        return const ScrollResolution.targetOutOfRange();
      case ScrollResolutionStatus.resolverRejected:
        return ScrollResolution.resolverRejected(
          diagnostics: indexed.diagnostics,
        );
      case ScrollResolutionStatus.unsupported:
        return ScrollResolution.unsupported();
      case ScrollResolutionStatus.resolved:
        break;
    }
    try {
      final VisibleRegion visible = visibleRegionResolver?.call(position) ??
          VisibleRegion.fromIntervals(<LogicalInterval>[
            LogicalInterval(0, position.viewportDimension),
          ]);
      if (!_validVisibleRegion(visible)) {
        return ScrollResolution.resolverRejected(
          diagnostics: _resolverDiagnostics(
            'obstruction',
            reason: 'invalidVisibleRegion',
          ),
        );
      }
      final ScrollPlacementResolution placementResolution =
          resolveScrollPlacement(
        placement: placement,
        target: indexed.targetInterval!,
        visibleRegion: visible,
        currentPixels: logicalPixels,
      );
      return _resolveRequestedPixels(
        requestedTarget,
        placementResolution.pixels,
        mode: ScrollResolutionMode.exact,
        dataRevision: indexed.dataRevision,
        diagnostics: indexed.diagnostics,
      );
    } on Object catch (error, stackTrace) {
      return ScrollResolution.resolverRejected(
        diagnostics: _resolverDiagnostics(
          'indexedPlacement',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  ScrollResolution _resolveCustom(
    CustomScrollTarget requestedTarget,
    ScrollCustomTargetResolution custom,
  ) {
    switch (custom.status) {
      case ScrollResolutionStatus.targetNotLoaded:
        return const ScrollResolution.targetNotLoaded();
      case ScrollResolutionStatus.targetDeleted:
        return const ScrollResolution.targetDeleted();
      case ScrollResolutionStatus.targetOutOfRange:
        return const ScrollResolution.targetOutOfRange();
      case ScrollResolutionStatus.resolverRejected:
        return ScrollResolution.resolverRejected(
          diagnostics: custom.diagnostics,
        );
      case ScrollResolutionStatus.unsupported:
        return const ScrollResolution.unsupported();
      case ScrollResolutionStatus.resolved:
        break;
    }
    final LogicalInterval interval = custom.targetInterval!;
    if (!interval.start.isFinite ||
        !interval.end.isFinite ||
        interval.start < 0 ||
        interval.end < interval.start) {
      return ScrollResolution.resolverRejected(
        diagnostics: _resolverDiagnostics(
          'customTarget',
          reason: 'invalidTargetInterval',
        ),
      );
    }
    try {
      final VisibleRegion visible = visibleRegionResolver?.call(position) ??
          VisibleRegion.fromIntervals(<LogicalInterval>[
            LogicalInterval(0, position.viewportDimension),
          ]);
      if (!_validVisibleRegion(visible)) {
        return ScrollResolution.resolverRejected(
          diagnostics: _resolverDiagnostics(
            'obstruction',
            reason: 'invalidVisibleRegion',
          ),
        );
      }
      final ScrollPlacementResolution placementResolution =
          resolveScrollPlacement(
        placement: placement,
        target: interval,
        visibleRegion: visible,
        currentPixels: logicalPixels,
      );
      return _resolveRequestedPixels(
        requestedTarget,
        placementResolution.pixels,
        mode: custom.mode,
        dataRevision: custom.dataRevision,
        diagnostics: custom.diagnostics,
      );
    } on Object catch (error, stackTrace) {
      return ScrollResolution.resolverRejected(
        diagnostics: _resolverDiagnostics(
          'customPlacement',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  bool _validVisibleRegion(VisibleRegion region) {
    if (region.intervals.isEmpty) {
      return false;
    }
    for (final LogicalInterval interval in region.intervals) {
      if (!interval.start.isFinite ||
          !interval.end.isFinite ||
          interval.start < 0 ||
          interval.end > position.viewportDimension) {
        return false;
      }
    }
    return true;
  }

  ScrollResolution _resolveRequestedPixels(
    ScrollTarget target,
    double requested, {
    ScrollResolutionMode? mode,
    int? dataRevision,
    Map<String, Object?>? diagnostics,
  }) {
    final ScrollResolutionMode effectiveMode = mode ?? resolutionMode;
    if (boundaryPolicy == ScrollBoundaryPolicy.reject &&
        (requested < 0 || requested > _geometry.extent)) {
      return const ScrollResolution.targetOutOfRange();
    }
    if (boundaryPolicy == ScrollBoundaryPolicy.allowPhysicsOverscroll) {
      final double physical = _geometry.logicalToPhysical(requested);
      if (position.physics.applyBoundaryConditions(position, physical) != 0) {
        return const ScrollResolution.unsupported();
      }
      return ScrollResolution.resolved(
        target: target,
        logicalPixels: requested,
        mode: effectiveMode,
        dataRevision: dataRevision,
        diagnostics: diagnostics,
      );
    }
    final double achieved = requested.clamp(0, _geometry.extent);
    return ScrollResolution.resolved(
      target: target,
      logicalPixels: achieved,
      mode: effectiveMode,
      dataRevision: dataRevision,
      clamped: achieved != requested,
      clampReason: achieved != requested
          ? 'Target is outside the finite scroll extent.'
          : null,
      diagnostics: diagnostics,
    );
  }

  Future<ScrollDriverResult> _waitForPhysicsSettle(
    ScrollResolution resolution,
  ) async {
    while (position.isScrollingNotifier.value) {
      final Completer<void> changed = Completer<void>();
      void listener() {
        if (!changed.isCompleted) {
          changed.complete();
        }
      }

      position.isScrollingNotifier.addListener(listener);
      cancellationToken.addListener(listener);
      try {
        if (!position.isScrollingNotifier.value ||
            cancellationToken.isCancelled) {
          listener();
        }
        await changed.future;
      } finally {
        position.isScrollingNotifier.removeListener(listener);
        cancellationToken.removeListener(listener);
      }
      if (!_isUsable) {
        return _terminalResult(_cancelledOutcome);
      }
    }
    final double error = (logicalPixels - resolution.logicalPixels!).abs();
    if (error <= 0.5) {
      return _resultFor(resolution);
    }
    return ScrollDriverResult(
      finalLogicalPixels: logicalPixels,
      finalError: error,
      outcome: ScrollOutcome.clamped,
      clamped: true,
      clampReason: 'Scroll physics settled inside the finite content extent.',
    );
  }

  ScrollDriverResult _resultFor(
    ScrollResolution resolution, {
    Map<String, Object?>? diagnostics,
  }) {
    final double actual = logicalPixels;
    return ScrollDriverResult(
      finalLogicalPixels: actual,
      finalError: (actual - resolution.logicalPixels!).abs(),
      outcome:
          resolution.clamped ? ScrollOutcome.clamped : ScrollOutcome.completed,
      clamped: resolution.clamped,
      clampReason: resolution.clampReason,
      diagnostics: diagnostics,
    );
  }

  ScrollDriverResult _terminalResult(
    ScrollOutcome outcome, {
    int correctionCount = 0,
    int replanCount = 0,
  }) {
    return ScrollDriverResult(
      finalLogicalPixels: logicalPixels,
      finalError: 0,
      outcome: outcome,
      correctionCount: correctionCount,
      replanCount: replanCount,
    );
  }

  Future<bool> _waitForLayoutFrame() async {
    if (!_isUsable) {
      return false;
    }
    final SchedulerBinding binding = SchedulerBinding.instance;
    final Completer<void> cancelled = Completer<void>();
    void cancelListener() {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
    }

    cancellationToken.addListener(cancelListener);
    try {
      if (!_isUsable) {
        return false;
      }
      if (!binding.framesEnabled) {
        final Completer<void> stableInterval = Completer<void>();
        final Timer timer = Timer(frameInterval, stableInterval.complete);
        try {
          await Future.any<void>(<Future<void>>[
            stableInterval.future,
            cancelled.future,
          ]);
          return _isUsable;
        } finally {
          timer.cancel();
        }
      }
      if (binding.schedulerPhase == SchedulerPhase.idle &&
          !binding.hasScheduledFrame) {
        binding.scheduleFrame();
      }
      final Future<void> frame = binding.endOfFrame;
      await Future.any<void>(<Future<void>>[frame, cancelled.future]);
      return _isUsable;
    } finally {
      cancellationToken.removeListener(cancelListener);
    }
  }

  _PositionLayoutSample _layoutSample(ScrollResolution resolution) {
    return _PositionLayoutSample(
      logicalPixels: resolution.logicalPixels!,
      viewportDimension: position.viewportDimension,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
      dataRevision: resolution.dataRevision,
    );
  }

  ScrollDriverResult _layoutUnstableResult({
    required ScrollResolution resolution,
    required int replanCount,
    required int correctionCount,
    required String exhausted,
  }) {
    return ScrollDriverResult(
      finalLogicalPixels: logicalPixels,
      finalError: (logicalPixels - resolution.logicalPixels!).abs(),
      outcome: ScrollOutcome.layoutUnstable,
      replanCount: replanCount,
      correctionCount: correctionCount,
      endRevision: resolution.dataRevision,
      diagnostics: <String, Object?>{'executionPolicy': exhausted},
    );
  }

  bool get _isPositionCurrent => isCurrentPosition();
  bool get _isUsable => _isPositionCurrent && !cancellationToken.isCancelled;

  ScrollOutcome get _cancelledOutcome => switch (cancellationToken.reason) {
        ScrollStopReason.userInteraction => ScrollOutcome.interruptedByUser,
        ScrollStopReason.superseded => ScrollOutcome.superseded,
        ScrollStopReason.timedOut => ScrollOutcome.timedOut,
        ScrollStopReason.detached => ScrollOutcome.detached,
        _ when !_isPositionCurrent => ScrollOutcome.detached,
        _ => ScrollOutcome.cancelled,
      };
}

extension on ScrollDriverResult {
  ScrollDriverResult copyWith({
    int? correctionCount,
    int? replanCount,
    int? endRevision,
    Map<String, Object?>? diagnostics,
  }) {
    return ScrollDriverResult(
      finalLogicalPixels: finalLogicalPixels,
      finalError: finalError,
      outcome: outcome,
      clamped: clamped,
      clampReason: clampReason,
      correctionCount: correctionCount ?? this.correctionCount,
      replanCount: replanCount ?? this.replanCount,
      endRevision: endRevision ?? this.endRevision,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }
}

enum _PositionAnimationCompletion { completed, watchdog, cancelled }

final class _PositionLayoutSample {
  const _PositionLayoutSample({
    required this.logicalPixels,
    required this.viewportDimension,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.dataRevision,
  });

  final double logicalPixels;
  final double viewportDimension;
  final double minScrollExtent;
  final double maxScrollExtent;
  final int? dataRevision;

  bool resolutionChangedFrom(_PositionLayoutSample other) {
    return logicalPixels != other.logicalPixels ||
        viewportDimension != other.viewportDimension ||
        minScrollExtent != other.minScrollExtent ||
        maxScrollExtent != other.maxScrollExtent ||
        dataRevision != other.dataRevision;
  }
}

ScrollOutcome _outcomeForResolution(ScrollResolutionStatus status) {
  return switch (status) {
    ScrollResolutionStatus.resolved => ScrollOutcome.completed,
    ScrollResolutionStatus.targetNotLoaded => ScrollOutcome.targetNotLoaded,
    ScrollResolutionStatus.targetDeleted => ScrollOutcome.targetDeleted,
    ScrollResolutionStatus.targetOutOfRange => ScrollOutcome.targetOutOfRange,
    ScrollResolutionStatus.resolverRejected => ScrollOutcome.resolverRejected,
    ScrollResolutionStatus.unsupported => ScrollOutcome.unsupported,
  };
}
