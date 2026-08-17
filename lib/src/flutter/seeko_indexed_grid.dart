part of 'seeko_controller.dart';

/// A layout-aware grid sliver for unmounted key and index navigation.
///
/// The surrounding scrollable remains a native [CustomScrollView]. This
/// primitive reuses the caller's [SliverChildDelegate] and
/// [SliverGridDelegate], so fixed, responsive, and custom grid layouts keep
/// Flutter's native layout, semantics, keep-alive, and recycling behavior.
///
/// When [indexDelegate] has a finite `itemCount`, [delegate] must expose the
/// same finite child count. A mismatched or unknown child count rejects indexed
/// target resolution instead of claiming that a cell exists when Flutter
/// cannot build it.
class SeekoIndexedGridSliver extends SliverMultiBoxAdaptorWidget {
  const SeekoIndexedGridSliver({
    required this.controller,
    required this.indexDelegate,
    required this.gridDelegate,
    required super.delegate,
    this.anchorPolicy = const AnchorPolicy.firstVisible(),
    super.key,
  });

  final SeekoController controller;
  final SeekoIndexDelegate<Object> indexDelegate;
  final SliverGridDelegate gridDelegate;
  final AnchorPolicy anchorPolicy;

  @override
  RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context) {
    return _RenderSeekoIndexedGrid(
      childManager: context as SliverMultiBoxAdaptorElement,
      controller: controller,
      indexDelegate: indexDelegate,
      gridDelegate: gridDelegate,
      anchorPolicy: anchorPolicy,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverMultiBoxAdaptor renderObject,
  ) {
    final _RenderSeekoIndexedGrid grid =
        renderObject as _RenderSeekoIndexedGrid;
    grid
      ..controller = controller
      ..indexDelegate = indexDelegate
      ..gridDelegate = gridDelegate
      ..anchorPolicy = anchorPolicy;
  }
}

final class _RenderSeekoIndexedGrid extends RenderSliverGrid
    implements _SeekoIndexedSliverHost {
  _RenderSeekoIndexedGrid({
    required super.childManager,
    required SeekoController controller,
    required SeekoIndexDelegate<Object> indexDelegate,
    required super.gridDelegate,
    required AnchorPolicy anchorPolicy,
  })  : _controller = controller,
        _indexDelegate = indexDelegate,
        _anchorPolicy = anchorPolicy;

  SeekoController _controller;
  SeekoController get controller => _controller;
  set controller(SeekoController value) {
    if (identical(_controller, value)) {
      return;
    }
    if (attached) {
      _controller._detachIndexedSliver(this);
    }
    _controller = value;
    if (attached) {
      _controller._attachIndexedSliver(this);
    }
  }

  SeekoIndexDelegate<Object> _indexDelegate;
  @override
  SeekoIndexDelegate<Object> get indexDelegate => _indexDelegate;
  set indexDelegate(SeekoIndexDelegate<Object> value) {
    if (identical(_indexDelegate, value)) {
      return;
    }
    if (attached) {
      _indexDelegate.changes.removeListener(_handleDataChanged);
    }
    _indexDelegate = value;
    if (attached) {
      _indexDelegate.changes.addListener(_handleDataChanged);
    }
    markNeedsLayout();
  }

  double _globalScrollOrigin = 0;
  AnchorPolicy _anchorPolicy;
  _IndexedLayoutAnchor? _capturedAnchor;
  _IndexedLayoutAnchor? _pendingAnchor;
  double? _lastCrossAxisExtent;
  AxisDirection? _lastCrossAxisDirection;

  AnchorPolicy get anchorPolicy => _anchorPolicy;
  set anchorPolicy(AnchorPolicy value) {
    if (_anchorPolicy == value) {
      return;
    }
    _anchorPolicy = value;
    _capturedAnchor = null;
    _pendingAnchor = null;
    markNeedsLayout();
  }

  @override
  set gridDelegate(SliverGridDelegate value) {
    final SliverGridDelegate previous = super.gridDelegate;
    final bool changesLayout = previous.runtimeType != value.runtimeType ||
        value.shouldRelayout(previous);
    if (changesLayout) {
      _pendingAnchor ??= _capturedAnchor;
    }
    super.gridDelegate = value;
  }

  @override
  double get globalScrollOrigin => _globalScrollOrigin;

  @override
  _SeekoIndexedExtentSnapshot? get extentSnapshot => null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _indexDelegate.changes.addListener(_handleDataChanged);
    _controller._attachIndexedSliver(this);
  }

  @override
  void detach() {
    _controller._detachIndexedSliver(this);
    _indexDelegate.changes.removeListener(_handleDataChanged);
    super.detach();
  }

  @override
  void performLayout() {
    final SeekoTimelineTask? timeline = kReleaseMode
        ? null
        : SeekoTimeline.start(
            'Seeko.layout',
            arguments: <String, Object?>{
              'driver': 'indexed-grid',
              'revision': _indexDelegate.revision,
            },
          );
    try {
      _performSeekoLayout();
    } finally {
      timeline?.finish();
    }
  }

  void _performSeekoLayout() {
    final double nextOrigin = constraints.precedingScrollExtent;
    if (_globalScrollOrigin != nextOrigin) {
      _globalScrollOrigin = nextOrigin;
      _controller._indexedSliverOriginChanged();
    }
    final double? previousCrossAxisExtent = _lastCrossAxisExtent;
    final AxisDirection? previousCrossAxisDirection = _lastCrossAxisDirection;
    if (previousCrossAxisExtent != null &&
        (previousCrossAxisExtent != constraints.crossAxisExtent ||
            previousCrossAxisDirection != constraints.crossAxisDirection)) {
      _pendingAnchor ??= _capturedAnchor;
    }
    _lastCrossAxisExtent = constraints.crossAxisExtent;
    _lastCrossAxisDirection = constraints.crossAxisDirection;
    final double? anchorCorrection = _pendingAnchorCorrection();
    if (anchorCorrection != null) {
      geometry = SliverGeometry(scrollOffsetCorrection: anchorCorrection);
      return;
    }
    final _InitialTargetLayoutDecision? initialDecision =
        _initialTargetDecision();
    if (_finishFailedInitialTarget(initialDecision)) {
      geometry = SliverGeometry.zero;
      return;
    }
    if (initialDecision?.correction case final double initialCorrection) {
      geometry = SliverGeometry(scrollOffsetCorrection: initialCorrection);
      return;
    }
    super.performLayout();
    final SliverGeometry? currentGeometry = geometry;
    if (currentGeometry == null ||
        currentGeometry.scrollOffsetCorrection != null) {
      return;
    }
    final _InitialTargetLayoutDecision? measuredDecision =
        _initialTargetDecision();
    if (_finishFailedInitialTarget(measuredDecision)) {
      geometry = SliverGeometry.zero;
      return;
    }
    if (measuredDecision?.correction case final double measuredCorrection) {
      geometry = SliverGeometry(scrollOffsetCorrection: measuredCorrection);
      return;
    }
    if (measuredDecision != null) {
      _controller._completeInitialTarget(
        outcome: ScrollOutcome.completed,
        dataRevision: measuredDecision.dataRevision,
        finalLogicalPixels: _globalScrollOrigin + constraints.scrollOffset,
      );
    }
    _captureAnchor();
    _controller._scheduleSnapshot();
  }

  @override
  SeekoIndexedTargetResolution? resolveTarget(ScrollTarget target) {
    try {
      return _resolveTarget(target);
    } on Object catch (error, stackTrace) {
      return SeekoIndexedTargetResolution.resolverRejected(
        diagnostics: <String, Object?>{
          'resolverKind': 'indexedGrid',
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  SeekoIndexedTargetResolution? _resolveTarget(ScrollTarget target) {
    final int? itemCount = _indexDelegate.itemCount;
    if (itemCount == null) {
      return const SeekoIndexedTargetResolution.targetNotLoaded();
    }
    if (!_hasCompatibleChildCount(itemCount)) {
      return SeekoIndexedTargetResolution.resolverRejected(
        diagnostics: <String, Object?>{
          'resolverKind': 'indexedGrid',
          'reason': 'childCountMismatch',
          'itemCount': itemCount,
        },
      );
    }
    late final SeekoKeyLookup<Object> lookup;
    if (target case KeyScrollTarget(:final Object key)) {
      lookup = _indexDelegate.lookupKey(key);
    } else if (target case IndexScrollTarget(:final int index)) {
      if (index >= itemCount) {
        return const SeekoIndexedTargetResolution.targetOutOfRange();
      }
      if (!_indexDelegate.loadedRanges.contains(index)) {
        return const SeekoIndexedTargetResolution.targetNotLoaded();
      }
      lookup = SeekoKeyLookup<Object>.found(index);
    } else {
      return null;
    }
    switch (lookup.status) {
      case SeekoKeyLookupStatus.notLoaded:
        return const SeekoIndexedTargetResolution.targetNotLoaded();
      case SeekoKeyLookupStatus.absent:
        return const SeekoIndexedTargetResolution.targetDeleted();
      case SeekoKeyLookupStatus.found:
        break;
    }
    final int index = lookup.index!;
    if (index < 0 || index >= itemCount) {
      return const SeekoIndexedTargetResolution.targetOutOfRange();
    }
    if (!_indexDelegate.loadedRanges.contains(index)) {
      return const SeekoIndexedTargetResolution.targetNotLoaded();
    }
    try {
      final SliverGridGeometry geometry =
          gridDelegate.getLayout(constraints).getGeometryForChildIndex(index);
      if (!_isValidGeometry(geometry)) {
        return SeekoIndexedTargetResolution.resolverRejected(
          diagnostics: <String, Object?>{
            'resolverKind': 'indexedGridGeometry',
            'reason': 'invalidGeometry',
            'index': index,
          },
        );
      }
      return SeekoIndexedTargetResolution.resolved(
        targetInterval: LogicalInterval(
          _globalScrollOrigin + geometry.scrollOffset,
          _globalScrollOrigin + geometry.trailingScrollOffset,
        ),
        dataRevision: _indexDelegate.revision,
      );
    } on Object catch (error, stackTrace) {
      return SeekoIndexedTargetResolution.resolverRejected(
        diagnostics: <String, Object?>{
          'resolverKind': 'indexedGridGeometry',
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  @override
  List<ScrollVisibleTarget> collectVisibleTargets(
    VisibleRegion visibleRegion, {
    required int? globalIndexBase,
  }) {
    final double viewportExtent = constraints.viewportMainAxisExtent;
    final SliverGeometry? currentGeometry = geometry;
    if (viewportExtent <= 0 ||
        firstChild == null ||
        currentGeometry == null ||
        !currentGeometry.visible ||
        currentGeometry.paintExtent <= 0) {
      return const <ScrollVisibleTarget>[];
    }
    final List<ScrollVisibleTarget> result = <ScrollVisibleTarget>[];
    final SliverGridLayout layout = gridDelegate.getLayout(constraints);
    RenderBox? child = firstChild;
    while (child != null) {
      final int index = indexOf(child);
      final double leading = childMainAxisPosition(child);
      final double trailing =
          leading + layout.getGeometryForChildIndex(index).mainAxisExtent;
      final double visibleExtent = _visibleExtentForInterval(
        leading: leading,
        trailing: trailing,
        visibleRegion: visibleRegion,
      );
      if (visibleExtent > 0 && trailing > leading) {
        result.add(
          ScrollVisibleTarget(
            key: _indexDelegate.keyAt(index),
            index: globalIndexBase == null ? null : globalIndexBase + index,
            leadingPixels: leading,
            trailingPixels: trailing,
            leadingViewportFraction: leading / viewportExtent,
            trailingViewportFraction: trailing / viewportExtent,
            visibleFraction: (visibleExtent / (trailing - leading)).clamp(0, 1),
          ),
        );
      }
      child = childAfter(child);
    }
    return result.isEmpty
        ? const <ScrollVisibleTarget>[]
        : List<ScrollVisibleTarget>.unmodifiable(result);
  }

  @override
  void beginWindowRebase({
    required double startPhysicalPixels,
    required double targetPhysicalPixels,
    required double viewportExtent,
  }) {}

  @override
  void endWindowRebase() {}

  void _handleDataChanged() {
    _pendingAnchor = _capturedAnchor;
    markNeedsLayout();
    _controller._scheduleSnapshot();
  }

  double? _pendingAnchorCorrection() {
    final _IndexedLayoutAnchor? anchor = _pendingAnchor;
    final int? itemCount = _indexDelegate.itemCount;
    if (anchor == null ||
        itemCount == null ||
        !_hasCompatibleChildCount(itemCount)) {
      return null;
    }
    if (itemCount == 0) {
      _pendingAnchor = null;
      return null;
    }
    final SliverGridLayout layout = gridDelegate.getLayout(constraints);
    final double totalExtent = layout.computeMaxScrollOffset(itemCount);
    final double maxScrollOffset = math.max(
      0,
      totalExtent - constraints.viewportMainAxisExtent,
    );
    late final double desired;
    if (anchor.trailing) {
      desired = maxScrollOffset;
    } else {
      final SeekoKeyLookup<Object> lookup =
          _indexDelegate.lookupKey(anchor.key!);
      int? index = lookup.isFound ? lookup.index : null;
      if (index == null &&
          (_anchorPolicy is NearestAnchorPolicy ||
              _anchorPolicy is TrailingEdgeAnchorPolicy)) {
        index = anchor.index.clamp(0, itemCount - 1);
      }
      if (index == null) {
        _pendingAnchor = null;
        return null;
      }
      desired = layout.getGeometryForChildIndex(index).scrollOffset -
          anchor.viewportOffset;
    }
    final double correction =
        desired.clamp(0, maxScrollOffset).toDouble() - constraints.scrollOffset;
    if (correction.abs() <= 0.5) {
      _pendingAnchor = null;
      return null;
    }
    return correction;
  }

  void _captureAnchor() {
    final int? itemCount = _indexDelegate.itemCount;
    if (_anchorPolicy is NoAnchorPolicy ||
        itemCount == null ||
        itemCount == 0 ||
        !_hasCompatibleChildCount(itemCount)) {
      _capturedAnchor = null;
      return;
    }
    final SliverGridLayout layout = gridDelegate.getLayout(constraints);
    if (_anchorPolicy case ExplicitKeyAnchorPolicy(:final Object key)) {
      final SeekoKeyLookup<Object> lookup = _indexDelegate.lookupKey(key);
      if (!lookup.isFound) {
        _capturedAnchor = null;
        return;
      }
      final int index = lookup.index!;
      _capturedAnchor = _IndexedLayoutAnchor.item(
        key: key,
        index: index,
        viewportOffset: layout.getGeometryForChildIndex(index).scrollOffset -
            constraints.scrollOffset,
      );
      return;
    }
    if (_anchorPolicy
        case TrailingEdgeAnchorPolicy(:final double followThreshold)) {
      final double totalExtent = layout.computeMaxScrollOffset(itemCount);
      final double maxScrollOffset = math.max(
        0,
        totalExtent - constraints.viewportMainAxisExtent,
      );
      if (maxScrollOffset - constraints.scrollOffset <= followThreshold) {
        _capturedAnchor = const _IndexedLayoutAnchor.trailing();
        return;
      }
    }
    final VisibleRegion visibleRegion = _effectiveVisibleRegion();
    RenderBox? child = firstChild;
    while (child != null) {
      final int index = indexOf(child);
      final double leading = childMainAxisPosition(child);
      final double trailing =
          leading + layout.getGeometryForChildIndex(index).mainAxisExtent;
      if (_visibleExtentForInterval(
            leading: leading,
            trailing: trailing,
            visibleRegion: visibleRegion,
          ) >
          0) {
        _capturedAnchor = _IndexedLayoutAnchor.item(
          key: _indexDelegate.keyAt(index),
          index: index,
          viewportOffset: leading,
        );
        return;
      }
      child = childAfter(child);
    }
    _capturedAnchor = null;
  }

  VisibleRegion _effectiveVisibleRegion() =>
      _controller.obstructionResolver?.call(
        ScrollViewportGeometry(
          viewportExtent: constraints.viewportMainAxisExtent,
          axis: constraints.axis,
          axisDirection: constraints.axisDirection,
        ),
      ) ??
      VisibleRegion.fromIntervals(<LogicalInterval>[
        LogicalInterval(0, constraints.viewportMainAxisExtent),
      ]);

  _InitialTargetLayoutDecision? _initialTargetDecision() {
    final ScrollTarget? target = _controller._pendingInitialTarget;
    if (target == null) {
      return null;
    }
    final SeekoIndexedTargetResolution? targetResolution =
        _controller._initialIndexedResolutionFor(this);
    if (targetResolution == null) {
      return null;
    }
    if (targetResolution.status != ScrollResolutionStatus.resolved) {
      return _InitialTargetLayoutDecision.failure(
        _outcomeForInitialResolution(targetResolution.status),
        dataRevision: targetResolution.dataRevision,
      );
    }
    final VisibleRegion visibleRegion = _controller.obstructionResolver?.call(
          ScrollViewportGeometry(
            viewportExtent: constraints.viewportMainAxisExtent,
            axis: constraints.axis,
            axisDirection: constraints.axisDirection,
          ),
        ) ??
        VisibleRegion.fromIntervals(<LogicalInterval>[
          LogicalInterval(0, constraints.viewportMainAxisExtent),
        ]);
    final ScrollPlacementResolution placement = resolveScrollPlacement(
      placement: _controller.initialPlacement,
      target: targetResolution.targetInterval!,
      visibleRegion: visibleRegion,
      currentPixels: _controller.position.pixels,
    );
    final int? itemCount = _indexDelegate.itemCount;
    if (itemCount == null) {
      return const _InitialTargetLayoutDecision.failure(
        ScrollOutcome.targetNotLoaded,
        dataRevision: null,
      );
    }
    final double totalExtent =
        gridDelegate.getLayout(constraints).computeMaxScrollOffset(itemCount);
    final double maxScrollOffset = math.max(
      0,
      _globalScrollOrigin + totalExtent - constraints.viewportMainAxisExtent,
    );
    final double desired =
        placement.pixels.clamp(0, maxScrollOffset).toDouble();
    final double correction = desired - _controller.position.pixels;
    return _InitialTargetLayoutDecision.resolved(
      correction: correction.abs() <= 0.5 ? null : correction,
      dataRevision: targetResolution.dataRevision,
    );
  }

  bool _finishFailedInitialTarget(
    _InitialTargetLayoutDecision? decision,
  ) {
    final ScrollOutcome? outcome = decision?.failure;
    if (outcome == null) {
      return false;
    }
    _controller._completeInitialTarget(
      outcome: outcome,
      dataRevision: decision?.dataRevision,
      finalLogicalPixels: null,
    );
    return true;
  }

  bool _isValidGeometry(SliverGridGeometry geometry) {
    return geometry.scrollOffset.isFinite &&
        geometry.scrollOffset >= 0 &&
        geometry.crossAxisOffset.isFinite &&
        geometry.mainAxisExtent.isFinite &&
        geometry.mainAxisExtent >= 0 &&
        geometry.crossAxisExtent.isFinite &&
        geometry.crossAxisExtent >= 0 &&
        geometry.trailingScrollOffset.isFinite;
  }

  bool _hasCompatibleChildCount(int itemCount) =>
      childManager.estimatedChildCount == itemCount;
}
