import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/capability.dart';
import '../core/command_model.dart';
import '../core/driver.dart';
import '../core/logical_geometry.dart';
import '../core/motion.dart';
import '../core/scroll_placement.dart';
import '../core/scroll_target.dart';
import 'seeko_position_driver.dart';

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

/// Drives Flutter's coordinated outer and inner positions as one logical axis.
final class SeekoNestedPositionDriver implements ScrollDriver {
  SeekoNestedPositionDriver({
    required this.outerPosition,
    required this.innerPosition,
    required this.bindingValid,
    required this.capabilities,
    required this.resolutionMode,
    required this.placement,
    required this.boundaryPolicy,
    required this.cancellationToken,
    required this.commit,
    required this.isCurrentPair,
    required this.mountedContextFor,
    required this.hasRegistryFor,
    required this.frameInterval,
    required this.reducedMotion,
    this.visibleRegionResolver,
    this.indexedTargetResolver,
    this.customTargetResolver,
    this.indexedMotionCoordinator,
  });

  final ScrollPosition outerPosition;
  final ScrollPosition? innerPosition;
  final bool bindingValid;

  @override
  final ScrollCapabilities capabilities;

  final ScrollResolutionMode resolutionMode;
  final ScrollPlacement placement;
  final ScrollBoundaryPolicy boundaryPolicy;
  final ScrollCancellationToken cancellationToken;
  final ScrollPositionCommit commit;
  final bool Function(ScrollPosition outer, ScrollPosition inner) isCurrentPair;
  final MountedTargetLookup mountedContextFor;
  final TargetRegistryProbe hasRegistryFor;
  final Duration frameInterval;
  final bool reducedMotion;
  final PositionVisibleRegionResolver? visibleRegionResolver;
  final IndexedTargetResolver? indexedTargetResolver;
  final ScrollCustomTargetResolver? customTargetResolver;
  final SeekoIndexedMotionCoordinator? indexedMotionCoordinator;

  _NestedPositionOwner? _resolvedOwner;
  ScrollResolution? _resolvedLocal;

  ScrollPosition get _inner => innerPosition!;

  LogicalAxisGeometry get _outerGeometry => LogicalAxisGeometry(
        axisDirection: outerPosition.axisDirection,
        minScrollExtent: outerPosition.minScrollExtent,
        maxScrollExtent: outerPosition.maxScrollExtent,
      );

  LogicalAxisGeometry get _innerGeometry => LogicalAxisGeometry(
        axisDirection: _inner.axisDirection,
        minScrollExtent: _inner.minScrollExtent,
        maxScrollExtent: _inner.maxScrollExtent,
      );

  double get _outerLogical =>
      _outerGeometry.physicalToLogical(outerPosition.pixels);
  double get _innerLogical => _innerGeometry.physicalToLogical(_inner.pixels);
  double get _logicalPixels => _outerLogical + _innerLogical;
  double get _extent => _outerLogical + _innerGeometry.extent;

  @override
  Future<ScrollResolution> resolve(ScrollTarget target) async {
    if (!bindingValid || innerPosition == null) {
      return ScrollResolution.resolverRejected(
        diagnostics: _resolverDiagnostics(
          'nestedBinding',
          reason: innerPosition == null
              ? 'innerPositionUnavailable'
              : 'bindingInvalid',
        ),
      );
    }
    if (!_isUsable) {
      return const ScrollResolution.targetDeleted();
    }
    if (target is OffsetScrollTarget ||
        target is EdgeScrollTarget ||
        target is ProgressScrollTarget) {
      return _resolveNumeric(target);
    }

    final BuildContext? mounted = await mountedContextFor(target);
    if (!_isUsable) {
      return const ScrollResolution.targetDeleted();
    }
    if (mounted != null) {
      if (!mounted.mounted) {
        return const ScrollResolution.targetDeleted();
      }
      final ScrollableState? scrollable = Scrollable.maybeOf(
        mounted,
        axis: outerPosition.axis,
      );
      if (scrollable == null) {
        return ScrollResolution.resolverRejected(
          diagnostics: _resolverDiagnostics(
            'nestedMountedTarget',
            reason: 'scrollableUnavailable',
          ),
        );
      }
      final _NestedPositionOwner? owner =
          identical(scrollable.position, outerPosition)
              ? _NestedPositionOwner.outer
              : identical(scrollable.position, _inner)
                  ? _NestedPositionOwner.inner
                  : null;
      if (owner == null) {
        return ScrollResolution.resolverRejected(
          diagnostics: _resolverDiagnostics(
            'nestedMountedTarget',
            reason: 'positionNotOwnedByBinding',
          ),
        );
      }
      final ScrollResolution local = await _delegateFor(
        owner,
        mountedContextFor: (_) => mounted,
      ).resolve(target);
      return _capture(local, owner);
    }

    if (target is CustomScrollTarget) {
      final ScrollResolution local = await _delegateFor(
        _NestedPositionOwner.inner,
        mountedContextFor: (_) => null,
      ).resolve(target);
      return _capture(local, _NestedPositionOwner.inner);
    }

    final SeekoIndexedTargetResolution? indexed;
    try {
      indexed = await indexedTargetResolver?.call(target);
    } on Object catch (error, stackTrace) {
      return ScrollResolution.resolverRejected(
        diagnostics: _resolverDiagnostics(
          'nestedIndexedTarget',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!_isUsable) {
      return const ScrollResolution.targetDeleted();
    }
    if (indexed != null) {
      final ScrollResolution local = await _delegateFor(
        _NestedPositionOwner.inner,
        mountedContextFor: (_) => null,
        indexedTargetResolver: (_) => indexed,
      ).resolve(target);
      return _capture(local, _NestedPositionOwner.inner);
    }
    if (target is KeyScrollTarget || target is IndexScrollTarget) {
      return hasRegistryFor(target)
          ? const ScrollResolution.targetNotLoaded()
          : const ScrollResolution.unsupported();
    }
    return const ScrollResolution.unsupported();
  }

  @override
  ScrollMotionPlan planMotion(
    ScrollResolution resolution,
    ScrollMotion motion,
  ) {
    if (!resolution.isResolved) {
      throw StateError('Cannot plan motion for an unresolved target.');
    }
    return const AdaptiveMotionPlanner().plan(
      distance: resolution.logicalPixels! - _logicalPixels,
      viewportExtent: outerPosition.viewportDimension,
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
    final _NestedPositionOwner? owner = _resolvedOwner;
    final ScrollResolution? local = _resolvedLocal;
    if (owner == null || local == null) {
      return _terminalResult(ScrollOutcome.resolverRejected);
    }
    final ScrollDriverResult result = await _delegateFor(owner).jump(local);
    return _wrapResult(resolution, result);
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
    final _NestedPositionOwner? owner = _resolvedOwner;
    final ScrollResolution? local = _resolvedLocal;
    if (owner == null || local == null) {
      return _terminalResult(ScrollOutcome.resolverRejected);
    }
    final ScrollDriverResult result =
        await _delegateFor(owner).animate(local, plan);
    return _wrapResult(resolution, result);
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
      final _NestedLayoutSample nextSample = _layoutSample(nextResolution);
      final bool resolutionChanged = nextSample.differsFrom(sample);
      if (resolutionChanged) {
        replans += 1;
        if (replans > executionPolicy.maxReplans) {
          return _layoutUnstableResult(
            nextResolution,
            replans,
            corrections,
            'maxReplans',
          );
        }
        resolution = nextResolution;
        sample = nextSample;
        stableSamples = 0;
      }

      final bool stableClamp =
          result.outcome == ScrollOutcome.clamped && !resolutionChanged;
      final double expected = stableClamp
          ? result.finalLogicalPixels
          : nextResolution.logicalPixels!;
      final double error = (_logicalPixels - expected).abs();
      if (error > executionPolicy.targetTolerance) {
        corrections += 1;
        if (corrections > executionPolicy.maxCorrections) {
          return _layoutUnstableResult(
            nextResolution,
            replans,
            corrections,
            'maxCorrections',
          );
        }
        final ScrollDriverResult corrected;
        if (correctionMotion == null ||
            correctionMotion.kind == ScrollMotionKind.instant) {
          corrected = await jump(nextResolution);
        } else {
          corrected = await animate(
            nextResolution,
            planMotion(nextResolution, _boundedCorrection(correctionMotion)),
          );
        }
        if (!corrected.isSuccess) {
          return _copyResult(
            corrected,
            replanCount: replans,
            correctionCount: corrections,
          );
        }
        result = corrected;
        resolution = nextResolution;
        sample = _layoutSample(nextResolution);
        stableSamples = 0;
        continue;
      }
      if (!stableClamp) {
        result = _resultFor(nextResolution);
      }
      stableSamples = resolutionChanged ? 1 : stableSamples + 1;
      resolution = nextResolution;
      sample = nextSample;
    }
    return _copyResult(
      result,
      replanCount: replans,
      correctionCount: corrections,
      endRevision: resolution.dataRevision,
    );
  }

  @override
  void stop(ScrollStopReason reason) {
    if (!_isUsable) {
      return;
    }
    _inner.jumpTo(_inner.pixels);
  }

  ScrollResolution _resolveNumeric(ScrollTarget target) {
    late final double requested;
    if (target case OffsetScrollTarget(:final double pixels)) {
      requested = pixels;
    } else if (target case EdgeScrollTarget(:final ScrollEdge edge)) {
      requested = edge == ScrollEdge.leading ? 0 : _extent;
    } else if (target case ProgressScrollTarget(:final double value)) {
      requested = _extent * value;
    } else {
      return const ScrollResolution.unsupported();
    }
    if (boundaryPolicy == ScrollBoundaryPolicy.allowPhysicsOverscroll) {
      return const ScrollResolution.unsupported();
    }
    if (boundaryPolicy == ScrollBoundaryPolicy.reject &&
        (requested < 0 || requested > _extent)) {
      return const ScrollResolution.targetOutOfRange();
    }
    final double achieved = requested.clamp(0, _extent).toDouble();
    final bool clamped = achieved != requested;
    final ScrollResolution composite = ScrollResolution.resolved(
      target: target,
      logicalPixels: achieved,
      mode: resolutionMode,
      clamped: clamped,
      clampReason:
          clamped ? 'Target is outside the finite composite extent.' : null,
    );
    final _NestedPositionOwner owner;
    final double localPixels;
    if ((achieved - _logicalPixels).abs() <= precisionErrorTolerance) {
      owner = _innerLogical > precisionErrorTolerance
          ? _NestedPositionOwner.inner
          : _NestedPositionOwner.outer;
      localPixels =
          owner == _NestedPositionOwner.inner ? _innerLogical : _outerLogical;
    } else if (achieved <= _outerGeometry.extent) {
      owner = _NestedPositionOwner.outer;
      localPixels = achieved;
    } else {
      owner = _NestedPositionOwner.inner;
      localPixels = achieved - _outerGeometry.extent;
    }
    _resolvedOwner = owner;
    _resolvedLocal = ScrollResolution.resolved(
      target: ScrollTarget.offset(localPixels),
      logicalPixels: localPixels,
      mode: resolutionMode,
      clamped: clamped,
      clampReason: composite.clampReason,
    );
    return composite;
  }

  ScrollResolution _capture(
    ScrollResolution local,
    _NestedPositionOwner owner,
  ) {
    if (!local.isResolved) {
      return local;
    }
    final double currentLocal =
        owner == _NestedPositionOwner.outer ? _outerLogical : _innerLogical;
    final double composite =
        (local.logicalPixels! - currentLocal).abs() <= precisionErrorTolerance
            ? _logicalPixels
            : owner == _NestedPositionOwner.outer
                ? local.logicalPixels!
                : _outerGeometry.extent + local.logicalPixels!;
    _resolvedOwner = owner;
    _resolvedLocal = local;
    return ScrollResolution.resolved(
      target: local.target!,
      logicalPixels: composite,
      mode: local.mode,
      dataRevision: local.dataRevision,
      clamped: local.clamped,
      clampReason: local.clampReason,
      diagnostics: local.diagnostics,
    );
  }

  SeekoPositionDriver _delegateFor(
    _NestedPositionOwner owner, {
    MountedTargetLookup? mountedContextFor,
    IndexedTargetResolver? indexedTargetResolver,
  }) {
    final ScrollPosition selected =
        owner == _NestedPositionOwner.outer ? outerPosition : _inner;
    return SeekoPositionDriver(
      position: selected,
      capabilities: capabilities,
      resolutionMode: resolutionMode,
      placement: placement,
      boundaryPolicy: boundaryPolicy,
      cancellationToken: cancellationToken,
      commit: commit,
      isCurrentPosition: () => _isUsable,
      mountedContextFor: mountedContextFor ?? this.mountedContextFor,
      hasRegistryFor: hasRegistryFor,
      frameInterval: frameInterval,
      reducedMotion: reducedMotion,
      visibleRegionResolver: visibleRegionResolver,
      indexedTargetResolver: indexedTargetResolver,
      customTargetResolver: customTargetResolver,
      indexedMotionCoordinator:
          owner == _NestedPositionOwner.inner ? indexedMotionCoordinator : null,
      positionStopper: (_) => _stopCoordinatedActivity(),
    );
  }

  void _stopCoordinatedActivity() {
    if (!_isUsable) {
      return;
    }
    if (_innerLogical <= precisionErrorTolerance) {
      outerPosition.jumpTo(outerPosition.pixels);
    } else {
      _inner.jumpTo(_inner.pixels);
    }
  }

  ScrollDriverResult _wrapResult(
    ScrollResolution resolution,
    ScrollDriverResult local,
  ) {
    if (!local.isSuccess) {
      return _copyResult(
        local,
        finalLogicalPixels: _logicalPixels,
      );
    }
    return ScrollDriverResult(
      finalLogicalPixels: _logicalPixels,
      finalError: (_logicalPixels - resolution.logicalPixels!).abs(),
      outcome: resolution.clamped ? ScrollOutcome.clamped : local.outcome,
      clamped: resolution.clamped || local.clamped,
      clampReason: resolution.clampReason ?? local.clampReason,
      correctionCount: local.correctionCount,
      replanCount: local.replanCount,
      endRevision: local.endRevision,
      diagnostics: local.diagnostics,
    );
  }

  ScrollDriverResult _resultFor(ScrollResolution resolution) {
    return ScrollDriverResult(
      finalLogicalPixels: _logicalPixels,
      finalError: (_logicalPixels - resolution.logicalPixels!).abs(),
      outcome:
          resolution.clamped ? ScrollOutcome.clamped : ScrollOutcome.completed,
      clamped: resolution.clamped,
      clampReason: resolution.clampReason,
      endRevision: resolution.dataRevision,
    );
  }

  ScrollDriverResult _terminalResult(
    ScrollOutcome outcome, {
    int correctionCount = 0,
    int replanCount = 0,
  }) {
    return ScrollDriverResult(
      finalLogicalPixels:
          bindingValid && innerPosition != null ? _logicalPixels : 0,
      finalError: 0,
      outcome: outcome,
      correctionCount: correctionCount,
      replanCount: replanCount,
    );
  }

  ScrollDriverResult _layoutUnstableResult(
    ScrollResolution resolution,
    int replans,
    int corrections,
    String exhausted,
  ) {
    return ScrollDriverResult(
      finalLogicalPixels: _logicalPixels,
      finalError: (_logicalPixels - resolution.logicalPixels!).abs(),
      outcome: ScrollOutcome.layoutUnstable,
      replanCount: replans,
      correctionCount: corrections,
      endRevision: resolution.dataRevision,
      diagnostics: <String, Object?>{'executionPolicy': exhausted},
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
      if (!binding.framesEnabled) {
        final Completer<void> interval = Completer<void>();
        final Timer timer = Timer(frameInterval, interval.complete);
        try {
          await Future.any<void>(<Future<void>>[
            interval.future,
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
      await Future.any<void>(<Future<void>>[
        binding.endOfFrame,
        cancelled.future,
      ]);
      return _isUsable;
    } finally {
      cancellationToken.removeListener(cancelListener);
    }
  }

  _NestedLayoutSample _layoutSample(ScrollResolution resolution) {
    return _NestedLayoutSample(
      logicalPixels: resolution.logicalPixels!,
      outerExtent: _outerGeometry.extent,
      innerExtent: _innerGeometry.extent,
      outerViewport: outerPosition.viewportDimension,
      innerViewport: _inner.viewportDimension,
      dataRevision: resolution.dataRevision,
    );
  }

  ScrollMotion _boundedCorrection(ScrollMotion requested) {
    const Duration maximum = Duration(milliseconds: 180);
    if (requested
        case ScrollMotion(
          kind: ScrollMotionKind.duration,
          duration: final Duration duration,
        ) when duration > maximum) {
      return const ScrollMotion.duration(
        duration: maximum,
        curve: Curves.easeOutCubic,
      );
    }
    return requested;
  }

  bool get _isUsable {
    final ScrollPosition? inner = innerPosition;
    return bindingValid &&
        inner != null &&
        isCurrentPair(outerPosition, inner) &&
        !cancellationToken.isCancelled;
  }

  ScrollOutcome get _cancelledOutcome => switch (cancellationToken.reason) {
        ScrollStopReason.userInteraction => ScrollOutcome.interruptedByUser,
        ScrollStopReason.superseded => ScrollOutcome.superseded,
        ScrollStopReason.timedOut => ScrollOutcome.timedOut,
        ScrollStopReason.detached => ScrollOutcome.detached,
        _ when !_isUsable => ScrollOutcome.detached,
        _ => ScrollOutcome.cancelled,
      };
}

enum _NestedPositionOwner { outer, inner }

final class _NestedLayoutSample {
  const _NestedLayoutSample({
    required this.logicalPixels,
    required this.outerExtent,
    required this.innerExtent,
    required this.outerViewport,
    required this.innerViewport,
    required this.dataRevision,
  });

  final double logicalPixels;
  final double outerExtent;
  final double innerExtent;
  final double outerViewport;
  final double innerViewport;
  final int? dataRevision;

  bool differsFrom(_NestedLayoutSample other) {
    return logicalPixels != other.logicalPixels ||
        outerExtent != other.outerExtent ||
        innerExtent != other.innerExtent ||
        outerViewport != other.outerViewport ||
        innerViewport != other.innerViewport ||
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

ScrollDriverResult _copyResult(
  ScrollDriverResult value, {
  double? finalLogicalPixels,
  int? correctionCount,
  int? replanCount,
  int? endRevision,
}) {
  return ScrollDriverResult(
    finalLogicalPixels: finalLogicalPixels ?? value.finalLogicalPixels,
    finalError: value.finalError,
    outcome: value.outcome,
    clamped: value.clamped,
    clampReason: value.clampReason,
    correctionCount: correctionCount ?? value.correctionCount,
    replanCount: replanCount ?? value.replanCount,
    endRevision: endRevision ?? value.endRevision,
    diagnostics: value.diagnostics,
  );
}
