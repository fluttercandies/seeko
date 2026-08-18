import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/anchor_policy.dart';
import '../core/capability.dart';
import '../core/command_model.dart';
import '../core/command_scheduler.dart';
import '../core/driver.dart';
import '../core/index_delegate.dart';
import '../core/logical_geometry.dart';
import '../core/motion.dart';
import '../core/restoration.dart';
import '../core/scroll_placement.dart';
import '../core/scroll_sync_coordinator_kernel.dart';
import '../core/scroll_target.dart';
import '../core/sparse_extent_index.dart';
import '../core/sync_mapping.dart';
import '../core/target_loader.dart';
import 'seeko_nested_position_driver.dart';
import 'seeko_position_driver.dart';
import 'seeko_snap.dart';
import 'seeko_snapshot.dart';
import 'seeko_timeline.dart';

part 'scroll_sync_group.dart';
part 'seeko_section_mapping.dart';
part 'seeko_indexed_grid.dart';
part 'seeko_indexed_sliver.dart';
part 'seeko_nested_scroll_binding.dart';

/// Geometry supplied when resolving the unobstructed viewport region.
final class ScrollViewportGeometry {
  const ScrollViewportGeometry({
    required this.viewportExtent,
    required this.axis,
    required this.axisDirection,
  });

  final double viewportExtent;
  final Axis axis;
  final AxisDirection axisDirection;
}

/// Returns viewport-local logical intervals that are not obscured.
///
/// The default region is the complete viewport. Applications may subtract
/// pinned headers, keyboard overlays, floating controls, or other occlusion.
typedef ViewportObstructionResolver = VisibleRegion Function(
  ScrollViewportGeometry viewport,
);

/// Terminal result of the one-shot [SeekoController.initialTarget] layout.
///
/// Initial positioning happens before the first paint and therefore does not
/// enter the normal attached command scheduler. Expected resolution failures
/// are reported here instead of escaping from RenderSliver layout.
final class SeekoInitialTargetResult {
  const SeekoInitialTargetResult._({
    required this.target,
    required this.placement,
    required this.outcome,
    required this.dataRevision,
    required this.finalLogicalPixels,
  });

  /// The index or stable-key target supplied to the controller.
  final ScrollTarget target;

  /// Requested placement inside the first effective viewport.
  final ScrollPlacement placement;

  /// Terminal initial-target outcome.
  final ScrollOutcome outcome;

  /// Data revision used to resolve the target, when available.
  final int? dataRevision;

  /// Settled logical pixels, or `null` when the target was not resolved.
  final double? finalLogicalPixels;

  /// Whether the initial target was positioned exactly.
  bool get isSuccess => outcome == ScrollOutcome.completed;
}

/// Explicitly selects the single [ScrollPosition] used by an adapted existing
/// controller.
///
/// The binding is caller-owned. Rebind it whenever the existing scrollable
/// creates a replacement position; Seeko deliberately does not guess among
/// multiple positions or monkey-patch the existing controller lifecycle.
final class SeekoPositionBinding extends ChangeNotifier {
  ScrollController? _owner;
  SeekoController? _claimant;
  ScrollPosition? _position;

  ScrollPosition? get position => _position;

  void rebind(ScrollPosition position) {
    final ScrollController? owner = _owner;
    if (owner == null) {
      throw StateError(
        'SeekoPositionBinding is not attached to an adapted controller.',
      );
    }
    if (!owner.positions
        .any((ScrollPosition value) => identical(value, position))) {
      throw StateError(
        'The selected ScrollPosition is not attached to the existing '
        'ScrollController supplied to SeekoController.adapt.',
      );
    }
    if (identical(_position, position)) {
      return;
    }
    _position = position;
    notifyListeners();
  }

  void unbind() {
    if (_position == null) {
      return;
    }
    _position = null;
    notifyListeners();
  }

  void _claim(ScrollController owner, SeekoController claimant) {
    if (_claimant != null) {
      throw StateError(
        'A SeekoPositionBinding can be claimed by only one adapter at a time.',
      );
    }
    _owner = owner;
    _claimant = claimant;
  }

  void _release(ScrollController owner, SeekoController claimant) {
    if (!identical(_owner, owner) || !identical(_claimant, claimant)) {
      return;
    }
    _owner = null;
    _claimant = null;
    _position = null;
  }
}

/// A [ScrollController] that adds typed semantic commands without replacing
/// Flutter's native scrollable widgets.
class SeekoController extends ScrollController {
  SeekoController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.defaultOptions = const ScrollCommandOptions(),
    this.obstructionResolver,
    this.indexDelegate,
    this.initialTarget,
    this.initialPlacement = const ScrollPlacement.start(),
    this.snapConfiguration,
    this.targetLoader,
    this.customTargetResolver,
    ScrollTargetLoadPolicy? targetLoadPolicy,
  })  : _adaptedController = null,
        _binding = null,
        _exclusiveProgrammaticWrites = true,
        targetLoadPolicy = targetLoadPolicy ?? ScrollTargetLoadPolicy() {
    if (initialTarget != null && initialScrollOffset != 0) {
      throw ArgumentError(
        'initialTarget and a non-zero initialScrollOffset are mutually '
        'exclusive.',
      );
    }
    if (initialTarget != null &&
        initialTarget is! IndexScrollTarget &&
        initialTarget is! KeyScrollTarget) {
      throw ArgumentError.value(
        initialTarget,
        'initialTarget',
        'must be an index or stable key target for SeekoIndexedSliver',
      );
    }
    if (initialTarget != null) {
      _initialTargetCompleter = Completer<SeekoInitialTargetResult>();
    }
  }

  /// Adds the Seeko façade to a controller that cannot be replaced.
  ///
  /// [binding] must explicitly select the current position and be rebound when
  /// that position changes. One binding can be claimed by only one adapter at a
  /// time. The adapter never disposes [existingController] or [binding].
  ///
  /// When [exclusiveProgrammaticWrites] is true, the caller promises that all
  /// programmatic writes use this façade, so [ScrollCapability.singleWriter]
  /// is declared. An existing controller can still receive direct writes and
  /// its position activity cannot be intercepted, so adapted controllers never
  /// declare [ScrollCapability.strictSync] or
  /// [ScrollCapability.programmaticResult]. Without the exclusive promise,
  /// typed command results are marked as fallback/degraded.
  factory SeekoController.adapt(
    ScrollController existingController, {
    required SeekoPositionBinding binding,
    bool exclusiveProgrammaticWrites = false,
    ScrollCommandOptions defaultOptions = const ScrollCommandOptions(),
    ViewportObstructionResolver? obstructionResolver,
    SeekoIndexDelegate<Object>? indexDelegate,
    SeekoSnapConfiguration? snapConfiguration,
    ScrollTargetLoader? targetLoader,
    ScrollCustomTargetResolver? customTargetResolver,
    ScrollTargetLoadPolicy? targetLoadPolicy,
  }) {
    return SeekoController._adapted(
      existingController,
      binding: binding,
      exclusiveProgrammaticWrites: exclusiveProgrammaticWrites,
      defaultOptions: defaultOptions,
      obstructionResolver: obstructionResolver,
      indexDelegate: indexDelegate,
      snapConfiguration: snapConfiguration,
      targetLoader: targetLoader,
      customTargetResolver: customTargetResolver,
      targetLoadPolicy: targetLoadPolicy ?? ScrollTargetLoadPolicy(),
    );
  }

  SeekoController._adapted(
    ScrollController existingController, {
    required SeekoPositionBinding binding,
    required bool exclusiveProgrammaticWrites,
    required this.defaultOptions,
    required this.obstructionResolver,
    required this.indexDelegate,
    required this.snapConfiguration,
    required this.targetLoader,
    required this.customTargetResolver,
    required this.targetLoadPolicy,
  })  : _adaptedController = existingController,
        _binding = binding,
        _exclusiveProgrammaticWrites = exclusiveProgrammaticWrites,
        initialTarget = null,
        initialPlacement = const ScrollPlacement.start(),
        super(
          initialScrollOffset: existingController.initialScrollOffset,
          keepScrollOffset: existingController.keepScrollOffset,
          debugLabel: existingController.debugLabel,
        ) {
    binding._claim(existingController, this);
    binding.addListener(_handleBindingChanged);
    _handleBindingChanged();
  }

  final ScrollCommandOptions defaultOptions;
  final ViewportObstructionResolver? obstructionResolver;
  final SeekoIndexDelegate<Object>? indexDelegate;
  final SeekoSnapConfiguration? snapConfiguration;
  final ScrollTargetLoader? targetLoader;
  final ScrollCustomTargetResolver? customTargetResolver;
  final ScrollTargetLoadPolicy targetLoadPolicy;

  /// Optional index/key target applied during the first L3 layout before paint.
  ///
  /// It is mutually exclusive with a non-zero [initialScrollOffset]. The
  /// target is consumed once per controller, so PageStorage/restoration and
  /// later detach/reattach cycles keep their current semantic position.
  final ScrollTarget? initialTarget;

  /// Placement used by [initialTarget] inside the first effective viewport.
  final ScrollPlacement initialPlacement;

  /// Completes once [initialTarget] settles or reaches a typed terminal state.
  ///
  /// This is `null` when no initial target was configured. The future never
  /// throws for expected resolution failures and completes with
  /// [ScrollOutcome.detached] if the controller is disposed before layout.
  Future<SeekoInitialTargetResult>? get initialTargetResult =>
      _initialTargetCompleter?.future;

  final ScrollController? _adaptedController;
  final SeekoPositionBinding? _binding;
  final bool _exclusiveProgrammaticWrites;
  final ScrollCommandScheduler _scheduler = ScrollCommandScheduler();
  final ScrollSnapshotNotifier _state = ScrollSnapshotNotifier();
  final Map<Object, BuildContext> _mountedKeys = <Object, BuildContext>{};
  final Map<int, BuildContext> _mountedIndexes = <int, BuildContext>{};
  final Map<BuildContext, _MountedTargetRecord> _mountedTargets =
      <BuildContext, _MountedTargetRecord>{};
  Completer<void>? _mountedRegistryCommit;
  var _mountedRegistryDirty = false;
  var _snapshotScheduled = false;
  var _positionValidationScheduled = false;
  var _programmatic = false;
  var _disposed = false;
  var _rawSequence = 0;
  ScrollPosition? _adaptedPosition;
  StreamController<ScrollRawEvent>? _rawEventController;
  StreamController<ScrollResult>? _commandResultController;
  int? _activeCommandId;
  ScrollEventOrigin _lastOrigin = ScrollEventOrigin.none;
  ScrollEventOrigin _activeProgrammaticOrigin = ScrollEventOrigin.programmatic;
  _ScrollSyncMemberState? _syncMember;
  final List<_SeekoIndexedSliverHost> _indexedSlivers =
      <_SeekoIndexedSliverHost>[];
  _SeekoIndexedSliverHost? _activeIndexedMotionSliver;
  late final SeekoIndexedMotionCoordinator _indexedMotionCoordinator =
      _CompositeIndexedMotionCoordinator(this);
  Object? _nestedBindingOwner;
  ScrollPosition? _nestedInnerPosition;
  var _nestedBindingAmbiguous = false;
  int? _applyingSyncTransactionId;
  int? _pendingSyncTransactionId;
  var _initialTargetConsumed = false;
  Completer<SeekoInitialTargetResult>? _initialTargetCompleter;
  var _snapEligible = false;
  var _snapScheduled = false;
  var _snapGeneration = 0;
  int? _activeSnapGeneration;
  Completer<void>? _snapResolverCancellation;

  bool get isAdapted => _adaptedController != null;

  bool get isAttached => hasClients;
  ValueListenable<ScrollSnapshot> get state => _state;

  /// High-frequency position events, created only after the first listener.
  ///
  /// Prefer [state] for UI rebuilds because it is coalesced to at most one
  /// structurally deduplicated update per frame.
  Stream<ScrollRawEvent> get rawEvents {
    return (_rawEventController ??=
            StreamController<ScrollRawEvent>.broadcast(sync: true))
        .stream;
  }

  /// Terminal typed command results, created only after the first listener.
  ///
  /// Convenience methods such as [jumpToIndex], [animateToKey],
  /// [ensureTargetVisible], restoration, and snap publish through this stream
  /// because they share the same target command pipeline. Native Flutter
  /// pixel methods keep their `Future<void>` contract and are not included.
  Stream<ScrollResult> get commandResults {
    return (_commandResultController ??=
            StreamController<ScrollResult>.broadcast(sync: true))
        .stream;
  }

  ScrollResult _publishCommandResult(ScrollResult result) {
    if (!_disposed) {
      _commandResultController?.add(result);
    }
    return result;
  }

  @override
  bool get hasClients =>
      isAdapted ? _adaptedPosition != null : super.hasClients;

  @override
  Iterable<ScrollPosition> get positions sync* {
    if (!isAdapted) {
      yield* super.positions;
      return;
    }
    final ScrollPosition? current = _adaptedPosition;
    if (current != null) {
      yield current;
    }
  }

  @override
  ScrollPosition get position {
    if (!isAdapted) {
      return super.position;
    }
    final ScrollPosition? current = _adaptedPosition;
    if (current == null) {
      throw StateError(
        'The adapted SeekoController has no bound ScrollPosition. '
        'Call SeekoPositionBinding.rebind after the existing controller '
        'attaches.',
      );
    }
    return current;
  }

  /// The current display's nominal vsync interval.
  ///
  /// Motion remains wall-clock based; this value is supplied to planners for
  /// frame-aware correction and diagnostics without assuming 60 or 120 Hz.
  Duration get frameInterval {
    return _frameIntervalFor(position);
  }

  Duration _frameIntervalFor(ScrollPosition commandPosition) {
    final double refreshRate = _displayRefreshRateFor(commandPosition);
    return Duration(
      microseconds: (Duration.microsecondsPerSecond / refreshRate).round(),
    );
  }

  double _displayRefreshRateFor(ScrollPosition commandPosition) {
    final BuildContext? context = commandPosition.context.notificationContext;
    final double? refreshRate =
        context == null ? null : View.maybeOf(context)?.display.refreshRate;
    if (refreshRate == null || !refreshRate.isFinite || refreshRate <= 0) {
      return 60;
    }
    return refreshRate;
  }

  ScrollCapabilities get capabilities {
    var value = ScrollCapabilities.pixel |
        const ScrollCapabilities(
          ScrollCapability.observationBit | ScrollCapability.mountedTargetBit,
        );
    if (!isAdapted) {
      value = value |
          const ScrollCapabilities(
            ScrollCapability.singleWriterBit |
                ScrollCapability.programmaticResultBit |
                ScrollCapability.strictSyncBit,
          );
      if (_nestedBindingOwner == null) {
        value = value |
            const ScrollCapabilities(
              ScrollCapability.naturalSyncPhysicsBit,
            );
      }
      if (_indexedSlivers.isNotEmpty) {
        value = value |
            const ScrollCapabilities(
              ScrollCapability.unmountedIndexBit |
                  ScrollCapability.stableKeyBit |
                  ScrollCapability.visibleItemsBit |
                  ScrollCapability.anchorPreservationBit |
                  ScrollCapability.dynamicExtentCorrectionBit |
                  ScrollCapability.semanticSyncBit,
            );
      }
    } else if (_exclusiveProgrammaticWrites) {
      value =
          value | const ScrollCapabilities(ScrollCapability.singleWriterBit);
    }
    if (customTargetResolver != null) {
      value =
          value | const ScrollCapabilities(ScrollCapability.customTargetBit);
    }
    return value;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    if (isAdapted) {
      throw StateError(
        'An adapted SeekoController is a façade and cannot be passed as the '
        'ScrollView controller. Keep using the existing controller.',
      );
    }
    return _SeekoScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      onActivityChanged: _handleActivityChanged,
      onMetricsChanged: _handleMetricsChanged,
      onUserScrollRequest: _handleUserScrollRequest,
    );
  }

  @override
  void attach(ScrollPosition position) {
    if (isAdapted) {
      throw StateError(
        'An adapted SeekoController cannot own a ScrollPosition. '
        'Bind the existing controller position explicitly instead.',
      );
    }
    final bool replacingNestedPosition = hasClients;
    if (replacingNestedPosition && _nestedBindingOwner == null) {
      throw StateError(
        'SeekoController supports one active ScrollPosition. '
        'Use one controller per view and synchronize them with a group.',
      );
    }
    super.attach(position);
    position.addListener(_handlePositionChanged);
    position.isScrollingNotifier.addListener(_scheduleSnapshot);
    if (replacingNestedPosition) {
      _scheduleOwnedPositionValidation();
    }
    _scheduleSnapshot();
    _syncMember?._handleAttach();
  }

  @override
  void detach(ScrollPosition position) {
    if (isAdapted) {
      throw StateError('An adapted SeekoController does not own positions.');
    }
    _scheduler.cancelAll(ScrollStopReason.detached);
    _invalidatePendingSnap();
    position.removeListener(_handlePositionChanged);
    position.isScrollingNotifier.removeListener(_scheduleSnapshot);
    _syncMember?._handleDetach();
    super.detach(position);
    if (!_disposed && !hasClients) {
      _state.value = const ScrollSnapshot.detached();
    } else if (!_disposed) {
      _scheduleSnapshot();
    }
  }

  void _scheduleOwnedPositionValidation() {
    if (_positionValidationScheduled || _disposed) {
      return;
    }
    _positionValidationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _positionValidationScheduled = false;
      if (_disposed || isAdapted) {
        return;
      }
      final int count = super.positions.length;
      if (count > 1) {
        throw StateError(
          'SeekoController supports one active outer ScrollPosition. '
          'A SeekoNestedScrollBinding may overlap old and replacement '
          'positions only until the end of the current frame.',
        );
      }
    });
  }

  /// Jumps to Flutter position pixels while preserving the native API contract.
  ///
  /// This replaces any active typed Seeko command and participates in an
  /// attached raw-pixel synchronization transaction. It does not apply Seeko
  /// boundary, conflict, resolution, or execution policies. Use
  /// [jumpToTarget] with an [OffsetScrollTarget] when a typed [ScrollResult] is
  /// required.
  @override
  void jumpTo(double value) {
    _invalidatePendingSnap();
    _scheduler.cancelAll(ScrollStopReason.superseded);
    _lastOrigin = ScrollEventOrigin.programmatic;
    if (isAdapted) {
      position.jumpTo(value);
    } else {
      super.jumpTo(value);
    }
  }

  /// Animates to Flutter position pixels while preserving `Future<void>`.
  ///
  /// Completion and interruption follow Flutter's native position activity.
  /// This replaces any active typed Seeko command and does not apply Seeko
  /// boundary, conflict, resolution, or execution policies. Use
  /// [animateToTarget] with an [OffsetScrollTarget] for adaptive motion and a
  /// typed [ScrollResult].
  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    _invalidatePendingSnap();
    _scheduler.cancelAll(ScrollStopReason.superseded);
    _lastOrigin = ScrollEventOrigin.programmatic;
    if (isAdapted) {
      return position.animateTo(offset, duration: duration, curve: curve);
    }
    return super.animateTo(offset, duration: duration, curve: curve);
  }

  /// Captures the current visible stable-key anchor for restoration.
  ///
  /// Returns null when no attached, laid-out, key-bearing target is visible.
  /// The capture is on demand; merely creating a controller adds no
  /// restoration listeners or per-frame work.
  SeekoRestorationAnchor<K>? captureRestorationAnchor<K extends Object>({
    String driverKind = 'tagged',
  }) {
    if (!hasClients || !position.hasContentDimensions) {
      return null;
    }
    final ScrollPosition current = position;
    final ScrollPosition anchorPosition = _nestedInnerFor(current) ?? current;
    final ScrollSemanticAnchor? semantic = _anchorFor(
      _collectVisibleTargets(current),
      current.viewportDimension,
      visibleRegion: _visibleRegionFor(anchorPosition),
    );
    final Object? key = semantic?.key;
    if (semantic == null || key == null) {
      return null;
    }
    if (key is! K) {
      throw StateError(
        'Cannot capture SeekoRestorationAnchor<$K>: the visible target key '
        'has runtime type ${key.runtimeType}. Request the target key type '
        'registered by SeekoTag or use Object for heterogeneous keys.',
      );
    }
    final LogicalAxisGeometry geometry = _geometryFor(current);
    final double logical = geometry.physicalToLogical(current.pixels);
    return SeekoRestorationAnchor<K>(
      driverKind: driverKind,
      key: key,
      lastKnownIndex: semantic.index,
      itemAnchor: semantic.itemAnchor,
      viewportAnchor: semantic.viewportAnchor,
      logicalOffset: semantic.logicalOffset,
      dataRevisionHint: indexDelegate?.revision,
      fallbackProgress: geometry.extent == 0 ? null : logical / geometry.extent,
    );
  }

  /// Restores a semantic anchor through the normal command scheduler/driver.
  ///
  /// When an [indexDelegate] is configured, a missing key follows [policy]
  /// without inventing key ordering. Without a delegate, the controller can
  /// still restore a currently mounted key, but cannot apply data-aware
  /// fallbacks.
  Future<ScrollResult> restoreRestorationAnchor<K extends Object>(
    SeekoRestorationAnchor<K> anchor, {
    SeekoRestorationPolicy<K>? policy,
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    _requireAttached();
    final ScrollTarget requested = ScrollTarget.key(anchor.key);
    final SeekoIndexDelegate<K>? delegate = _restorationDelegate<K>();
    if (delegate == null) {
      return _jumpToTarget(
        requested,
        requestedTarget: requested,
        placement: ScrollPlacement.exact(
          targetAnchor: anchor.itemAnchor,
          viewportAnchor: anchor.viewportAnchor,
          offset: anchor.logicalOffset,
        ),
        options: options,
        origin: ScrollEventOrigin.restoration,
      )
          .then(
            (ScrollResult result) => _decorateRestorationResult(
              result,
              requestedTarget: requested,
              resolutionMode: result.resolutionMode,
              diagnostics: <String, Object?>{
                'driverKind': anchor.driverKind,
                'restoredRevisionHint': anchor.dataRevisionHint,
                'currentRevision': null,
                'indexDelegate': 'unavailable',
              },
            ),
          )
          .then(_publishCommandResult);
    }
    final SeekoRestorationResolution resolution = resolveSeekoRestoration(
      anchor: anchor,
      delegate: delegate,
      policy: policy,
    );
    return _executeRestorationResolution(
      resolution,
      requestedTarget: requested,
      options: options,
      failedOutcome: ScrollOutcome.targetDeleted,
    ).then(_publishCommandResult);
  }

  /// Applies restoration fallback metadata retained after codec decoding
  /// failed or became incompatible with the current schema.
  Future<ScrollResult> restoreRestorationFallback<K extends Object>(
    SeekoRestorationFallbackState fallbackState, {
    SeekoRestorationPolicy<K>? policy,
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    _requireAttached();
    final SeekoIndexDelegate<K>? delegate = _restorationDelegate<K>();
    if (delegate == null) {
      throw StateError(
        'Restoration fallback requires SeekoController.indexDelegate so '
        'index hints and current stable keys can be resolved.',
      );
    }
    final SeekoRestorationResolution resolution = resolveSeekoRestoration(
      fallbackState: fallbackState,
      delegate: delegate,
      policy: policy,
    );
    return _executeRestorationResolution(
      resolution,
      requestedTarget: ScrollTarget.custom(fallbackState),
      options: options,
      failedOutcome: ScrollOutcome.resolverRejected,
    ).then(_publishCommandResult);
  }

  SeekoIndexDelegate<K>? _restorationDelegate<K extends Object>() {
    final SeekoIndexDelegate<Object>? delegate = indexDelegate;
    if (delegate == null) {
      return null;
    }
    if (delegate is SeekoIndexDelegate<K>) {
      return delegate;
    }
    throw StateError(
      'Cannot restore SeekoRestorationAnchor<$K>: the controller index '
      'delegate uses a different key type. Use the same key type for the '
      'anchor, restoration policy, SeekoTag, and index delegate.',
    );
  }

  Future<ScrollResult> _executeRestorationResolution(
    SeekoRestorationResolution resolution, {
    required ScrollTarget requestedTarget,
    required ScrollCommandOptions options,
    required ScrollOutcome failedOutcome,
  }) {
    final ScrollResolutionMode resolutionMode =
        resolution.mode == ScrollResolutionMode.exact
            ? _resultResolutionMode
            : resolution.mode;
    final Map<String, Object?> diagnostics = <String, Object?>{
      ...resolution.diagnostics,
      if (resolution.fallbackStep != null)
        'fallbackStep': resolution.fallbackStep!.name,
    };
    if (resolution.status == SeekoRestorationResolutionStatus.targetNotLoaded) {
      return _scheduleRestorationTerminal(
        requestedTarget: requestedTarget,
        capturedTarget: resolution.target,
        outcome: ScrollOutcome.targetNotLoaded,
        resolutionMode: resolutionMode,
        diagnostics: diagnostics,
        options: options,
      );
    }
    final ScrollTarget? target = resolution.target;
    if (resolution.status == SeekoRestorationResolutionStatus.failed ||
        target == null) {
      return _scheduleRestorationTerminal(
        requestedTarget: requestedTarget,
        capturedTarget: null,
        outcome: failedOutcome,
        resolutionMode: resolutionMode,
        diagnostics: diagnostics,
        options: options,
      );
    }
    return _jumpToTarget(
      target,
      requestedTarget: requestedTarget,
      placement: resolution.placement,
      options: options,
      origin: ScrollEventOrigin.restoration,
      resolutionMode: resolutionMode,
    ).then(
      (ScrollResult result) => _decorateRestorationResult(
        result,
        requestedTarget: requestedTarget,
        resolutionMode: resolutionMode,
        diagnostics: diagnostics,
      ),
    );
  }

  Future<ScrollResult> jumpToTarget(
    ScrollTarget target, {
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    if (_activeSnapGeneration == null) {
      _invalidatePendingSnap();
    }
    return _jumpToTarget(
      target,
      placement: placement,
      options: options,
    ).then(_publishCommandResult);
  }

  /// Jumps to the stable item captured at [index].
  Future<ScrollResult> jumpToIndex(
    int index, {
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return jumpToTarget(
      ScrollTarget.index(index),
      placement: placement,
      options: options,
    );
  }

  /// Jumps to the item identified by [key].
  Future<ScrollResult> jumpToKey(
    Object key, {
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return jumpToTarget(
      ScrollTarget.key(key),
      placement: placement,
      options: options,
    );
  }

  Future<ScrollResult> _jumpToTarget(
    ScrollTarget target, {
    required ScrollPlacement placement,
    required ScrollCommandOptions options,
    ScrollTarget? requestedTarget,
    ScrollEventOrigin origin = ScrollEventOrigin.programmatic,
    ScrollResolutionMode? resolutionMode,
  }) {
    _requireAttached();
    final ScrollCommandOptions effective = defaultOptions.merge(options);
    final _CapturedCommandTarget initialCaptured = _captureTarget(target);
    final ScrollTarget requested = requestedTarget ?? target;
    final ScrollResolutionMode effectiveResolutionMode =
        resolutionMode ?? _resultResolutionMode;
    int? commandId;
    final Future<ScrollResult> future = _scheduler.schedule(
      target: requested,
      policy: effective.conflictPolicy ?? ScrollConflictPolicy.replace,
      executionPolicy:
          effective.executionPolicy ?? ScrollExecutionPolicy.jump(),
      cancellationToken: effective.cancellationToken,
      execute: (ScrollCommandContext context) async {
        commandId = context.commandId;
        late final ScrollPosition commandPosition;
        if (!context.commit(() {
          commandPosition = position;
        })) {
          return _cancelledResult(context);
        }
        final ScrollResult? policyFailure = _resolutionPolicyFailure(
          context,
          effective.resolutionPolicy,
          commandPosition,
          resolutionMode: effectiveResolutionMode,
        );
        if (policyFailure != null) {
          return policyFailure;
        }
        final int? commandStartRevision = initialCaptured.revision;
        final _TargetLoadResolution<_PreparedCommandTarget> loadResolution =
            await _resolveWithTargetLoader<_PreparedCommandTarget>(
          context: context,
          target: target,
          startRevision: commandStartRevision,
          initialValue: await _prepareCommandTarget(
            context: context,
            commandPosition: commandPosition,
            captured: initialCaptured,
            placement: placement,
            boundaryPolicy:
                effective.boundaryPolicy ?? ScrollBoundaryPolicy.clampNumeric,
            resolutionMode: effectiveResolutionMode,
          ),
          isNotLoaded: (_PreparedCommandTarget value) => value.isNotLoaded,
          resolve: () => _prepareCommandTarget(
            context: context,
            commandPosition: commandPosition,
            captured: _captureTarget(target),
            placement: placement,
            boundaryPolicy:
                effective.boundaryPolicy ?? ScrollBoundaryPolicy.clampNumeric,
            resolutionMode: effectiveResolutionMode,
          ),
        );
        if (loadResolution.cancelled) {
          return _cancelledResult(context, commandPosition);
        }
        if (loadResolution.isTerminal) {
          return _targetLoadFailureResult(
            context,
            commandPosition,
            loadResolution,
            startRevision: commandStartRevision,
          );
        }
        final _PreparedCommandTarget prepared = loadResolution.value;
        final _CapturedCommandTarget captured = prepared.captured;
        final Map<String, Object?> commandDiagnostics =
            loadResolution.diagnostics;
        if (captured.failure != null) {
          return _captureFailureResult(
            context,
            captured,
            commandPosition,
            commandStartRevision: commandStartRevision,
            commandDiagnostics: commandDiagnostics,
          );
        }
        final ScrollResolution resolution = prepared.resolution!;
        if (!resolution.isResolved) {
          return _driverFailureResult(
            context,
            resolution,
            commandPosition,
            commandStartRevision: commandStartRevision,
            commandDiagnostics: commandDiagnostics,
          );
        }
        if (!context.commit(() {
          _beginProgrammatic(
            context.commandId,
            lockUserInteraction: effective.lockUserInteraction ?? false,
            origin: origin,
          );
        })) {
          return _cancelledResult(context, commandPosition);
        }
        final ScrollDriver driver = prepared.driver!;
        if (!context.transitionTo(ScrollCommandPhase.moving)) {
          return _cancelledResult(context, commandPosition);
        }
        final ScrollDriverResult moved = await driver.jump(resolution);
        if (!moved.isSuccess) {
          return _resultFromDriver(
            context,
            requested,
            captured,
            resolution,
            moved,
            commandStartRevision: commandStartRevision,
            commandDiagnostics: commandDiagnostics,
          );
        }
        if (!context.transitionTo(ScrollCommandPhase.correcting)) {
          return _cancelledResult(context, commandPosition);
        }
        final ScrollDriverResult driverResult = await driver.stabilize(
          captured.target,
          resolution,
          moved,
          executionPolicy: context.executionPolicy,
        );
        if (driverResult.isSuccess &&
            !context.transitionTo(ScrollCommandPhase.settled)) {
          return _cancelledResult(context, commandPosition);
        }
        return _resultFromDriver(
          context,
          requested,
          captured,
          resolution,
          driverResult,
          commandStartRevision: commandStartRevision,
          commandDiagnostics: commandDiagnostics,
        );
      },
    );
    return future
        .then(_normalizeAdaptedResult)
        .whenComplete(() => _endProgrammaticFor(commandId));
  }

  Future<ScrollResult> animateToTarget(
    ScrollTarget target, {
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollMotion motion = const ScrollMotion.adaptive(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    if (_activeSnapGeneration == null) {
      _invalidatePendingSnap();
    }
    _requireAttached();
    final ScrollCommandOptions effective = defaultOptions.merge(options);
    final _CapturedCommandTarget initialCaptured = _captureTarget(target);
    int? commandId;
    final Future<ScrollResult> future = _scheduler.schedule(
      target: target,
      policy: effective.conflictPolicy ?? ScrollConflictPolicy.replace,
      executionPolicy: effective.executionPolicy ?? _executionPolicyFor(motion),
      cancellationToken: effective.cancellationToken,
      execute: (ScrollCommandContext context) async {
        commandId = context.commandId;
        late final ScrollPosition commandPosition;
        if (!context.commit(() {
          commandPosition = position;
        })) {
          return _cancelledResult(context);
        }
        final ScrollResult? policyFailure = _resolutionPolicyFailure(
          context,
          effective.resolutionPolicy,
          commandPosition,
        );
        if (policyFailure != null) {
          return policyFailure;
        }
        final int? commandStartRevision = initialCaptured.revision;
        final _TargetLoadResolution<_PreparedCommandTarget> loadResolution =
            await _resolveWithTargetLoader<_PreparedCommandTarget>(
          context: context,
          target: target,
          startRevision: commandStartRevision,
          initialValue: await _prepareCommandTarget(
            context: context,
            commandPosition: commandPosition,
            captured: initialCaptured,
            placement: placement,
            boundaryPolicy:
                effective.boundaryPolicy ?? ScrollBoundaryPolicy.clampNumeric,
            resolutionMode: _resultResolutionMode,
          ),
          isNotLoaded: (_PreparedCommandTarget value) => value.isNotLoaded,
          resolve: () => _prepareCommandTarget(
            context: context,
            commandPosition: commandPosition,
            captured: _captureTarget(target),
            placement: placement,
            boundaryPolicy:
                effective.boundaryPolicy ?? ScrollBoundaryPolicy.clampNumeric,
            resolutionMode: _resultResolutionMode,
          ),
        );
        if (loadResolution.cancelled) {
          return _cancelledResult(context, commandPosition);
        }
        if (loadResolution.isTerminal) {
          return _targetLoadFailureResult(
            context,
            commandPosition,
            loadResolution,
            startRevision: commandStartRevision,
          );
        }
        final _PreparedCommandTarget prepared = loadResolution.value;
        final _CapturedCommandTarget captured = prepared.captured;
        final Map<String, Object?> commandDiagnostics =
            loadResolution.diagnostics;
        if (captured.failure != null) {
          return _captureFailureResult(
            context,
            captured,
            commandPosition,
            commandStartRevision: commandStartRevision,
            commandDiagnostics: commandDiagnostics,
          );
        }
        final ScrollResolution resolution = prepared.resolution!;
        if (!resolution.isResolved) {
          return _driverFailureResult(
            context,
            resolution,
            commandPosition,
            commandStartRevision: commandStartRevision,
            commandDiagnostics: commandDiagnostics,
          );
        }
        if (!context.commit(() {
          _beginProgrammatic(
            context.commandId,
            lockUserInteraction: effective.lockUserInteraction ?? false,
          );
        })) {
          return _cancelledResult(context, commandPosition);
        }
        final ScrollDriver driver = prepared.driver!;
        final ScrollMotionPlan plan = driver.planMotion(resolution, motion);
        if (!context.transitionTo(ScrollCommandPhase.moving)) {
          return _cancelledResult(context, commandPosition);
        }
        final ScrollDriverResult moved = await driver.animate(
          resolution,
          plan,
        );
        if (!moved.isSuccess) {
          return _resultFromDriver(
            context,
            target,
            captured,
            resolution,
            moved,
            commandStartRevision: commandStartRevision,
            commandDiagnostics: commandDiagnostics,
          );
        }
        if (!context.transitionTo(ScrollCommandPhase.correcting)) {
          return _cancelledResult(context, commandPosition);
        }
        final ScrollDriverResult driverResult = await driver.stabilize(
          captured.target,
          resolution,
          moved,
          executionPolicy: context.executionPolicy,
          correctionMotion: motion,
        );
        if (driverResult.isSuccess &&
            !context.transitionTo(ScrollCommandPhase.settled)) {
          return _cancelledResult(context, commandPosition);
        }
        return _resultFromDriver(
          context,
          target,
          captured,
          resolution,
          driverResult,
          commandStartRevision: commandStartRevision,
          commandDiagnostics: commandDiagnostics,
        );
      },
    );
    return future
        .then(_normalizeAdaptedResult)
        .then(_publishCommandResult)
        .whenComplete(() => _endProgrammaticFor(commandId));
  }

  /// Animates to the stable item captured at [index].
  Future<ScrollResult> animateToIndex(
    int index, {
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollMotion motion = const ScrollMotion.adaptive(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return animateToTarget(
      ScrollTarget.index(index),
      placement: placement,
      motion: motion,
      options: options,
    );
  }

  /// Animates to the item identified by [key].
  Future<ScrollResult> animateToKey(
    Object key, {
    ScrollPlacement placement = const ScrollPlacement.nearest(),
    ScrollMotion motion = const ScrollMotion.adaptive(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return animateToTarget(
      ScrollTarget.key(key),
      placement: placement,
      motion: motion,
      options: options,
    );
  }

  /// Moves only as far as necessary to expose [target].
  ///
  /// With [motion] omitted this is an immediate typed command. Supplying a
  /// motion uses the same cancellable animation pipeline as
  /// [animateToTarget].
  Future<ScrollResult> ensureTargetVisible(
    ScrollTarget target, {
    ScrollMotion? motion,
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    if (motion == null || motion.kind == ScrollMotionKind.instant) {
      return jumpToTarget(
        target,
        placement: const ScrollPlacement.nearest(),
        options: options,
      );
    }
    return animateToTarget(
      target,
      placement: const ScrollPlacement.nearest(),
      motion: motion,
      options: options,
    );
  }

  /// Resolves and executes the configured snap transaction immediately.
  ///
  /// Returns `null` when the resolver has no target for the current snapshot.
  /// Automatic snapping uses the same method after real user scrolling
  /// becomes idle; programmatic and synchronized writes do not trigger it.
  Future<ScrollResult?> snap() {
    if (snapConfiguration == null) {
      throw StateError(
        'SeekoController.snap requires a SeekoSnapConfiguration.',
      );
    }
    _requireAttached();
    _snapGeneration += 1;
    _snapEligible = false;
    return _executeSnap(_snapGeneration);
  }

  ScrollExecutionPolicy _executionPolicyFor(ScrollMotion motion) {
    if (motion.kind == ScrollMotionKind.duration && motion.duration != null) {
      final Duration deadline = motion.duration! + const Duration(seconds: 2);
      return ScrollExecutionPolicy(
        deadline: deadline > const Duration(seconds: 10)
            ? const Duration(seconds: 10)
            : deadline,
      );
    }
    return ScrollExecutionPolicy();
  }

  ScrollDriver _driverFor(
    ScrollCommandContext context,
    ScrollPosition commandPosition,
    ScrollPlacement placement,
    ScrollBoundaryPolicy boundaryPolicy, {
    ScrollResolutionMode? resolutionMode,
  }) {
    final PositionVisibleRegionResolver? visibleRegionResolver =
        obstructionResolver == null
            ? null
            : (ScrollPosition current) => obstructionResolver!(
                  ScrollViewportGeometry(
                    viewportExtent: current.viewportDimension,
                    axis: current.axis,
                    axisDirection: current.axisDirection,
                  ),
                );
    if (_nestedBindingOwner != null) {
      final ScrollPosition? inner = _nestedInnerPosition;
      return SeekoNestedPositionDriver(
        outerPosition: commandPosition,
        innerPosition: inner,
        bindingValid: !_nestedBindingAmbiguous &&
            inner != null &&
            inner.axis == commandPosition.axis &&
            inner.axisDirection == commandPosition.axisDirection,
        capabilities: capabilities,
        resolutionMode: resolutionMode ?? _resultResolutionMode,
        placement: placement,
        boundaryPolicy: boundaryPolicy,
        cancellationToken: context.cancellationToken,
        commit: context.commit,
        isCurrentPair: (ScrollPosition outer, ScrollPosition selectedInner) {
          return hasClients &&
              identical(position, outer) &&
              identical(_nestedInnerPosition, selectedInner);
        },
        mountedContextFor: _mountedContextFor,
        hasRegistryFor: _hasRegistryFor,
        frameInterval: _frameIntervalFor(commandPosition),
        reducedMotion: _disableAnimationsFor(commandPosition),
        visibleRegionResolver: visibleRegionResolver,
        indexedTargetResolver:
            _indexedSlivers.isEmpty ? null : _resolveIndexedTarget,
        customTargetResolver: customTargetResolver,
        indexedMotionCoordinator:
            _indexedSlivers.isEmpty ? null : _indexedMotionCoordinator,
      );
    }
    return SeekoPositionDriver(
      position: commandPosition,
      capabilities: capabilities,
      resolutionMode: resolutionMode ?? _resultResolutionMode,
      placement: placement,
      boundaryPolicy: boundaryPolicy,
      cancellationToken: context.cancellationToken,
      commit: context.commit,
      isCurrentPosition: () =>
          hasClients && identical(position, commandPosition),
      mountedContextFor: _mountedContextFor,
      hasRegistryFor: _hasRegistryFor,
      frameInterval: _frameIntervalFor(commandPosition),
      reducedMotion: _disableAnimationsFor(commandPosition),
      visibleRegionResolver: visibleRegionResolver,
      indexedTargetResolver:
          _indexedSlivers.isEmpty ? null : _resolveIndexedTarget,
      customTargetResolver: customTargetResolver,
      indexedMotionCoordinator:
          _indexedSlivers.isEmpty ? null : _indexedMotionCoordinator,
    );
  }

  SeekoIndexedTargetResolution? _resolveIndexedTarget(
    ScrollTarget target, {
    bool selectMotionTarget = true,
  }) {
    if (_indexedSlivers.isEmpty ||
        (target is! KeyScrollTarget && target is! IndexScrollTarget)) {
      return null;
    }
    if (selectMotionTarget) {
      _activeIndexedMotionSliver = null;
    }
    if (target case IndexScrollTarget(:final int index)) {
      final _CompositeIndexedLocation? location =
          _compositeLocationForIndex(index);
      if (location == null) {
        return _compositeItemCountKnown
            ? const SeekoIndexedTargetResolution.targetOutOfRange()
            : const SeekoIndexedTargetResolution.targetNotLoaded();
      }
      final SeekoIndexedTargetResolution? resolution =
          location.sliver.resolveTarget(
        ScrollTarget.index(
          location.localIndex,
          tracking: IndexTracking.liveSlot,
        ),
      );
      if (selectMotionTarget &&
          resolution?.status == ScrollResolutionStatus.resolved) {
        _activeIndexedMotionSliver = location.sliver;
      }
      return resolution;
    }

    _SeekoIndexedSliverHost? resolvedSliver;
    SeekoIndexedTargetResolution? resolved;
    var targetNotLoaded = false;
    var resolverRejected = false;
    for (final _SeekoIndexedSliverHost sliver in _indexedSlivers) {
      final SeekoIndexedTargetResolution? candidate =
          sliver.resolveTarget(target);
      switch (candidate?.status) {
        case ScrollResolutionStatus.resolved:
          if (resolved != null) {
            return SeekoIndexedTargetResolution.resolverRejected(
              diagnostics: <String, Object?>{
                'resolverKind': 'indexedSliverRegistry',
                'reason': 'duplicateResolvedKey',
              },
            );
          }
          resolved = candidate;
          resolvedSliver = sliver;
          break;
        case ScrollResolutionStatus.targetNotLoaded:
          targetNotLoaded = true;
          break;
        case ScrollResolutionStatus.resolverRejected:
          resolverRejected = true;
          break;
        case ScrollResolutionStatus.targetDeleted:
        case ScrollResolutionStatus.targetOutOfRange:
        case ScrollResolutionStatus.unsupported:
        case null:
          break;
      }
    }
    if (resolved != null) {
      if (selectMotionTarget) {
        _activeIndexedMotionSliver = resolvedSliver;
      }
      return resolved;
    }
    if (resolverRejected) {
      return SeekoIndexedTargetResolution.resolverRejected(
        diagnostics: <String, Object?>{
          'resolverKind': 'indexedSliverRegistry',
          'reason': 'childResolverRejected',
        },
      );
    }
    return targetNotLoaded
        ? const SeekoIndexedTargetResolution.targetNotLoaded()
        : const SeekoIndexedTargetResolution.targetDeleted();
  }

  SeekoIndexedTargetResolution? _initialIndexedResolutionFor(
    _SeekoIndexedSliverHost sliver,
  ) {
    final ScrollTarget? target = _pendingInitialTarget;
    if (target == null) {
      return null;
    }
    final _SeekoIndexedSliverHost? previousMotionSliver =
        _activeIndexedMotionSliver;
    final SeekoIndexedTargetResolution? resolution =
        _resolveIndexedTarget(target);
    final _SeekoIndexedSliverHost? owner = _activeIndexedMotionSliver;
    _activeIndexedMotionSliver = previousMotionSliver;
    if (resolution?.status == ScrollResolutionStatus.resolved) {
      return identical(owner, sliver) ? resolution : null;
    }
    return _indexedSlivers.isNotEmpty &&
            identical(_indexedSlivers.first, sliver)
        ? resolution
        : null;
  }

  bool get _compositeItemCountKnown {
    for (final _SeekoIndexedSliverHost sliver in _indexedSlivers) {
      if (sliver.indexDelegate.itemCount == null) {
        return false;
      }
    }
    return true;
  }

  _CompositeIndexedLocation? _compositeLocationForIndex(int index) {
    var remaining = index;
    for (final _SeekoIndexedSliverHost sliver in _indexedSlivers) {
      final int? itemCount = sliver.indexDelegate.itemCount;
      if (itemCount == null) {
        return null;
      }
      if (remaining < itemCount) {
        return _CompositeIndexedLocation(
          sliver: sliver,
          localIndex: remaining,
        );
      }
      remaining -= itemCount;
    }
    return null;
  }

  Future<_PreparedCommandTarget> _prepareCommandTarget({
    required ScrollCommandContext context,
    required ScrollPosition commandPosition,
    required _CapturedCommandTarget captured,
    required ScrollPlacement placement,
    required ScrollBoundaryPolicy boundaryPolicy,
    required ScrollResolutionMode resolutionMode,
  }) async {
    if (captured.failure != null) {
      return _PreparedCommandTarget(captured: captured);
    }
    final ScrollDriver driver = _driverFor(
      context,
      commandPosition,
      placement,
      boundaryPolicy,
      resolutionMode: resolutionMode,
    );
    final ScrollResolution resolution = await driver.resolve(captured.target);
    return _PreparedCommandTarget(
      captured: captured,
      driver: driver,
      resolution: resolution,
    );
  }

  Future<_TargetLoadResolution<T>> _resolveWithTargetLoader<T>({
    required ScrollCommandContext context,
    required ScrollTarget target,
    required int? startRevision,
    required T initialValue,
    required bool Function(T value) isNotLoaded,
    required FutureOr<T> Function() resolve,
  }) async {
    T value = initialValue;
    final ScrollTargetLoader? loader = targetLoader;
    if (!isNotLoaded(value) || loader == null) {
      return _TargetLoadResolution<T>.resolved(value);
    }
    Object? lastDiagnostic;
    int? loaderRevision;
    for (var attempt = 1;
        attempt <= targetLoadPolicy.maxAttempts;
        attempt += 1) {
      final _TargetLoaderInvocation invocation = await _invokeTargetLoader(
        loader,
        ScrollTargetLoadRequest(
          commandId: context.commandId,
          target: target,
          attempt: attempt,
          startRevision: startRevision,
          cancellationToken: context.cancellationToken,
        ),
      );
      if (invocation.cancelled || context.cancellationToken.isCancelled) {
        return _TargetLoadResolution<T>.cancelled(value, attempts: attempt);
      }
      final Object? invocationError = invocation.error;
      if (invocationError != null) {
        lastDiagnostic = invocationError;
        if (attempt == targetLoadPolicy.maxAttempts) {
          return _TargetLoadResolution<T>.terminal(
            value,
            outcome: ScrollOutcome.resolverRejected,
            attempts: attempt,
            diagnostic: invocationError,
          );
        }
        if (!await _waitForTargetLoadRetry(
          targetLoadPolicy.retryDelayAfter(attempt),
          context.cancellationToken,
        )) {
          return _TargetLoadResolution<T>.cancelled(
            value,
            attempts: attempt,
          );
        }
        continue;
      }

      final ScrollTargetLoadResult loadResult = invocation.result!;
      lastDiagnostic = loadResult.diagnostic;
      loaderRevision = loadResult.revision ?? loaderRevision;
      switch (loadResult.status) {
        case ScrollTargetLoadStatus.loaded:
          value = await Future<T>.sync(resolve);
          if (isNotLoaded(value)) {
            if (!await _waitForTargetLoadCommit(
              context.cancellationToken,
            )) {
              return _TargetLoadResolution<T>.cancelled(
                value,
                attempts: attempt,
              );
            }
            value = await Future<T>.sync(resolve);
          }
          if (!isNotLoaded(value)) {
            return _TargetLoadResolution<T>.resolved(
              value,
              attempts: attempt,
              diagnostic: lastDiagnostic,
              revision: loaderRevision,
            );
          }
          if (attempt == targetLoadPolicy.maxAttempts) {
            return _TargetLoadResolution<T>.resolved(
              value,
              attempts: attempt,
              diagnostic: lastDiagnostic,
              revision: loaderRevision,
            );
          }
          break;
        case ScrollTargetLoadStatus.notFound:
        case ScrollTargetLoadStatus.rejected:
          return _TargetLoadResolution<T>.terminal(
            value,
            outcome: loadResult.outcome!,
            attempts: attempt,
            diagnostic: loadResult.diagnostic,
            revision: loaderRevision,
          );
        case ScrollTargetLoadStatus.retry:
          if (attempt == targetLoadPolicy.maxAttempts) {
            return _TargetLoadResolution<T>.terminal(
              value,
              outcome: ScrollOutcome.resolverRejected,
              attempts: attempt,
              diagnostic: loadResult.diagnostic ?? 'retry-exhausted',
              revision: loaderRevision,
            );
          }
          if (!await _waitForTargetLoadRetry(
            targetLoadPolicy.retryDelayAfter(
              attempt,
              suggested: loadResult.retryAfter,
            ),
            context.cancellationToken,
          )) {
            return _TargetLoadResolution<T>.cancelled(
              value,
              attempts: attempt,
            );
          }
      }
    }
    return _TargetLoadResolution<T>.resolved(
      value,
      attempts: targetLoadPolicy.maxAttempts,
      diagnostic: lastDiagnostic,
      revision: loaderRevision,
    );
  }

  Future<_TargetLoaderInvocation> _invokeTargetLoader(
    ScrollTargetLoader loader,
    ScrollTargetLoadRequest request,
  ) async {
    if (request.cancellationToken.isCancelled) {
      return const _TargetLoaderInvocation.cancelled();
    }
    final Completer<_TargetLoaderInvocation> cancelled =
        Completer<_TargetLoaderInvocation>();
    void cancelListener() {
      if (!cancelled.isCompleted) {
        cancelled.complete(const _TargetLoaderInvocation.cancelled());
      }
    }

    request.cancellationToken.addListener(cancelListener);
    try {
      final Future<_TargetLoaderInvocation> loading =
          Future<ScrollTargetLoadResult>.sync(() => loader.load(request)).then(
        _TargetLoaderInvocation.completed,
        onError: (Object error, StackTrace stackTrace) =>
            _TargetLoaderInvocation.failed(error, stackTrace),
      );
      return await Future.any<_TargetLoaderInvocation>(
        <Future<_TargetLoaderInvocation>>[
          loading,
          cancelled.future,
        ],
      );
    } finally {
      request.cancellationToken.removeListener(cancelListener);
    }
  }

  Future<bool> _waitForTargetLoadRetry(
    Duration delay,
    ScrollCancellationToken cancellationToken,
  ) async {
    if (cancellationToken.isCancelled) {
      return false;
    }
    if (delay == Duration.zero) {
      return true;
    }
    final Completer<void> cancelled = Completer<void>();
    final Completer<void> delayCompleted = Completer<void>();
    final Timer timer = Timer(delay, delayCompleted.complete);
    void cancelListener() {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
    }

    cancellationToken.addListener(cancelListener);
    try {
      final Object completed = await Future.any<Object>(<Future<Object>>[
        delayCompleted.future.then<Object>((_) => _targetLoadDelayDone),
        cancelled.future.then<Object>((_) => _targetLoadDelayCancelled),
      ]);
      return identical(completed, _targetLoadDelayDone) &&
          !cancellationToken.isCancelled;
    } finally {
      timer.cancel();
      cancellationToken.removeListener(cancelListener);
    }
  }

  Future<bool> _waitForTargetLoadCommit(
    ScrollCancellationToken cancellationToken,
  ) async {
    if (cancellationToken.isCancelled) {
      return false;
    }
    final Completer<void> cancelled = Completer<void>();
    void cancelListener() {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
    }

    cancellationToken.addListener(cancelListener);
    try {
      final Object completed = await Future.any<Object>(<Future<Object>>[
        SchedulerBinding.instance.endOfFrame
            .then<Object>((_) => _targetLoadCommitDone),
        cancelled.future.then<Object>((_) => _targetLoadCommitCancelled),
      ]);
      return identical(completed, _targetLoadCommitDone) &&
          !cancellationToken.isCancelled;
    } finally {
      cancellationToken.removeListener(cancelListener);
    }
  }

  ScrollResult _targetLoadFailureResult<T>(
    ScrollCommandContext context,
    ScrollPosition commandPosition,
    _TargetLoadResolution<T> loadResolution, {
    required int? startRevision,
  }) {
    final Map<String, Object?> diagnostics = loadResolution.diagnostics;
    return ScrollResult(
      commandId: context.commandId,
      outcome: loadResolution.outcome!,
      requestedTarget: context.target,
      capturedTarget: null,
      achievedTarget: null,
      startRevision: startRevision,
      endRevision: indexDelegate?.revision ?? loadResolution.revision,
      resolutionMode: _resultResolutionMode,
      finalLogicalPixels: _logicalPixelsFor(commandPosition),
      finalError: null,
      elapsed: Duration.zero,
      replanCount: 0,
      correctionCount: 0,
      diagnostics: diagnostics.isEmpty ? null : diagnostics,
    );
  }

  ScrollResult _driverFailureResult(
    ScrollCommandContext context,
    ScrollResolution resolution,
    ScrollPosition commandPosition, {
    int? commandStartRevision,
    Map<String, Object?>? commandDiagnostics,
  }) {
    final ScrollOutcome outcome = switch (resolution.status) {
      ScrollResolutionStatus.resolved => ScrollOutcome.completed,
      ScrollResolutionStatus.targetNotLoaded => ScrollOutcome.targetNotLoaded,
      ScrollResolutionStatus.targetDeleted => ScrollOutcome.targetDeleted,
      ScrollResolutionStatus.targetOutOfRange => ScrollOutcome.targetOutOfRange,
      ScrollResolutionStatus.resolverRejected => ScrollOutcome.resolverRejected,
      ScrollResolutionStatus.unsupported => ScrollOutcome.unsupported,
    };
    final Map<String, Object?> diagnostics = <String, Object?>{
      ...?commandDiagnostics,
      ...?resolution.diagnostics,
    };
    return ScrollResult(
      commandId: context.commandId,
      outcome: outcome,
      requestedTarget: context.target,
      capturedTarget: null,
      achievedTarget: null,
      startRevision: commandStartRevision,
      endRevision: indexDelegate?.revision ?? resolution.dataRevision,
      resolutionMode: resolution.mode,
      finalLogicalPixels: _logicalPixelsFor(commandPosition),
      finalError: null,
      elapsed: Duration.zero,
      replanCount: 0,
      correctionCount: 0,
      diagnostics: diagnostics.isEmpty ? null : diagnostics,
    );
  }

  ScrollResult _resultFromDriver(
    ScrollCommandContext context,
    ScrollTarget target,
    _CapturedCommandTarget captured,
    ScrollResolution resolution,
    ScrollDriverResult result, {
    int? commandStartRevision,
    Map<String, Object?>? commandDiagnostics,
  }) {
    final Map<String, Object?> diagnostics = <String, Object?>{
      ...?commandDiagnostics,
      ...?resolution.diagnostics,
      ...?result.diagnostics,
    };
    return ScrollResult(
      commandId: context.commandId,
      outcome: result.outcome,
      requestedTarget: target,
      capturedTarget: resolution.target,
      achievedTarget: ScrollTarget.offset(result.finalLogicalPixels),
      startRevision:
          commandStartRevision ?? captured.revision ?? resolution.dataRevision,
      endRevision: indexDelegate?.revision ??
          result.endRevision ??
          resolution.dataRevision ??
          captured.revision,
      resolutionMode: resolution.mode,
      finalLogicalPixels: result.finalLogicalPixels,
      finalError: result.finalError,
      clampReason: result.clampReason,
      elapsed: Duration.zero,
      replanCount: result.replanCount,
      correctionCount: result.correctionCount,
      diagnostics: diagnostics.isEmpty ? null : diagnostics,
    );
  }

  Future<ScrollResult> _scheduleRestorationTerminal({
    required ScrollTarget requestedTarget,
    required ScrollTarget? capturedTarget,
    required ScrollOutcome outcome,
    required ScrollResolutionMode resolutionMode,
    required Map<String, Object?> diagnostics,
    required ScrollCommandOptions options,
  }) {
    final ScrollCommandOptions effective = defaultOptions.merge(options);
    return _scheduler
        .schedule(
          target: requestedTarget,
          policy: effective.conflictPolicy ?? ScrollConflictPolicy.replace,
          executionPolicy:
              effective.executionPolicy ?? ScrollExecutionPolicy.jump(),
          cancellationToken: effective.cancellationToken,
          execute: (ScrollCommandContext context) async {
            late final ScrollPosition commandPosition;
            if (!context.commit(() {
              commandPosition = position;
            })) {
              return _cancelledResult(context);
            }
            final ScrollResult? policyFailure = _resolutionPolicyFailure(
              context,
              effective.resolutionPolicy,
              commandPosition,
              resolutionMode: resolutionMode,
            );
            if (policyFailure != null) {
              return policyFailure;
            }
            if (!context.commit(() {
              _lastOrigin = ScrollEventOrigin.restoration;
              _scheduleSnapshot();
            })) {
              return _cancelledResult(context, commandPosition);
            }
            return ScrollResult(
              commandId: context.commandId,
              outcome: outcome,
              requestedTarget: requestedTarget,
              capturedTarget: capturedTarget,
              achievedTarget: null,
              startRevision: indexDelegate?.revision,
              endRevision: indexDelegate?.revision,
              resolutionMode: resolutionMode,
              finalLogicalPixels: _logicalPixelsFor(commandPosition),
              finalError: null,
              elapsed: Duration.zero,
              replanCount: 0,
              correctionCount: 0,
              diagnostics: Map<String, Object?>.unmodifiable(diagnostics),
            );
          },
        )
        .then(_normalizeAdaptedResult);
  }

  ScrollResult _decorateRestorationResult(
    ScrollResult result, {
    required ScrollTarget requestedTarget,
    required ScrollResolutionMode resolutionMode,
    required Map<String, Object?> diagnostics,
  }) {
    final Map<String, Object?> merged = <String, Object?>{
      ...diagnostics,
      ...?result.diagnostics,
    };
    return ScrollResult(
      commandId: result.commandId,
      outcome: result.outcome,
      requestedTarget: requestedTarget,
      capturedTarget: result.capturedTarget,
      achievedTarget: result.achievedTarget,
      startRevision: result.startRevision,
      endRevision: result.endRevision,
      resolutionMode: resolutionMode,
      finalLogicalPixels: result.finalLogicalPixels,
      finalError: result.finalError,
      clampReason: result.clampReason,
      elapsed: result.elapsed,
      replanCount: result.replanCount,
      correctionCount: result.correctionCount,
      diagnostics: Map<String, Object?>.unmodifiable(merged),
    );
  }

  _CapturedCommandTarget _captureTarget(ScrollTarget target) {
    final SeekoIndexDelegate<Object>? delegate = indexDelegate;
    if (target is! IndexScrollTarget ||
        target.tracking == IndexTracking.liveSlot) {
      return _CapturedCommandTarget(
        target: target,
        revision: delegate?.revision,
      );
    }
    if (delegate == null) {
      return _indexedSlivers.isEmpty
          ? _captureMountedIndex(target)
          : _captureCompositeIndex(target);
    }
    final int revision = delegate.revision;
    final SeekoKeyLookup<Object> lookup = delegate.captureIndex(target.index);
    return switch (lookup.status) {
      SeekoKeyLookupStatus.found => _CapturedCommandTarget(
          target: ScrollTarget.key(
            lookup.key ?? delegate.keyAt(lookup.index!),
          ),
          revision: revision,
        ),
      SeekoKeyLookupStatus.notLoaded => _CapturedCommandTarget(
          target: target,
          revision: revision,
          failure: ScrollOutcome.targetNotLoaded,
        ),
      SeekoKeyLookupStatus.absent => _CapturedCommandTarget(
          target: target,
          revision: revision,
          failure: ScrollOutcome.targetOutOfRange,
        ),
    };
  }

  _CapturedCommandTarget _captureMountedIndex(IndexScrollTarget target) {
    if (_mountedRegistryDirty) {
      return _CapturedCommandTarget(
        target: target,
        revision: null,
        failure: ScrollOutcome.targetNotLoaded,
      );
    }
    final BuildContext? context = _mountedIndexes[target.index];
    if (context == null) {
      return _CapturedCommandTarget(
        target: target,
        revision: null,
        failure: _mountedTargets.values.any(
          (_MountedTargetRecord record) => record.index != null,
        )
            ? ScrollOutcome.targetNotLoaded
            : ScrollOutcome.unsupported,
      );
    }
    final Object? key = _mountedTargets[context]?.key;
    if (key == null) {
      return _CapturedCommandTarget(
        target: target,
        revision: null,
        failure: ScrollOutcome.unsupported,
      );
    }
    return _CapturedCommandTarget(
      target: ScrollTarget.key(key),
      revision: null,
    );
  }

  _CapturedCommandTarget _captureCompositeIndex(IndexScrollTarget target) {
    final _CompositeIndexedLocation? location =
        _compositeLocationForIndex(target.index);
    if (location == null) {
      return _CapturedCommandTarget(
        target: target,
        revision: null,
        failure: _compositeItemCountKnown
            ? ScrollOutcome.targetOutOfRange
            : ScrollOutcome.targetNotLoaded,
      );
    }
    final SeekoKeyLookup<Object> lookup =
        location.sliver.indexDelegate.captureIndex(location.localIndex);
    final int revision = location.sliver.indexDelegate.revision;
    return switch (lookup.status) {
      SeekoKeyLookupStatus.found => _CapturedCommandTarget(
          target: ScrollTarget.key(
            lookup.key ??
                location.sliver.indexDelegate.keyAt(location.localIndex),
          ),
          revision: revision,
        ),
      SeekoKeyLookupStatus.notLoaded => _CapturedCommandTarget(
          target: target,
          revision: revision,
          failure: ScrollOutcome.targetNotLoaded,
        ),
      SeekoKeyLookupStatus.absent => _CapturedCommandTarget(
          target: target,
          revision: revision,
          failure: ScrollOutcome.targetOutOfRange,
        ),
    };
  }

  ScrollResult _captureFailureResult(
    ScrollCommandContext context,
    _CapturedCommandTarget captured,
    ScrollPosition commandPosition, {
    int? commandStartRevision,
    Map<String, Object?>? commandDiagnostics,
  }) {
    return ScrollResult(
      commandId: context.commandId,
      outcome: captured.failure!,
      requestedTarget: context.target,
      capturedTarget: null,
      achievedTarget: null,
      startRevision: commandStartRevision ?? captured.revision,
      endRevision: indexDelegate?.revision ?? captured.revision,
      resolutionMode: _resultResolutionMode,
      finalLogicalPixels: _logicalPixelsFor(commandPosition),
      finalError: null,
      elapsed: Duration.zero,
      replanCount: 0,
      correctionCount: 0,
      diagnostics:
          commandDiagnostics?.isEmpty == true ? null : commandDiagnostics,
    );
  }

  void _handleBindingChanged() {
    final ScrollPosition? next = _binding?.position;
    if (identical(next, _adaptedPosition)) {
      return;
    }
    final ScrollPosition? previous = _adaptedPosition;
    if (previous != null) {
      _scheduler.cancelAll(ScrollStopReason.detached);
      previous.removeListener(_handlePositionChanged);
      previous.isScrollingNotifier.removeListener(_scheduleSnapshot);
    }
    _adaptedPosition = next;
    if (next == null) {
      if (!_disposed) {
        _state.value = const ScrollSnapshot.detached();
      }
      return;
    }
    next.addListener(_handlePositionChanged);
    next.isScrollingNotifier.addListener(_scheduleSnapshot);
    _scheduleSnapshot();
  }

  Future<ScrollResult> jumpBy(
    double delta, {
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    if (!delta.isFinite) {
      throw ArgumentError.value(delta, 'delta', 'must be finite');
    }
    _requireAttached();
    return jumpToTarget(ScrollTarget.offset(_logicalPixels + delta),
        options: options);
  }

  Future<ScrollResult> animateBy(
    double delta, {
    ScrollMotion motion = const ScrollMotion.adaptive(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    if (!delta.isFinite) {
      throw ArgumentError.value(delta, 'delta', 'must be finite');
    }
    _requireAttached();
    return animateToTarget(
      ScrollTarget.offset(_logicalPixels + delta),
      motion: motion,
      options: options,
    );
  }

  void stop({ScrollStopReason reason = ScrollStopReason.requested}) {
    _invalidatePendingSnap();
    _scheduler.cancelAll(reason);
    if (hasClients) {
      final ScrollPosition outer = position;
      final ScrollPosition? inner = _nestedInnerFor(outer);
      if (inner == null) {
        outer.jumpTo(outer.pixels);
      } else if (_geometryFor(inner).physicalToLogical(inner.pixels) <=
          precisionErrorTolerance) {
        outer.jumpTo(outer.pixels);
      } else {
        inner.jumpTo(inner.pixels);
      }
    }
  }

  void registerMountedTarget(
    BuildContext context, {
    Object? key,
    int? index,
  }) {
    if (index != null) {
      RangeError.checkNotNegative(index, 'index');
    }
    final _MountedTargetRecord? previous = _mountedTargets[context];
    _mountedTargets[context] = _MountedTargetRecord(key: key, index: index);
    if (previous?.key != key || previous?.index != index) {
      _markMountedRegistryDirty();
    }
    _scheduleSnapshot();
  }

  void unregisterMountedTarget(
    BuildContext context, {
    Object? key,
    int? index,
  }) {
    final _MountedTargetRecord? record = _mountedTargets[context];
    if (record == null ||
        (key != null && record.key != key) ||
        (index != null && record.index != index)) {
      return;
    }
    _mountedTargets.remove(context);
    if (record.key != null || record.index != null) {
      _markMountedRegistryDirty();
    }
    _scheduleSnapshot();
  }

  void _markMountedRegistryDirty() {
    if (_mountedRegistryDirty || _disposed) {
      return;
    }
    _mountedRegistryDirty = true;
    _mountedRegistryCommit = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _commitMountedRegistry();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _commitMountedRegistry() {
    final Completer<void>? commit = _mountedRegistryCommit;
    if (_disposed) {
      _mountedRegistryDirty = false;
      if (commit != null && !commit.isCompleted) {
        commit.complete();
      }
      return;
    }
    final Map<Object, BuildContext> resolvedKeys = <Object, BuildContext>{};
    final Set<Object> duplicateKeys = <Object>{};
    final Map<int, BuildContext> resolved = <int, BuildContext>{};
    final Set<int> duplicates = <int>{};
    for (final MapEntry<BuildContext, _MountedTargetRecord> entry
        in _mountedTargets.entries) {
      final Object? targetKey = entry.value.key;
      if (targetKey != null && !duplicateKeys.contains(targetKey)) {
        final BuildContext? previous = resolvedKeys[targetKey];
        if (previous == null) {
          resolvedKeys[targetKey] = entry.key;
        } else if (!identical(previous, entry.key)) {
          resolvedKeys.remove(targetKey);
          duplicateKeys.add(targetKey);
        }
      }
      final int? targetIndex = entry.value.index;
      if (targetIndex == null || duplicates.contains(targetIndex)) {
        continue;
      }
      final BuildContext? previous = resolved[targetIndex];
      if (previous == null) {
        resolved[targetIndex] = entry.key;
      } else if (!identical(previous, entry.key)) {
        resolved.remove(targetIndex);
        duplicates.add(targetIndex);
      }
    }
    _mountedRegistryDirty = false;
    _mountedRegistryCommit = null;
    StateError? duplicateError;
    if (duplicateKeys.isNotEmpty) {
      final List<Object> values = duplicateKeys.toList(growable: false);
      if (values.length == 1) {
        duplicateError =
            StateError('Duplicate mounted Seeko key: ${values.single}.');
      } else {
        duplicateError = StateError('Duplicate mounted Seeko keys: $values.');
      }
    }
    if (duplicates.isNotEmpty) {
      final List<int> sorted = duplicates.toList()..sort();
      final String message = sorted.length == 1
          ? 'Duplicate mounted Seeko index: ${sorted.single}.'
          : 'Duplicate mounted Seeko indexes: $sorted.';
      duplicateError = duplicateError == null
          ? StateError(message)
          : StateError('${duplicateError.message} $message');
    }
    if (duplicateError != null) {
      if (commit != null && !commit.isCompleted) {
        commit.completeError(duplicateError, StackTrace.current);
      } else {
        throw duplicateError;
      }
      return;
    }
    _mountedKeys
      ..clear()
      ..addAll(resolvedKeys);
    _mountedIndexes
      ..clear()
      ..addAll(resolved);
    if (commit != null && !commit.isCompleted) {
      commit.complete();
    }
  }

  void _beginProgrammatic(
    int commandId, {
    required bool lockUserInteraction,
    ScrollEventOrigin origin = ScrollEventOrigin.programmatic,
  }) {
    if (_activeSnapGeneration == null) {
      _invalidatePendingSnap();
    } else {
      _snapEligible = false;
    }
    _activeCommandId = commandId;
    _programmatic = true;
    _activeProgrammaticOrigin = origin;
    _lastOrigin = origin;
    final ScrollPosition? current = hasClients ? position : null;
    if (current is _SeekoScrollPosition) {
      current.userInteractionLocked = lockUserInteraction;
    }
    _scheduleSnapshot();
  }

  void _endProgrammatic() {
    final ScrollPosition? current = hasClients ? position : null;
    if (current is _SeekoScrollPosition) {
      current.userInteractionLocked = false;
    }
    _activeCommandId = null;
    _programmatic = false;
    _scheduleSnapshot();
  }

  void _endProgrammaticFor(int? commandId) {
    if (commandId == null || commandId != _activeCommandId) {
      return;
    }
    _endProgrammatic();
  }

  FutureOr<BuildContext?> _mountedContextFor(ScrollTarget target) {
    return switch (target) {
      MountedScrollTarget(:final BuildContext context) => context,
      KeyScrollTarget(:final Object key) when _mountedRegistryDirty =>
        _mountedKeyAfterCommit(key),
      KeyScrollTarget(:final Object key) => _mountedKeys[key],
      IndexScrollTarget(:final int index) when _mountedRegistryDirty =>
        _mountedIndexAfterCommit(index),
      IndexScrollTarget(:final int index) => _mountedIndexes[index],
      _ => null,
    };
  }

  Future<BuildContext?> _mountedKeyAfterCommit(Object key) async {
    await _mountedRegistryCommit?.future;
    return _disposed ? null : _mountedKeys[key];
  }

  Future<BuildContext?> _mountedIndexAfterCommit(int index) async {
    await _mountedRegistryCommit?.future;
    return _disposed ? null : _mountedIndexes[index];
  }

  bool _hasRegistryFor(ScrollTarget target) => switch (target) {
        KeyScrollTarget() => _mountedKeys.isNotEmpty,
        IndexScrollTarget() => _mountedIndexes.isNotEmpty,
        _ => false,
      };

  void _markUserSnapEligible() {
    if (snapConfiguration == null || _disposed) {
      return;
    }
    _cancelPendingSnapResolver();
    _snapGeneration += 1;
    _snapEligible = true;
  }

  void _invalidatePendingSnap() {
    if (snapConfiguration == null) {
      return;
    }
    _cancelPendingSnapResolver();
    _snapGeneration += 1;
    _snapEligible = false;
  }

  void _cancelPendingSnapResolver() {
    final Completer<void>? cancellation = _snapResolverCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  void _scheduleAutomaticSnap() {
    if (snapConfiguration == null ||
        isAdapted ||
        !_snapEligible ||
        _snapScheduled ||
        _activeSnapGeneration != null ||
        _programmatic ||
        _disposed) {
      return;
    }
    _snapScheduled = true;
    final int generation = _snapGeneration;
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      if (_disposed ||
          generation != _snapGeneration ||
          !_snapEligible ||
          !hasClients ||
          position.isScrollingNotifier.value ||
          _applyingSyncTransactionId != null ||
          _programmatic) {
        return;
      }
      _snapEligible = false;
      unawaited(_runAutomaticSnap(generation));
    });
  }

  Future<void> _runAutomaticSnap(int generation) async {
    try {
      await _executeSnap(generation);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'seeko',
          context: ErrorDescription('while resolving an automatic snap'),
        ),
      );
    }
  }

  Future<ScrollResult?> _executeSnap(int generation) async {
    final SeekoSnapConfiguration? configuration = snapConfiguration;
    if (configuration == null ||
        _disposed ||
        !hasClients ||
        generation != _snapGeneration) {
      return null;
    }
    _activeSnapGeneration = generation;
    final Completer<void> resolverCancellation = Completer<void>();
    _snapResolverCancellation = resolverCancellation;
    try {
      final Future<_ResolvedSnapTarget> resolvedTarget =
          Future<ScrollTarget?>.sync(
        () => configuration.resolver.resolve(state.value),
      ).then<_ResolvedSnapTarget>(_ResolvedSnapTarget.new);
      final Object resolution = await Future.any<Object>(<Future<Object>>[
        resolvedTarget,
        resolverCancellation.future.then<Object>(
          (_) => _cancelledSnapResolution,
        ),
      ]);
      if (identical(resolution, _cancelledSnapResolution)) {
        return null;
      }
      final ScrollTarget? target = (resolution as _ResolvedSnapTarget).target;
      if (target == null ||
          _disposed ||
          !hasClients ||
          generation != _snapGeneration) {
        return null;
      }
      if (configuration.motion.kind == ScrollMotionKind.instant) {
        return await jumpToTarget(
          target,
          placement: configuration.placement,
          options: configuration.options,
        );
      }
      return await animateToTarget(
        target,
        placement: configuration.placement,
        motion: configuration.motion,
        options: configuration.options,
      );
    } finally {
      if (identical(_snapResolverCancellation, resolverCancellation)) {
        _snapResolverCancellation = null;
      }
      if (_activeSnapGeneration == generation) {
        _activeSnapGeneration = null;
      }
    }
  }

  void _handleActivityChanged(ScrollActivity? activity) {
    if (activity is HoldScrollActivity || activity is DragScrollActivity) {
      _markUserSnapEligible();
      _lastOrigin = ScrollEventOrigin.user;
      _scheduler.cancelActive(ScrollStopReason.userInteraction);
      _programmatic = false;
    }
    if (hasClients && position.hasContentDimensions) {
      _syncMember?._handleActivity(
        _phaseFor(position, activity),
        _originFor(activity),
      );
    }
    _scheduleSnapshot();
    if (activity is IdleScrollActivity) {
      _scheduleAutomaticSnap();
    }
  }

  void _handleMetricsChanged() {
    if (_disposed) {
      return;
    }
    _syncMember?._handleMetricsChanged();
    _scheduleSnapshot();
  }

  void _handleUserScrollRequest() {
    _markUserSnapEligible();
    _lastOrigin = ScrollEventOrigin.user;
    _scheduler.cancelActive(ScrollStopReason.userInteraction);
    _programmatic = false;
    _scheduleSnapshot();
  }

  void _handlePositionChanged() {
    if (!_hasUnambiguousPosition) {
      return;
    }
    if (isAdapted && !_programmatic) {
      _lastOrigin = ScrollEventOrigin.external;
    }
    final ScrollPosition current = position;
    if (current.hasContentDimensions) {
      final ScrollActivity? activity =
          current is _SeekoScrollPosition ? current.currentActivity : null;
      _syncMember?._handlePosition(
        logicalPixels: _logicalPixelsFor(current),
        maxScrollExtent: _logicalExtentFor(current),
        viewportExtent: _viewportExtentFor(current),
        phase: _phaseFor(current, activity),
        origin: _originFor(activity),
        applyingTransactionId: _syncTransactionIdFor(activity),
      );
    }
    _emitRawEvent();
    _scheduleSnapshot();
    if (!current.isScrollingNotifier.value) {
      _scheduleAutomaticSnap();
    }
  }

  void _emitRawEvent() {
    final StreamController<ScrollRawEvent>? controller = _rawEventController;
    if (controller == null ||
        !controller.hasListener ||
        !hasClients ||
        !_hasUnambiguousPosition) {
      return;
    }
    final ScrollPosition current = position;
    if (!current.hasContentDimensions) {
      return;
    }
    final ScrollActivity? activity =
        current is _SeekoScrollPosition ? current.currentActivity : null;
    final ScrollPhase phase = _phaseFor(current, activity);
    final int? syncTransactionId =
        _syncTransactionIdFor(activity) ?? _pendingSyncTransactionId;
    controller.add(
      ScrollRawEvent(
        sequence: ++_rawSequence,
        pixels: _logicalPixelsFor(current),
        velocity: activity?.velocity ?? 0,
        phase: phase,
        origin: _originFor(activity),
        commandId: _activeCommandId,
        syncTransactionId: syncTransactionId,
      ),
    );
  }

  void _scheduleSnapshot() {
    if (_disposed || _snapshotScheduled) {
      return;
    }
    _snapshotScheduled = true;
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _snapshotScheduled = false;
      _publishSnapshot();
    });
  }

  void _publishSnapshot() {
    if (_disposed ||
        !hasClients ||
        !_hasUnambiguousPosition ||
        !position.hasContentDimensions) {
      return;
    }
    final ScrollPosition current = position;
    final double logical = _logicalPixelsFor(current);
    final double extent = _logicalExtentFor(current);
    final double viewportExtent = _viewportExtentFor(current);
    final ScrollActivity? activity =
        current is _SeekoScrollPosition ? current.currentActivity : null;
    final ScrollPhase phase = _phaseFor(current, activity);
    final int? syncTransactionId =
        _syncTransactionIdFor(activity) ?? _pendingSyncTransactionId;
    final List<ScrollVisibleTarget> visibleTargets =
        _collectVisibleTargets(current);
    final ScrollPosition anchorPosition = _nestedInnerFor(current) ?? current;
    final VisibleRegion? effectiveVisibleRegion =
        _visibleRegionFor(anchorPosition);
    _state.value = ScrollSnapshot(
      pixels: logical,
      minScrollExtent: 0,
      maxScrollExtent: extent,
      viewportExtent: viewportExtent,
      progress: extent == 0 ? null : logical / extent,
      axis: current.axis,
      axisDirection: current.axisDirection,
      userScrollDirection: current.userScrollDirection,
      velocity: activity?.velocity ?? 0,
      phase: phase,
      origin: _originFor(activity),
      atLeadingEdge: logical <= 0.5,
      atTrailingEdge: (extent - logical).abs() <= 0.5,
      visibleTargets: visibleTargets,
      anchor: _anchorFor(
        visibleTargets,
        viewportExtent,
        visibleRegion: effectiveVisibleRegion,
      ),
      activeCommandId: _activeCommandId,
      synchronized: syncTransactionId != null,
      syncTransactionId: syncTransactionId,
      dataRevision: _indexedDataRevision,
      effectiveViewportIntervals:
          effectiveVisibleRegion?.intervals ?? const <LogicalInterval>[],
      extent: _indexedExtentSnapshot,
    );
    _pendingSyncTransactionId = null;
  }

  ScrollPhase _phaseFor(
    ScrollPosition current,
    ScrollActivity? activity,
  ) {
    if (_programmatic) {
      return ScrollPhase.programmatic;
    }
    return switch (activity) {
      DragScrollActivity() => ScrollPhase.drag,
      BallisticScrollActivity() => ScrollPhase.ballistic,
      HoldScrollActivity() => ScrollPhase.held,
      DrivenScrollActivity() => ScrollPhase.programmatic,
      _SeekoNaturalSyncActivity() => ScrollPhase.programmatic,
      _ when isAdapted && current.isScrollingNotifier.value =>
        ScrollPhase.scrolling,
      _ => ScrollPhase.idle,
    };
  }

  ScrollEventOrigin _originFor(ScrollActivity? activity) {
    if (_programmatic) {
      return _activeProgrammaticOrigin;
    }
    if (activity is DrivenScrollActivity) {
      return _lastOrigin == ScrollEventOrigin.restoration
          ? ScrollEventOrigin.restoration
          : ScrollEventOrigin.programmatic;
    }
    if (activity is _SeekoNaturalSyncActivity) {
      return ScrollEventOrigin.synchronized;
    }
    if (activity is DragScrollActivity || activity is HoldScrollActivity) {
      return ScrollEventOrigin.user;
    }
    return _lastOrigin;
  }

  int? _syncTransactionIdFor(ScrollActivity? activity) =>
      _applyingSyncTransactionId ??
      (activity is _SeekoNaturalSyncActivity ? activity.transactionId : null);

  List<ScrollVisibleTarget> _collectVisibleTargets(ScrollPosition current) {
    if (_mountedTargets.isEmpty && _indexedSlivers.isEmpty) {
      return const <ScrollVisibleTarget>[];
    }
    final VisibleRegion? outerVisibleRegion = _visibleRegionFor(current);
    if (outerVisibleRegion == null) {
      return const <ScrollVisibleTarget>[];
    }
    final ScrollPosition? nestedInner = _nestedInnerFor(current);
    final VisibleRegion? innerVisibleRegion =
        nestedInner == null ? null : _visibleRegionFor(nestedInner);
    if (nestedInner != null && innerVisibleRegion == null) {
      return const <ScrollVisibleTarget>[];
    }
    final List<ScrollVisibleTarget> result = <ScrollVisibleTarget>[];
    int? globalIndexBase = 0;
    for (final _SeekoIndexedSliverHost sliver in _indexedSlivers) {
      result.addAll(
        sliver.collectVisibleTargets(
          innerVisibleRegion ?? outerVisibleRegion,
          globalIndexBase: globalIndexBase,
        ),
      );
      final int? itemCount = sliver.indexDelegate.itemCount;
      globalIndexBase = globalIndexBase == null || itemCount == null
          ? null
          : globalIndexBase + itemCount;
    }
    final Set<(Object?, int?)> indexedIdentities = result
        .map(
          (ScrollVisibleTarget target) => (target.key, target.index),
        )
        .toSet();
    for (final MapEntry<BuildContext, _MountedTargetRecord> entry
        in _mountedTargets.entries) {
      if (indexedIdentities.contains((entry.value.key, entry.value.index))) {
        continue;
      }
      final RenderObject? object = entry.key.findRenderObject();
      if (object == null || !object.attached) {
        continue;
      }
      final RenderAbstractViewport? viewport =
          RenderAbstractViewport.maybeOf(object);
      if (viewport == null) {
        continue;
      }
      final ScrollableState? targetScrollable = Scrollable.maybeOf(
        entry.key,
        axis: current.axis,
      );
      final ScrollPosition? targetPosition = targetScrollable?.position;
      if (targetPosition == null ||
          (!identical(targetPosition, current) &&
              !identical(targetPosition, nestedInner))) {
        continue;
      }
      final VisibleRegion targetVisibleRegion =
          identical(targetPosition, nestedInner)
              ? innerVisibleRegion!
              : outerVisibleRegion;
      final Rect rect = MatrixUtils.transformRect(
        object.getTransformTo(viewport),
        object.paintBounds,
      );
      final double extent =
          targetPosition.axis == Axis.horizontal ? rect.width : rect.height;
      if (!extent.isFinite || extent <= 0) {
        continue;
      }
      final double leading = switch (targetPosition.axisDirection) {
        AxisDirection.down => rect.top,
        AxisDirection.up => targetPosition.viewportDimension - rect.bottom,
        AxisDirection.right => rect.left,
        AxisDirection.left => targetPosition.viewportDimension - rect.right,
      };
      final double trailing = leading + extent;
      final double visibleExtent = _visibleExtentForInterval(
        leading: leading,
        trailing: trailing,
        visibleRegion: targetVisibleRegion,
      );
      if (visibleExtent <= 0) {
        continue;
      }
      result.add(
        ScrollVisibleTarget(
          key: entry.value.key,
          index: entry.value.index,
          leadingPixels: leading,
          trailingPixels: trailing,
          leadingViewportFraction: leading / targetPosition.viewportDimension,
          trailingViewportFraction: trailing / targetPosition.viewportDimension,
          visibleFraction: (visibleExtent / extent).clamp(0, 1),
        ),
      );
    }
    if (result.isEmpty) {
      return const <ScrollVisibleTarget>[];
    }
    result.sort(
      (ScrollVisibleTarget a, ScrollVisibleTarget b) =>
          a.leadingPixels.compareTo(b.leadingPixels),
    );
    return List<ScrollVisibleTarget>.unmodifiable(result);
  }

  VisibleRegion? _visibleRegionFor(ScrollPosition targetPosition) {
    try {
      return obstructionResolver?.call(
            ScrollViewportGeometry(
              viewportExtent: targetPosition.viewportDimension,
              axis: targetPosition.axis,
              axisDirection: targetPosition.axisDirection,
            ),
          ) ??
          VisibleRegion.fromIntervals(<LogicalInterval>[
            LogicalInterval(0, targetPosition.viewportDimension),
          ]);
    } on Object {
      return null;
    }
  }

  ScrollSemanticAnchor? _anchorFor(
    List<ScrollVisibleTarget> targets,
    double viewportExtent, {
    VisibleRegion? visibleRegion,
  }) {
    if (targets.isEmpty || viewportExtent <= 0) {
      return null;
    }
    final LogicalInterval viewport =
        visibleRegion?.largestInterval ?? LogicalInterval(0, viewportExtent);
    ScrollVisibleTarget target = targets.first;
    for (final ScrollVisibleTarget candidate in targets) {
      if (math.min(candidate.trailingPixels, viewport.end) >
          math.max(candidate.leadingPixels, viewport.start)) {
        target = candidate;
        break;
      }
    }
    final double extent = target.trailingPixels - target.leadingPixels;
    if (extent <= 0 || viewport.extent <= 0) {
      return null;
    }
    final double visibleLeading = math
        .max(target.leadingPixels, viewport.start)
        .clamp(viewport.start, viewport.end)
        .toDouble();
    return ScrollSemanticAnchor(
      key: target.key,
      index: target.index,
      itemAnchor:
          ((visibleLeading - target.leadingPixels) / extent).clamp(0, 1),
      viewportAnchor:
          ((visibleLeading - viewport.start) / viewport.extent).clamp(0, 1),
      logicalOffset: 0,
    );
  }

  double? _semanticSyncPixels(ScrollSemanticAnchor anchor) {
    if (_disposed || !hasClients || !position.hasContentDimensions) {
      return null;
    }
    final ScrollTarget? target = anchor.key != null
        ? ScrollTarget.key(anchor.key!)
        : anchor.index != null
            ? ScrollTarget.index(anchor.index!)
            : null;
    if (target == null) {
      return null;
    }
    final ({
      LogicalInterval interval,
      ScrollPosition targetPosition
    })? targetGeometry = _semanticTargetGeometry(target);
    if (targetGeometry == null) {
      return null;
    }
    final VisibleRegion? visibleRegion =
        _visibleRegionFor(targetGeometry.targetPosition);
    if (visibleRegion == null) {
      return null;
    }
    try {
      final ScrollPlacementResolution resolution = resolveScrollPlacement(
        placement: ScrollPlacement.exact(
          targetAnchor: anchor.itemAnchor,
          viewportAnchor: anchor.viewportAnchor,
          offset: anchor.logicalOffset,
        ),
        target: targetGeometry.interval,
        visibleRegion: visibleRegion,
        currentPixels: _logicalPixelsFor(position),
      );
      return resolution.pixels.clamp(0, _logicalExtentFor(position)).toDouble();
    } on Object {
      return null;
    }
  }

  LogicalInterval? _semanticTargetInterval(ScrollTarget target) =>
      _semanticTargetGeometry(target)?.interval;

  ({LogicalInterval interval, ScrollPosition targetPosition})?
      _semanticTargetGeometry(ScrollTarget target) {
    if (_disposed || !hasClients || !position.hasContentDimensions) {
      return null;
    }
    final ScrollPosition current = position;
    final ScrollPosition? nestedInner = _nestedInnerFor(current);
    ScrollPosition targetPosition = current;
    late final LogicalInterval targetInterval;
    final SeekoIndexedTargetResolution? indexed = _resolveIndexedTarget(
      target,
      selectMotionTarget: false,
    );
    if (indexed?.status == ScrollResolutionStatus.resolved) {
      final LogicalInterval indexedInterval = indexed!.targetInterval!;
      if (nestedInner == null) {
        targetInterval = indexedInterval;
      } else {
        targetPosition = nestedInner;
        final double outerExtent = _geometryFor(current).extent;
        targetInterval = LogicalInterval(
          outerExtent + indexedInterval.start,
          outerExtent + indexedInterval.end,
        );
      }
    } else {
      if (_mountedRegistryDirty) {
        return null;
      }
      final BuildContext? context = switch (target) {
        KeyScrollTarget(:final Object key) => _mountedKeys[key],
        IndexScrollTarget(:final int index) => _mountedIndexes[index],
        _ => null,
      };
      final RenderObject? object = context?.findRenderObject();
      if (context == null || object == null || !object.attached) {
        return null;
      }
      final RenderAbstractViewport? viewport =
          RenderAbstractViewport.maybeOf(object);
      final ScrollableState? scrollable = Scrollable.maybeOf(
        context,
        axis: current.axis,
      );
      if (viewport == null ||
          scrollable == null ||
          (!identical(scrollable.position, current) &&
              !identical(scrollable.position, nestedInner))) {
        return null;
      }
      targetPosition = scrollable.position;
      final Rect rect = MatrixUtils.transformRect(
        object.getTransformTo(viewport),
        object.paintBounds,
      );
      final double extent =
          targetPosition.axis == Axis.horizontal ? rect.width : rect.height;
      final double leading = switch (targetPosition.axisDirection) {
        AxisDirection.down => rect.top,
        AxisDirection.up => targetPosition.viewportDimension - rect.bottom,
        AxisDirection.right => rect.left,
        AxisDirection.left => targetPosition.viewportDimension - rect.right,
      };
      final double localStart = _geometryFor(targetPosition)
              .physicalToLogical(targetPosition.pixels) +
          leading;
      final double start = identical(targetPosition, nestedInner)
          ? _geometryFor(current).extent + localStart
          : localStart;
      targetInterval = LogicalInterval(start, start + extent);
    }
    return (interval: targetInterval, targetPosition: targetPosition);
  }

  double get _logicalPixels => _logicalPixelsFor(position);

  double _logicalPixelsFor(ScrollPosition commandPosition) {
    final double outer =
        _geometryFor(commandPosition).physicalToLogical(commandPosition.pixels);
    final ScrollPosition? inner = _nestedInnerFor(commandPosition);
    if (inner == null) {
      return outer;
    }
    return outer + _geometryFor(inner).physicalToLogical(inner.pixels);
  }

  double _logicalExtentFor(ScrollPosition commandPosition) {
    final double outer = _geometryFor(commandPosition).extent;
    final ScrollPosition? inner = _nestedInnerFor(commandPosition);
    if (inner == null) {
      return outer;
    }
    final double outerLogical =
        _geometryFor(commandPosition).physicalToLogical(commandPosition.pixels);
    return outerLogical + _geometryFor(inner).extent;
  }

  double _viewportExtentFor(ScrollPosition commandPosition) {
    return commandPosition.viewportDimension;
  }

  ScrollPosition? _nestedInnerFor(ScrollPosition commandPosition) {
    final ScrollPosition? inner = _nestedInnerPosition;
    if (_nestedBindingOwner == null ||
        _nestedBindingAmbiguous ||
        inner == null ||
        !identical(commandPosition, position) ||
        !commandPosition.hasContentDimensions ||
        !inner.hasContentDimensions ||
        commandPosition.axis != inner.axis ||
        commandPosition.axisDirection != inner.axisDirection) {
      return null;
    }
    return inner;
  }

  bool get _hasUnambiguousPosition => isAdapted || super.positions.length == 1;

  LogicalAxisGeometry get _geometry => LogicalAxisGeometry(
        axisDirection: position.axisDirection,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
      );

  LogicalAxisGeometry _geometryFor(ScrollPosition commandPosition) =>
      LogicalAxisGeometry(
        axisDirection: commandPosition.axisDirection,
        minScrollExtent: commandPosition.minScrollExtent,
        maxScrollExtent: commandPosition.maxScrollExtent,
      );

  bool _disableAnimationsFor(ScrollPosition commandPosition) {
    final BuildContext? context = commandPosition.context.notificationContext;
    return context != null &&
        MediaQuery.maybeDisableAnimationsOf(context) == true;
  }

  ScrollResult? _resolutionPolicyFailure(
    ScrollCommandContext context,
    ScrollResolutionPolicy policy,
    ScrollPosition commandPosition, {
    ScrollResolutionMode? resolutionMode,
  }) {
    final ScrollResolutionMode mode = resolutionMode ?? _resultResolutionMode;
    final bool allowed = !policy.requireExact &&
        switch (mode) {
          ScrollResolutionMode.exact => true,
          ScrollResolutionMode.estimated => policy.allowEstimated,
          ScrollResolutionMode.searched => policy.allowSearched,
          ScrollResolutionMode.fallback => policy.allowFallback,
        };
    if (allowed || mode == ScrollResolutionMode.exact) {
      return null;
    }
    return ScrollResult(
      commandId: context.commandId,
      outcome: ScrollOutcome.unsupported,
      requestedTarget: context.target,
      capturedTarget: null,
      achievedTarget: null,
      startRevision: null,
      endRevision: null,
      resolutionMode: mode,
      finalLogicalPixels: _logicalPixelsFor(commandPosition),
      finalError: null,
      elapsed: Duration.zero,
      replanCount: 0,
      correctionCount: 0,
      diagnostics: <String, Object?>{
        'resolutionPolicyRejected': mode.name,
      },
    );
  }

  ScrollResult _cancelledResult(
    ScrollCommandContext context, [
    ScrollPosition? commandPosition,
  ]) {
    final ScrollOutcome outcome = switch (context.cancellationToken.reason) {
      ScrollStopReason.userInteraction => ScrollOutcome.interruptedByUser,
      ScrollStopReason.superseded => ScrollOutcome.superseded,
      ScrollStopReason.timedOut => ScrollOutcome.timedOut,
      ScrollStopReason.detached => ScrollOutcome.detached,
      _ => ScrollOutcome.cancelled,
    };
    return ScrollResult(
      commandId: context.commandId,
      outcome: outcome,
      requestedTarget: context.target,
      capturedTarget: null,
      achievedTarget: null,
      startRevision: null,
      endRevision: null,
      resolutionMode: _resultResolutionMode,
      finalLogicalPixels:
          commandPosition == null ? null : _logicalPixelsFor(commandPosition),
      finalError: null,
      elapsed: Duration.zero,
      replanCount: 0,
      correctionCount: 0,
    );
  }

  void _requireAttached() {
    if (!hasClients) {
      throw StateError(
        'SeekoController is not attached to a Scrollable. '
        'Pass it to the native scrollable controller parameter first.',
      );
    }
  }

  ScrollResolutionMode get _resultResolutionMode =>
      isAdapted && !_exclusiveProgrammaticWrites
          ? ScrollResolutionMode.fallback
          : ScrollResolutionMode.exact;

  ScrollResult _normalizeAdaptedResult(ScrollResult result) {
    final ScrollResolutionMode resolutionMode = _resultResolutionMode;
    if (resolutionMode == ScrollResolutionMode.exact ||
        result.resolutionMode == resolutionMode) {
      return result;
    }
    return ScrollResult(
      commandId: result.commandId,
      outcome: result.outcome,
      requestedTarget: result.requestedTarget,
      capturedTarget: result.capturedTarget,
      achievedTarget: result.achievedTarget,
      startRevision: result.startRevision,
      endRevision: result.endRevision,
      resolutionMode: resolutionMode,
      finalLogicalPixels: result.finalLogicalPixels,
      finalError: result.finalError,
      clampReason: result.clampReason,
      elapsed: result.elapsed,
      replanCount: result.replanCount,
      correctionCount: result.correctionCount,
      diagnostics: result.diagnostics,
    );
  }

  bool _applySynchronizedLogicalPixels({
    required double logicalPixels,
    required int transactionId,
  }) {
    if (_disposed || !hasClients || !position.hasContentDimensions) {
      return false;
    }
    _invalidatePendingSnap();
    final ScrollPosition outer = position;
    final ScrollPosition? inner = _nestedInnerFor(outer);
    final double extent = _logicalExtentFor(outer);
    final double clamped = logicalPixels.clamp(0, extent).toDouble();
    if ((_logicalPixelsFor(outer) - clamped).abs() <= 1e-9) {
      return true;
    }
    _scheduler.cancelAll(ScrollStopReason.superseded);
    _programmatic = false;
    _lastOrigin = ScrollEventOrigin.synchronized;
    _applyingSyncTransactionId = transactionId;
    _pendingSyncTransactionId = transactionId;
    try {
      if (inner == null) {
        final LogicalAxisGeometry geometry = _geometryFor(outer);
        outer.jumpTo(geometry.logicalToPhysical(clamped));
      } else {
        final LogicalAxisGeometry outerGeometry = _geometryFor(outer);
        if (clamped <= outerGeometry.extent) {
          outer.jumpTo(outerGeometry.logicalToPhysical(clamped));
        } else {
          final LogicalAxisGeometry innerGeometry = _geometryFor(inner);
          inner.jumpTo(
            innerGeometry.logicalToPhysical(
              clamped - outerGeometry.extent,
            ),
          );
        }
      }
    } finally {
      _applyingSyncTransactionId = null;
    }
    return true;
  }

  bool _applyNaturalSynchronizedLogicalPixels({
    required double logicalPixels,
    required int transactionId,
    required Duration duration,
    required Curve curve,
    required NaturalSyncSnapBehavior snapBehavior,
  }) {
    if (_disposed || !hasClients || !position.hasContentDimensions) {
      return false;
    }
    _invalidatePendingSnap();
    final ScrollPosition current = position;
    if (current is! _SeekoScrollPosition) {
      return false;
    }
    final LogicalAxisGeometry geometry = _geometry;
    final double clamped = logicalPixels.clamp(0, geometry.extent);
    final double physical = geometry.logicalToPhysical(clamped);
    _scheduler.cancelAll(ScrollStopReason.superseded);
    _programmatic = false;
    _lastOrigin = ScrollEventOrigin.synchronized;
    _pendingSyncTransactionId = transactionId;
    current.animateNaturalSyncTo(
      physical,
      transactionId: transactionId,
      duration: duration,
      curve: curve,
      snapBehavior: snapBehavior,
    );
    return true;
  }

  @override
  void dispose() {
    _syncMember?._handleControllerDispose();
    _invalidatePendingSnap();
    _disposed = true;
    final ScrollPosition? nestedInner = _nestedInnerPosition;
    if (nestedInner != null) {
      nestedInner.removeListener(_handlePositionChanged);
      nestedInner.isScrollingNotifier.removeListener(_scheduleSnapshot);
    }
    _nestedBindingOwner = null;
    _nestedInnerPosition = null;
    _nestedBindingAmbiguous = false;
    _completeInitialTarget(
      outcome: ScrollOutcome.detached,
      dataRevision: indexDelegate?.revision,
      finalLogicalPixels: null,
    );
    if (!isAdapted) {
      for (final ScrollPosition current in positions.toList(growable: false)) {
        current.removeListener(_handlePositionChanged);
        current.isScrollingNotifier.removeListener(_scheduleSnapshot);
        if (current is _SeekoScrollPosition) {
          current.userInteractionLocked = false;
        }
      }
    }
    final ScrollPosition? adapted = _adaptedPosition;
    if (adapted != null) {
      adapted.removeListener(_handlePositionChanged);
      adapted.isScrollingNotifier.removeListener(_scheduleSnapshot);
    }
    final SeekoPositionBinding? binding = _binding;
    if (binding != null) {
      binding.removeListener(_handleBindingChanged);
      binding._release(_adaptedController!, this);
    }
    _scheduler.dispose();
    _state.dispose();
    unawaited(_rawEventController?.close());
    unawaited(_commandResultController?.close());
    _mountedKeys.clear();
    _mountedIndexes.clear();
    _mountedTargets.clear();
    _indexedSlivers.clear();
    _activeIndexedMotionSliver = null;
    final Completer<void>? mountedRegistryCommit = _mountedRegistryCommit;
    if (mountedRegistryCommit != null && !mountedRegistryCommit.isCompleted) {
      mountedRegistryCommit.complete();
    }
    super.dispose();
  }

  void _attachIndexedSliver(_SeekoIndexedSliverHost sliver) {
    if (_disposed) {
      throw StateError(
        'A SeekoIndexedSliver cannot attach to a disposed controller.',
      );
    }
    if (isAdapted) {
      throw StateError(
        'SeekoIndexedSliver requires a direct SeekoController.',
      );
    }
    if (_indexedSlivers.contains(sliver)) {
      return;
    }
    _indexedSlivers.add(sliver);
  }

  void _bindNestedScroll({
    required Object owner,
    required ScrollPosition? innerPosition,
    required bool ambiguous,
  }) {
    if (_disposed) {
      return;
    }
    if (isAdapted) {
      throw StateError(
        'SeekoNestedScrollBinding requires a direct SeekoController.',
      );
    }
    final Object? currentOwner = _nestedBindingOwner;
    if (currentOwner != null && !identical(currentOwner, owner)) {
      throw StateError(
        'A SeekoController can be claimed by only one '
        'SeekoNestedScrollBinding at a time.',
      );
    }
    _nestedBindingOwner = owner;
    final ScrollPosition? previous = _nestedInnerPosition;
    final bool changed = !identical(previous, innerPosition) ||
        _nestedBindingAmbiguous != ambiguous;
    if (!changed) {
      return;
    }
    if (previous != null) {
      previous.removeListener(_handlePositionChanged);
      previous.isScrollingNotifier.removeListener(_scheduleSnapshot);
    }
    if (previous != null && !identical(previous, innerPosition)) {
      _scheduler.cancelActive(ScrollStopReason.detached);
    }
    _nestedInnerPosition = innerPosition;
    _nestedBindingAmbiguous = ambiguous;
    if (innerPosition != null) {
      innerPosition.addListener(_handlePositionChanged);
      innerPosition.isScrollingNotifier.addListener(_scheduleSnapshot);
    }
    _syncMember?._handleMetricsChanged();
    _scheduleSnapshot();
  }

  void _unbindNestedScroll(Object owner) {
    if (!identical(_nestedBindingOwner, owner)) {
      return;
    }
    final ScrollPosition? inner = _nestedInnerPosition;
    if (inner != null) {
      inner.removeListener(_handlePositionChanged);
      inner.isScrollingNotifier.removeListener(_scheduleSnapshot);
    }
    _nestedBindingOwner = null;
    _nestedInnerPosition = null;
    _nestedBindingAmbiguous = false;
    _scheduler.cancelActive(ScrollStopReason.detached);
    _syncMember?._handleMetricsChanged();
    _scheduleSnapshot();
  }

  void _handleNestedScrollNotification(ScrollNotification notification) {
    if (_disposed || _nestedBindingOwner == null) {
      return;
    }
    final BuildContext? notificationContext = notification.context;
    final ScrollPosition? source = notificationContext == null
        ? null
        : Scrollable.maybeOf(
            notificationContext,
            axis: notification.metrics.axis,
          )?.position;
    if (source != null &&
        !identical(source, position) &&
        !identical(source, _nestedInnerPosition)) {
      return;
    }
    final bool userRequested = switch (notification) {
      ScrollStartNotification(:final DragStartDetails? dragDetails) =>
        dragDetails != null,
      UserScrollNotification(:final ScrollDirection direction) =>
        direction != ScrollDirection.idle,
      _ => false,
    };
    if (userRequested) {
      _handleUserScrollRequest();
    }
  }

  void _detachIndexedSliver(_SeekoIndexedSliverHost sliver) {
    _indexedSlivers.remove(sliver);
    if (identical(_activeIndexedMotionSliver, sliver)) {
      sliver.endWindowRebase();
      _activeIndexedMotionSliver = null;
    }
  }

  void _indexedSliverOriginChanged() {
    _indexedSlivers.sort(
      (_SeekoIndexedSliverHost a, _SeekoIndexedSliverHost b) =>
          a.globalScrollOrigin.compareTo(b.globalScrollOrigin),
    );
  }

  int? get _indexedDataRevision {
    if (_indexedSlivers.isEmpty) {
      return null;
    }
    final int revision = _indexedSlivers.first.indexDelegate.revision;
    for (final _SeekoIndexedSliverHost sliver in _indexedSlivers.skip(1)) {
      if (sliver.indexDelegate.revision != revision) {
        return null;
      }
    }
    return revision;
  }

  ScrollExtentSnapshot? get _indexedExtentSnapshot {
    if (_indexedSlivers.isEmpty) {
      return null;
    }
    var itemCount = 0;
    var measuredItemCount = 0;
    var measuredExtent = 0.0;
    var estimatedExtent = 0.0;
    var reportedSourceCount = 0;
    for (final _SeekoIndexedSliverHost sliver in _indexedSlivers) {
      final _SeekoIndexedExtentSnapshot? extent = sliver.extentSnapshot;
      if (extent == null) {
        continue;
      }
      reportedSourceCount += 1;
      itemCount += extent.itemCount;
      measuredItemCount += extent.measuredItemCount;
      measuredExtent += extent.measuredExtent;
      estimatedExtent += extent.estimatedExtent;
    }
    if (reportedSourceCount == 0) {
      return null;
    }
    return ScrollExtentSnapshot(
      itemCount: itemCount,
      measuredItemCount: measuredItemCount,
      measuredExtent: measuredExtent,
      estimatedExtent: estimatedExtent,
      sourceCount: _indexedSlivers.length,
      reportedSourceCount: reportedSourceCount,
    );
  }

  ScrollTarget? get _pendingInitialTarget =>
      _initialTargetConsumed ? null : initialTarget;

  void _completeInitialTarget({
    required ScrollOutcome outcome,
    required int? dataRevision,
    required double? finalLogicalPixels,
  }) {
    final ScrollTarget? target = initialTarget;
    final Completer<SeekoInitialTargetResult>? completer =
        _initialTargetCompleter;
    if (target == null || completer == null || completer.isCompleted) {
      return;
    }
    _initialTargetConsumed = true;
    completer.complete(
      SeekoInitialTargetResult._(
        target: target,
        placement: initialPlacement,
        outcome: outcome,
        dataRevision: dataRevision,
        finalLogicalPixels: finalLogicalPixels,
      ),
    );
  }
}

double _visibleExtentForInterval({
  required double leading,
  required double trailing,
  required VisibleRegion visibleRegion,
}) {
  var visibleExtent = 0.0;
  for (final LogicalInterval interval in visibleRegion.intervals) {
    final double overlapStart =
        leading > interval.start ? leading : interval.start;
    final double overlapEnd = trailing < interval.end ? trailing : interval.end;
    if (overlapEnd > overlapStart) {
      visibleExtent += overlapEnd - overlapStart;
    }
  }
  return visibleExtent;
}

final class _MountedTargetRecord {
  const _MountedTargetRecord({required this.key, required this.index});

  final Object? key;
  final int? index;
}

final class _CapturedCommandTarget {
  const _CapturedCommandTarget({
    required this.target,
    required this.revision,
    this.failure,
  });

  final ScrollTarget target;
  final int? revision;
  final ScrollOutcome? failure;
}

final class _PreparedCommandTarget {
  _PreparedCommandTarget({
    required this.captured,
    this.driver,
    this.resolution,
  }) : assert(
          captured.failure != null || (driver != null && resolution != null),
        );

  final _CapturedCommandTarget captured;
  final ScrollDriver? driver;
  final ScrollResolution? resolution;

  bool get isNotLoaded =>
      captured.failure == ScrollOutcome.targetNotLoaded ||
      resolution?.status == ScrollResolutionStatus.targetNotLoaded;
}

final class _TargetLoadResolution<T> {
  const _TargetLoadResolution._({
    required this.value,
    required this.outcome,
    required this.attempts,
    required this.diagnostic,
    required this.revision,
    required this.cancelled,
  });

  const _TargetLoadResolution.resolved(
    T value, {
    int attempts = 0,
    Object? diagnostic,
    int? revision,
  }) : this._(
          value: value,
          outcome: null,
          attempts: attempts,
          diagnostic: diagnostic,
          revision: revision,
          cancelled: false,
        );

  const _TargetLoadResolution.terminal(
    T value, {
    required ScrollOutcome outcome,
    required int attempts,
    Object? diagnostic,
    int? revision,
  }) : this._(
          value: value,
          outcome: outcome,
          attempts: attempts,
          diagnostic: diagnostic,
          revision: revision,
          cancelled: false,
        );

  const _TargetLoadResolution.cancelled(
    T value, {
    required int attempts,
  }) : this._(
          value: value,
          outcome: null,
          attempts: attempts,
          diagnostic: null,
          revision: null,
          cancelled: true,
        );

  final T value;
  final ScrollOutcome? outcome;
  final int attempts;
  final Object? diagnostic;
  final int? revision;
  final bool cancelled;

  bool get isTerminal => outcome != null;

  Map<String, Object?> get diagnostics => <String, Object?>{
        if (attempts > 0) 'targetLoaderAttempts': attempts,
        if (diagnostic != null) 'targetLoader': diagnostic,
        if (revision != null) 'targetLoaderRevision': revision,
      };
}

final class _TargetLoaderInvocation {
  const _TargetLoaderInvocation._({
    required this.result,
    required this.error,
    required this.stackTrace,
    required this.cancelled,
  });

  const _TargetLoaderInvocation.completed(ScrollTargetLoadResult result)
      : this._(
          result: result,
          error: null,
          stackTrace: null,
          cancelled: false,
        );

  const _TargetLoaderInvocation.failed(
    Object error,
    StackTrace stackTrace,
  ) : this._(
          result: null,
          error: error,
          stackTrace: stackTrace,
          cancelled: false,
        );

  const _TargetLoaderInvocation.cancelled()
      : this._(
          result: null,
          error: null,
          stackTrace: null,
          cancelled: true,
        );

  final ScrollTargetLoadResult? result;
  final Object? error;
  final StackTrace? stackTrace;
  final bool cancelled;
}

const Object _targetLoadDelayDone = Object();
const Object _targetLoadDelayCancelled = Object();
const Object _targetLoadCommitDone = Object();
const Object _targetLoadCommitCancelled = Object();

const Object _cancelledSnapResolution = Object();

final class _ResolvedSnapTarget {
  const _ResolvedSnapTarget(this.target);

  final ScrollTarget? target;
}

abstract interface class _SeekoIndexedSliverHost {
  SeekoIndexDelegate<Object> get indexDelegate;
  double get globalScrollOrigin;
  _SeekoIndexedExtentSnapshot? get extentSnapshot;

  SeekoIndexedTargetResolution? resolveTarget(ScrollTarget target);

  List<ScrollVisibleTarget> collectVisibleTargets(
    VisibleRegion visibleRegion, {
    required int? globalIndexBase,
  });

  void beginWindowRebase({
    required double startPhysicalPixels,
    required double targetPhysicalPixels,
    required double viewportExtent,
  });

  void endWindowRebase();
}

final class _SeekoIndexedExtentSnapshot {
  const _SeekoIndexedExtentSnapshot({
    required this.itemCount,
    required this.measuredItemCount,
    required this.measuredExtent,
    required this.estimatedExtent,
  });

  final int itemCount;
  final int measuredItemCount;
  final double measuredExtent;
  final double estimatedExtent;
}

final class _CompositeIndexedLocation {
  const _CompositeIndexedLocation({
    required this.sliver,
    required this.localIndex,
  });

  final _SeekoIndexedSliverHost sliver;
  final int localIndex;
}

final class _CompositeIndexedMotionCoordinator
    implements SeekoIndexedMotionCoordinator {
  const _CompositeIndexedMotionCoordinator(this.controller);

  final SeekoController controller;

  @override
  void beginWindowRebase({
    required double startPhysicalPixels,
    required double targetPhysicalPixels,
    required double viewportExtent,
  }) {
    final _SeekoIndexedSliverHost? sliver =
        controller._activeIndexedMotionSliver;
    if (sliver == null) {
      return;
    }
    final double origin = sliver.globalScrollOrigin;
    sliver.beginWindowRebase(
      startPhysicalPixels: startPhysicalPixels - origin,
      targetPhysicalPixels: targetPhysicalPixels - origin,
      viewportExtent: viewportExtent,
    );
  }

  @override
  void endWindowRebase() {
    final _SeekoIndexedSliverHost? sliver =
        controller._activeIndexedMotionSliver;
    sliver?.endWindowRebase();
    controller._activeIndexedMotionSliver = null;
  }
}

final class _SeekoScrollPosition extends ScrollPositionWithSingleContext {
  _SeekoScrollPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    required super.oldPosition,
    required super.debugLabel,
    required this.onActivityChanged,
    required this.onMetricsChanged,
    required this.onUserScrollRequest,
  });

  final ValueChanged<ScrollActivity?> onActivityChanged;
  final VoidCallback onMetricsChanged;
  final VoidCallback onUserScrollRequest;
  var _userInteractionLocked = false;
  _LockedScrollHoldController? _lockedHold;

  bool get userInteractionLocked => _userInteractionLocked;

  set userInteractionLocked(bool value) {
    if (_userInteractionLocked == value) {
      return;
    }
    _userInteractionLocked = value;
    if (!value) {
      _lockedHold?.cancel();
    }
  }

  ScrollActivity? get currentActivity => activity;

  void animateNaturalSyncTo(
    double to, {
    required int transactionId,
    required Duration duration,
    required Curve curve,
    required NaturalSyncSnapBehavior snapBehavior,
  }) {
    final ScrollActivity? current = activity;
    if (current is _SeekoNaturalSyncActivity) {
      current.retarget(
        to: to,
        transactionId: transactionId,
        duration: duration,
        curve: curve,
        snapBehavior: snapBehavior,
      );
      return;
    }
    beginActivity(
      _SeekoNaturalSyncActivity(
        this,
        from: pixels,
        to: to,
        transactionId: transactionId,
        duration: duration,
        curve: curve,
        snapBehavior: snapBehavior,
        vsync: context.vsync,
      ),
    );
  }

  @override
  void didUpdateScrollMetrics() {
    super.didUpdateScrollMetrics();
    onMetricsChanged();
  }

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    if (userInteractionLocked) {
      final _LockedScrollHoldController hold = _LockedScrollHoldController(
        () {
          _lockedHold = null;
          holdCancelCallback();
        },
      );
      _lockedHold = hold;
      return hold;
    }
    return super.hold(holdCancelCallback);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    if (userInteractionLocked) {
      _lockedHold?.cancel();
      return _LockedDrag(dragCancelCallback);
    }
    return super.drag(details, dragCancelCallback);
  }

  @override
  void pointerScroll(double delta) {
    if (!userInteractionLocked) {
      if (delta != 0) {
        onUserScrollRequest();
      }
      super.pointerScroll(delta);
    }
  }

  @override
  Future<void> moveTo(
    double to, {
    Duration? duration,
    Curve? curve,
    bool? clamp = true,
  }) {
    if (userInteractionLocked) {
      return Future<void>.value();
    }
    if (to != pixels) {
      onUserScrollRequest();
    }
    return super.moveTo(
      to,
      duration: duration,
      curve: curve,
      clamp: clamp,
    );
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    super.beginActivity(newActivity);
    onActivityChanged(newActivity);
  }
}

final class _SeekoNaturalSyncActivity extends ScrollActivity {
  _SeekoNaturalSyncActivity(
    super.delegate, {
    required double from,
    required double to,
    required this.transactionId,
    required Duration duration,
    required Curve curve,
    required NaturalSyncSnapBehavior snapBehavior,
    required TickerProvider vsync,
  }) : _controller = AnimationController.unbounded(
          value: from,
          debugLabel: '_SeekoNaturalSyncActivity',
          vsync: vsync,
        ) {
    _controller
      ..addListener(_tick)
      ..addStatusListener(_handleStatus);
    retarget(
      to: to,
      transactionId: transactionId,
      duration: duration,
      curve: curve,
      snapBehavior: snapBehavior,
    );
  }

  final AnimationController _controller;
  int transactionId;
  double _target = 0;
  NaturalSyncSnapBehavior _snapBehavior = NaturalSyncSnapBehavior.none;
  var _disposed = false;

  void retarget({
    required double to,
    required int transactionId,
    required Duration duration,
    required Curve curve,
    required NaturalSyncSnapBehavior snapBehavior,
  }) {
    this.transactionId = transactionId;
    _target = to;
    _snapBehavior = snapBehavior;
    unawaited(_controller.animateTo(to, duration: duration, curve: curve));
  }

  void _tick() {
    if (delegate.setPixels(_controller.value).abs() >=
        precisionErrorTolerance) {
      delegate.goIdle();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (_disposed || _controller.isAnimating) {
      return;
    }
    if ((_controller.value - _target).abs() > precisionErrorTolerance) {
      return;
    }
    switch (_snapBehavior) {
      case NaturalSyncSnapBehavior.none:
        delegate.goIdle();
      case NaturalSyncSnapBehavior.memberPhysics:
        delegate.goBallistic(0);
    }
  }

  @override
  void dispatchOverscrollNotification(
    ScrollMetrics metrics,
    BuildContext context,
    double overscroll,
  ) {
    OverscrollNotification(
      metrics: metrics,
      context: context,
      overscroll: overscroll,
      velocity: velocity,
    ).dispatch(context);
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _controller.velocity;

  @override
  void dispose() {
    _disposed = true;
    _controller
      ..removeListener(_tick)
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }
}

final class _LockedScrollHoldController implements ScrollHoldController {
  _LockedScrollHoldController(this._onCancelled);

  final VoidCallback _onCancelled;
  var _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _onCancelled();
  }
}

final class _LockedDrag implements Drag {
  _LockedDrag(this._onCancelled);

  final VoidCallback _onCancelled;
  var _ended = false;

  @override
  void update(DragUpdateDetails details) {}

  @override
  void end(DragEndDetails details) => _finish();

  @override
  void cancel() => _finish();

  void _finish() {
    if (_ended) {
      return;
    }
    _ended = true;
    _onCancelled();
  }
}
