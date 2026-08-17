part of 'seeko_controller.dart';

/// A layout-aware sliver primitive for unmounted index and key navigation.
///
/// The outer scroll view remains a native [CustomScrollView]. This primitive
/// reuses the caller's [SliverChildDelegate] and materializes only the active
/// viewport/cache window, including after a far jump.
class SeekoIndexedSliver extends SliverMultiBoxAdaptorWidget {
  const SeekoIndexedSliver({
    required this.controller,
    required this.indexDelegate,
    required super.delegate,
    this.estimatedExtent = 56,
    this.anchorPolicy = const AnchorPolicy.firstVisible(),
    this.debugShrinkWrapItemLimit = 1000,
    super.key,
  })  : assert(estimatedExtent > 0 && estimatedExtent < double.infinity),
        assert(debugShrinkWrapItemLimit > 0);

  final SeekoController controller;
  final SeekoIndexDelegate<Object> indexDelegate;
  final double estimatedExtent;
  final AnchorPolicy anchorPolicy;

  /// Maximum finite item count accepted by a shrink-wrapping viewport in
  /// debug mode.
  ///
  /// Shrink wrapping must discover the complete main-axis extent, so it
  /// cannot provide Seeko's sparse million-item or 120 Hz guarantees. Small
  /// finite collections remain supported; larger collections fail early with
  /// migration guidance instead of silently materializing the whole list.
  final int debugShrinkWrapItemLimit;

  @override
  RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context) {
    final SliverMultiBoxAdaptorElement element =
        context as SliverMultiBoxAdaptorElement;
    return _RenderSeekoIndexedSliver(
      childManager: element,
      controller: controller,
      indexDelegate: indexDelegate,
      estimatedExtent: estimatedExtent,
      anchorPolicy: anchorPolicy,
      debugShrinkWrapItemLimit: debugShrinkWrapItemLimit,
      brightness:
          MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverMultiBoxAdaptor renderObject,
  ) {
    final _RenderSeekoIndexedSliver indexed =
        renderObject as _RenderSeekoIndexedSliver;
    indexed
      ..controller = controller
      ..indexDelegate = indexDelegate
      ..estimatedExtent = estimatedExtent
      ..anchorPolicy = anchorPolicy
      ..debugShrinkWrapItemLimit = debugShrinkWrapItemLimit
      ..brightness =
          MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
  }
}

final class _RenderSeekoIndexedSliver extends RenderSliverList
    implements SeekoIndexedMotionCoordinator, _SeekoIndexedSliverHost {
  _RenderSeekoIndexedSliver({
    required super.childManager,
    required SeekoController controller,
    required SeekoIndexDelegate<Object> indexDelegate,
    required double estimatedExtent,
    required AnchorPolicy anchorPolicy,
    required int debugShrinkWrapItemLimit,
    required Brightness brightness,
  })  : _controller = controller,
        _indexDelegate = indexDelegate,
        _estimatedExtent = estimatedExtent,
        _anchorPolicy = anchorPolicy,
        _debugShrinkWrapItemLimit = debugShrinkWrapItemLimit,
        _brightness = brightness,
        _extentIndex = SparseExtentIndex(
          itemCount: _finiteItemCount(indexDelegate),
          estimatedExtent: estimatedExtent,
        ),
        _extentRevision = indexDelegate.revision;

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
    _resetExtentIndex();
    if (attached) {
      _indexDelegate.changes.addListener(_handleDataChanged);
    }
    markNeedsLayout();
  }

  double _estimatedExtent;
  double get estimatedExtent => _estimatedExtent;
  set estimatedExtent(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'estimatedExtent',
        'must be finite and positive',
      );
    }
    if (_estimatedExtent == value) {
      return;
    }
    _estimatedExtent = value;
    _resetExtentIndex();
    markNeedsLayout();
  }

  AnchorPolicy _anchorPolicy;
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

  int _debugShrinkWrapItemLimit;
  int get debugShrinkWrapItemLimit => _debugShrinkWrapItemLimit;
  set debugShrinkWrapItemLimit(int value) {
    if (value <= 0) {
      throw RangeError.value(
        value,
        'debugShrinkWrapItemLimit',
        'must be positive',
      );
    }
    _debugShrinkWrapItemLimit = value;
  }

  SparseExtentIndex _extentIndex;
  int _extentRevision;
  Brightness _brightness;
  Brightness get brightness => _brightness;
  set brightness(Brightness value) {
    if (_brightness == value) {
      return;
    }
    _brightness = value;
    markNeedsPaint();
  }

  _IndexedWindowRebase? _windowRebase;
  int? _materializedWindowEpoch;
  _IndexedVirtualWindow? _paintedVirtualWindow;
  _IndexedLayoutAnchor? _capturedAnchor;
  _IndexedLayoutAnchor? _pendingAnchor;
  double _globalScrollOrigin = 0;
  var _dataWindowDirty = false;
  var _reportedShrinkWrapDiagnostic = false;
  final Paint _cruiseSurfacePaint = Paint();
  final Paint _cruiseAccentPaint = Paint()..strokeCap = StrokeCap.round;

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
  double get globalScrollOrigin => _globalScrollOrigin;

  @override
  _SeekoIndexedExtentSnapshot get extentSnapshot => _SeekoIndexedExtentSnapshot(
        itemCount: _extentIndex.itemCount,
        measuredItemCount: _extentIndex.measuredCount,
        measuredExtent: _extentIndex.measuredExtent,
        estimatedExtent: _extentIndex.estimatedExtentTotal,
      );

  @override
  SeekoIndexedTargetResolution? resolveTarget(ScrollTarget target) {
    late final SeekoIndexedTargetResolution? local;
    try {
      local = _resolveLocalTarget(target);
    } on Object catch (error, stackTrace) {
      return SeekoIndexedTargetResolution.resolverRejected(
        diagnostics: <String, Object?>{
          'resolverKind': 'indexedKeyLookup',
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
    if (local?.status != ScrollResolutionStatus.resolved) {
      return local;
    }
    final LogicalInterval interval = local!.targetInterval!;
    return SeekoIndexedTargetResolution.resolved(
      targetInterval: LogicalInterval(
        _globalScrollOrigin + interval.start,
        _globalScrollOrigin + interval.end,
      ),
      dataRevision: local.dataRevision!,
      diagnostics: local.diagnostics,
    );
  }

  SeekoIndexedTargetResolution? _resolveLocalTarget(ScrollTarget target) {
    final int? itemCount = _indexDelegate.itemCount;
    if (itemCount == null) {
      return const SeekoIndexedTargetResolution.targetNotLoaded();
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
    _ensureExtentIndexCount();
    final double start = _extentIndex.offsetOf(index);
    return SeekoIndexedTargetResolution.resolved(
      targetInterval: LogicalInterval(
        start,
        start + _extentIndex.extentOf(index),
      ),
      dataRevision: _indexDelegate.revision,
    );
  }

  @override
  void performLayout() {
    final SeekoTimelineTask? timeline = kReleaseMode
        ? null
        : SeekoTimeline.start(
            'Seeko.layout',
            arguments: <String, Object?>{
              'driver': 'indexed-sliver',
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
    assert(_debugCheckShrinkWrapUsage());
    final double globalScrollOrigin = constraints.precedingScrollExtent;
    if (_globalScrollOrigin != globalScrollOrigin) {
      _globalScrollOrigin = globalScrollOrigin;
      _controller._indexedSliverOriginChanged();
    }
    _ensureExtentIndexCount();
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
    final double scrollOffset =
        constraints.scrollOffset + constraints.cacheOrigin;
    final _IndexedWindowRebase? windowRebase = _windowRebase;
    if (windowRebase != null) {
      final _IndexedVirtualWindow window = windowRebase.windowAt(
        constraints.scrollOffset,
      );
      _paintedVirtualWindow = window;
      _prepareVirtualWindow(window);
    } else if (_dataWindowDirty) {
      _paintedVirtualWindow = null;
      _rebaseTo(scrollOffset);
      _dataWindowDirty = false;
    } else if (_shouldRebase(scrollOffset)) {
      _paintedVirtualWindow = null;
      _rebaseTo(scrollOffset);
    } else {
      _paintedVirtualWindow = null;
    }
    super.performLayout();
    final SliverGeometry? currentGeometry = geometry;
    if (currentGeometry == null ||
        currentGeometry.scrollOffsetCorrection != null) {
      return;
    }
    _recordMeasurements();
    final double? measuredAnchorCorrection = _pendingAnchorCorrection();
    if (measuredAnchorCorrection != null) {
      geometry = SliverGeometry(
        scrollOffsetCorrection: measuredAnchorCorrection,
      );
      return;
    }
    final _InitialTargetLayoutDecision? measuredInitialDecision =
        _initialTargetDecision();
    if (_finishFailedInitialTarget(measuredInitialDecision)) {
      geometry = SliverGeometry.zero;
      return;
    }
    if (measuredInitialDecision?.correction
        case final double measuredInitialCorrection) {
      geometry = SliverGeometry(
        scrollOffsetCorrection: measuredInitialCorrection,
      );
      return;
    }
    final double totalExtent = _extentIndex.offsetOf(_extentIndex.itemCount);
    final double paintExtent = windowRebase == null
        ? currentGeometry.paintExtent
        : constraints.remainingPaintExtent.clamp(0, totalExtent).toDouble();
    geometry = currentGeometry.copyWith(
      scrollExtent: totalExtent,
      paintExtent: paintExtent,
      layoutExtent: paintExtent,
      maxPaintExtent: totalExtent,
      hitTestExtent: paintExtent,
      visible: paintExtent > 0,
      hasVisualOverflow:
          windowRebase != null || currentGeometry.hasVisualOverflow,
      cacheExtent: windowRebase == null
          ? currentGeometry.cacheExtent
          : constraints.remainingCacheExtent.clamp(0, totalExtent).toDouble(),
    );
    if (measuredInitialDecision != null) {
      _controller._completeInitialTarget(
        outcome: ScrollOutcome.completed,
        dataRevision: measuredInitialDecision.dataRevision,
        finalLogicalPixels: _globalScrollOrigin + constraints.scrollOffset,
      );
    }
    _captureAnchor();
    _controller._scheduleSnapshot();
  }

  bool _debugCheckShrinkWrapUsage() {
    if (parent is! RenderShrinkWrappingViewport) {
      _reportedShrinkWrapDiagnostic = false;
      return true;
    }
    final int count = _finiteItemCount(_indexDelegate);
    if (count <= _debugShrinkWrapItemLimit || _reportedShrinkWrapDiagnostic) {
      return true;
    }
    _reportedShrinkWrapDiagnostic = true;
    debugPrint(
      'SeekoIndexedSliver: shrinkWrap must measure all $count items, which '
      'exceeds debugShrinkWrapItemLimit=$_debugShrinkWrapItemLimit and '
      'disables sparse million-item and 120 Hz performance guarantees. Use '
      'a bounded CustomScrollView without shrinkWrap for virtualized data.',
    );
    return true;
  }

  double? _pendingAnchorCorrection() {
    final _IndexedLayoutAnchor? anchor = _pendingAnchor;
    if (anchor == null) {
      return null;
    }
    final int count = _extentIndex.itemCount;
    if (count == 0) {
      _pendingAnchor = null;
      return null;
    }
    final double totalExtent = _extentIndex.offsetOf(count);
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
        index = anchor.index.clamp(0, count - 1);
      }
      if (index == null) {
        _pendingAnchor = null;
        return null;
      }
      desired = _extentIndex.offsetOf(index) - anchor.viewportOffset;
    }
    final double correction =
        desired.clamp(0, maxScrollOffset).toDouble() - constraints.scrollOffset;
    if (correction.abs() <= 0.5) {
      _pendingAnchor = null;
      return null;
    }
    return correction;
  }

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
    final double totalExtent = _extentIndex.offsetOf(_extentIndex.itemCount);
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

  @override
  void beginWindowRebase({
    required double startPhysicalPixels,
    required double targetPhysicalPixels,
    required double viewportExtent,
  }) {
    _windowRebase = _IndexedWindowRebase(
      startScrollOffset: startPhysicalPixels,
      targetScrollOffset: targetPhysicalPixels,
      viewportExtent: viewportExtent,
      maxScrollOffset: math.max(
        0,
        _extentIndex.offsetOf(_extentIndex.itemCount) - viewportExtent,
      ),
    );
    _materializedWindowEpoch = null;
    markNeedsLayout();
  }

  @override
  void endWindowRebase() {
    if (_windowRebase == null) {
      return;
    }
    _windowRebase = null;
    _paintedVirtualWindow = null;
    _materializedWindowEpoch = null;
    markNeedsLayout();
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final _IndexedVirtualWindow? window = _paintedVirtualWindow;
    if (window == null || window.cruiseOpacity <= 0) {
      return;
    }
    final SliverGeometry? currentGeometry = geometry;
    if (currentGeometry == null || currentGeometry.paintExtent <= 0) {
      return;
    }
    final Size size = constraints.axis == Axis.vertical
        ? Size(constraints.crossAxisExtent, currentGeometry.paintExtent)
        : Size(currentGeometry.paintExtent, constraints.crossAxisExtent);
    final Rect bounds = offset & size;
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.clipRect(bounds);
    _cruiseSurfacePaint.color = brightness == Brightness.dark
        ? Color.fromRGBO(7, 17, 31, window.cruiseOpacity)
        : Color.fromRGBO(248, 250, 252, window.cruiseOpacity);
    canvas.drawRect(bounds, _cruiseSurfacePaint);
    _paintCruiseStreaks(canvas, bounds, window);
    canvas.restore();
  }

  void _paintCruiseStreaks(
    Canvas canvas,
    Rect bounds,
    _IndexedVirtualWindow window,
  ) {
    final double mainExtent =
        constraints.axis == Axis.vertical ? bounds.height : bounds.width;
    final double crossExtent =
        constraints.axis == Axis.vertical ? bounds.width : bounds.height;
    _cruiseAccentPaint.color = brightness == Brightness.dark
        ? Color.fromRGBO(76, 125, 255, 0.30 * window.cruiseOpacity)
        : Color.fromRGBO(49, 95, 214, 0.22 * window.cruiseOpacity);
    for (var index = 0; index < 6; index += 1) {
      final double cross = crossExtent * (0.18 + index * 0.13);
      final double phase = (window.progress * 3.0 + index * 0.17) % 1.0;
      final double center = mainExtent * phase;
      final double halfLength = mainExtent * (0.035 + index * 0.004);
      _cruiseAccentPaint.strokeWidth = 2.0 + (index % 3);
      final double leading = center - halfLength * window.direction;
      final double trailing = center + halfLength * window.direction;
      if (constraints.axis == Axis.vertical) {
        canvas.drawLine(
          Offset(bounds.left + cross, bounds.top + leading),
          Offset(bounds.left + cross, bounds.top + trailing),
          _cruiseAccentPaint,
        );
      } else {
        canvas.drawLine(
          Offset(bounds.left + leading, bounds.top + cross),
          Offset(bounds.left + trailing, bounds.top + cross),
          _cruiseAccentPaint,
        );
      }
    }
  }

  @override
  List<ScrollVisibleTarget> collectVisibleTargets(
    VisibleRegion visibleRegion, {
    required int? globalIndexBase,
  }) {
    if (_paintedVirtualWindow
        case _IndexedVirtualWindow(
          cruiseOpacity: > 0,
        )) {
      return const <ScrollVisibleTarget>[];
    }
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
    RenderBox? child = firstChild;
    while (child != null) {
      final int index = indexOf(child);
      final double leading = childMainAxisPosition(child);
      final double trailing = leading + paintExtentOf(child);
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

  void _captureAnchor() {
    if (_windowRebase != null || _anchorPolicy is NoAnchorPolicy) {
      return;
    }
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
        viewportOffset: _extentIndex.offsetOf(index) - constraints.scrollOffset,
      );
      return;
    }
    if (_anchorPolicy
        case TrailingEdgeAnchorPolicy(:final double followThreshold)) {
      final double totalExtent = _extentIndex.offsetOf(_extentIndex.itemCount);
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
      final double leading = childMainAxisPosition(child);
      final double trailing = leading + paintExtentOf(child);
      if (_visibleExtentForInterval(
            leading: leading,
            trailing: trailing,
            visibleRegion: visibleRegion,
          ) >
          0) {
        final int index = indexOf(child);
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

  void _prepareVirtualWindow(_IndexedVirtualWindow window) {
    if (_extentIndex.itemCount == 0) {
      return;
    }
    final double virtualCacheOffset = math.max(
      0,
      window.scrollOffset + constraints.cacheOrigin,
    );
    final int seedIndex = _extentIndex.indexAtOffset(virtualCacheOffset);
    final double layoutOffset = constraints.scrollOffset +
        _extentIndex.offsetOf(seedIndex) -
        window.scrollOffset;
    if (layoutOffset < -precisionErrorTolerance) {
      return;
    }
    final RenderBox? first = firstChild;
    final RenderBox? last = lastChild;
    final bool canReuseCurrentWindow = first != null &&
        last != null &&
        seedIndex >= indexOf(first) &&
        seedIndex <= indexOf(last);
    if (_materializedWindowEpoch != window.epoch && !canReuseCurrentWindow) {
      _rebaseToIndex(seedIndex, layoutOffset);
    } else if (first != null) {
      final int firstIndex = indexOf(first);
      final SliverMultiBoxAdaptorParentData parentData =
          first.parentData! as SliverMultiBoxAdaptorParentData;
      parentData.layoutOffset = constraints.scrollOffset +
          _extentIndex.offsetOf(firstIndex) -
          window.scrollOffset;
    }
    _materializedWindowEpoch = window.epoch;
  }

  bool _shouldRebase(double scrollOffset) {
    if (_extentIndex.itemCount == 0) {
      return false;
    }
    final RenderBox? first = firstChild;
    final RenderBox? last = lastChild;
    if (first == null || last == null) {
      return scrollOffset > precisionErrorTolerance;
    }
    final double? firstOffset = childScrollOffset(first);
    final double? lastOffset = childScrollOffset(last);
    if (firstOffset == null || lastOffset == null) {
      return true;
    }
    final double windowEnd = lastOffset + paintExtentOf(last);
    final double threshold = constraints.viewportMainAxisExtent * 2 +
        constraints.remainingCacheExtent;
    return scrollOffset < firstOffset - threshold ||
        scrollOffset > windowEnd + threshold;
  }

  void _rebaseTo(double scrollOffset) {
    final int index = _extentIndex.indexAtOffset(scrollOffset);
    _rebaseToIndex(index, _extentIndex.offsetOf(index));
    _materializedWindowEpoch = null;
  }

  void _rebaseToIndex(int index, double layoutOffset) {
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);
    try {
      if (firstChild != null) {
        collectGarbage(childCount, 0);
      }
      addInitialChild(
        index: index,
        layoutOffset: layoutOffset,
      );
    } finally {
      childManager.didFinishLayout();
    }
  }

  bool _recordMeasurements() {
    var changed = false;
    final _IndexedLayoutAnchor? measurementAnchor =
        _anchorMatchesCurrentPosition(_capturedAnchor) ? _capturedAnchor : null;
    RenderBox? child = firstChild;
    while (child != null) {
      final int index = indexOf(child);
      final double extent = paintExtentOf(child);
      if ((_extentIndex.extentOf(index) - extent).abs() > 1e-6) {
        _extentIndex.update(index, extent);
        changed = true;
      }
      child = childAfter(child);
    }
    if (changed && _pendingAnchor == null && measurementAnchor != null) {
      _pendingAnchor = measurementAnchor;
    }
    return changed;
  }

  bool _anchorMatchesCurrentPosition(_IndexedLayoutAnchor? anchor) {
    if (anchor == null || _extentIndex.itemCount == 0) {
      return false;
    }
    final double expected;
    if (anchor.trailing) {
      expected = math.max(
        0,
        _extentIndex.offsetOf(_extentIndex.itemCount) -
            constraints.viewportMainAxisExtent,
      );
    } else {
      final SeekoKeyLookup<Object> lookup =
          _indexDelegate.lookupKey(anchor.key!);
      if (!lookup.isFound) {
        return false;
      }
      expected = _extentIndex.offsetOf(lookup.index!) - anchor.viewportOffset;
    }
    return (expected - constraints.scrollOffset).abs() <= 0.5;
  }

  void _handleDataChanged() {
    _pendingAnchor = _capturedAnchor;
    final Listenable changes = _indexDelegate.changes;
    final SeekoChangeSet? changeSet =
        changes is ValueListenable<SeekoChangeSet?> ? changes.value : null;
    if (!_applyChangeSet(changeSet)) {
      _resetExtentIndex();
    }
    _dataWindowDirty = true;
    markNeedsLayout();
    _controller._scheduleSnapshot();
  }

  bool _applyChangeSet(SeekoChangeSet? changeSet) {
    if (changeSet == null) {
      return false;
    }
    if (changeSet.beforeRevision != _extentRevision ||
        changeSet.afterRevision != _indexDelegate.revision) {
      throw StateError(
        'SeekoIndexedSliver received a non-contiguous change set: extent '
        'revision $_extentRevision, change ${changeSet.beforeRevision} -> '
        '${changeSet.afterRevision}, delegate revision '
        '${_indexDelegate.revision}.',
      );
    }
    for (final SeekoChange change in changeSet.changes) {
      switch (change) {
        case SeekoInsertChange(:final int index, :final int count):
          _extentIndex.insert(index, count);
        case SeekoRemoveChange(:final int index, :final int count):
          _extentIndex.remove(index, count);
        case SeekoMoveChange(
            :final int from,
            :final int to,
            :final int count,
          ):
          _extentIndex.move(from, to, count);
        case SeekoUpdateChange(:final int index, :final int count):
          _extentIndex.invalidate(index, count);
        case SeekoResetChange():
          return false;
      }
    }
    final int expectedCount = _finiteItemCount(_indexDelegate);
    if (_extentIndex.itemCount != expectedCount) {
      throw StateError(
        'SeekoChangeSet produced ${_extentIndex.itemCount} indexed items, '
        'but the delegate reports $expectedCount.',
      );
    }
    _extentRevision = changeSet.afterRevision;
    return true;
  }

  void _ensureExtentIndexCount() {
    final int count = _finiteItemCount(_indexDelegate);
    if (_extentIndex.itemCount != count) {
      _resetExtentIndex();
    }
  }

  void _resetExtentIndex() {
    _extentIndex = SparseExtentIndex(
      itemCount: _finiteItemCount(_indexDelegate),
      estimatedExtent: _estimatedExtent,
    );
    _extentRevision = _indexDelegate.revision;
  }
}

final class _IndexedWindowRebase {
  const _IndexedWindowRebase({
    required this.startScrollOffset,
    required this.targetScrollOffset,
    required this.viewportExtent,
    required this.maxScrollOffset,
  });

  static const double _travelViewportsAtCruise = 1.15;
  static const double _cruiseEntryProgress = 0.35;

  final double startScrollOffset;
  final double targetScrollOffset;
  final double viewportExtent;
  final double maxScrollOffset;

  _IndexedVirtualWindow windowAt(double currentScrollOffset) {
    final double distance = targetScrollOffset - startScrollOffset;
    if (distance.abs() <= precisionErrorTolerance) {
      return _IndexedVirtualWindow(
        epoch: 1,
        scrollOffset: targetScrollOffset,
        progress: 1,
      );
    }
    final double progress =
        ((currentScrollOffset - startScrollOffset) / distance).clamp(0, 1);
    final double direction = distance.sign;
    final double travelPerProgress =
        viewportExtent * _travelViewportsAtCruise / _cruiseEntryProgress;
    final int epoch = progress < 0.5 ? 0 : 1;
    final double virtualOffset = epoch == 0
        ? startScrollOffset + direction * travelPerProgress * progress
        : targetScrollOffset - direction * travelPerProgress * (1 - progress);
    return _IndexedVirtualWindow(
      epoch: epoch,
      scrollOffset: virtualOffset.clamp(0, maxScrollOffset).toDouble(),
      progress: progress,
      direction: direction,
      cruiseOpacity: _cruiseOpacity(progress),
    );
  }

  double _cruiseOpacity(double progress) {
    if (progress <= 0.18 || progress >= 0.82) {
      return 0;
    }
    if (progress < 0.36) {
      return _smoothStep((progress - 0.18) / 0.18);
    }
    if (progress > 0.64) {
      return _smoothStep((0.82 - progress) / 0.18);
    }
    return 1;
  }

  double _smoothStep(double value) => value * value * (3 - 2 * value);
}

final class _IndexedVirtualWindow {
  const _IndexedVirtualWindow({
    required this.epoch,
    required this.scrollOffset,
    required this.progress,
    this.direction = 1,
    this.cruiseOpacity = 0,
  });

  final int epoch;
  final double scrollOffset;
  final double progress;
  final double direction;
  final double cruiseOpacity;
}

final class _IndexedLayoutAnchor {
  const _IndexedLayoutAnchor.item({
    required this.key,
    required this.index,
    required this.viewportOffset,
  }) : trailing = false;

  const _IndexedLayoutAnchor.trailing()
      : key = null,
        index = 0,
        viewportOffset = 0,
        trailing = true;

  final Object? key;
  final int index;
  final double viewportOffset;
  final bool trailing;
}

final class _InitialTargetLayoutDecision {
  const _InitialTargetLayoutDecision.resolved({
    required this.correction,
    required this.dataRevision,
  }) : failure = null;

  const _InitialTargetLayoutDecision.failure(
    this.failure, {
    this.dataRevision,
  }) : correction = null;

  final double? correction;
  final ScrollOutcome? failure;
  final int? dataRevision;
}

ScrollOutcome _outcomeForInitialResolution(ScrollResolutionStatus status) =>
    switch (status) {
      ScrollResolutionStatus.resolved => ScrollOutcome.completed,
      ScrollResolutionStatus.targetNotLoaded => ScrollOutcome.targetNotLoaded,
      ScrollResolutionStatus.targetDeleted => ScrollOutcome.targetDeleted,
      ScrollResolutionStatus.targetOutOfRange => ScrollOutcome.targetOutOfRange,
      ScrollResolutionStatus.resolverRejected => ScrollOutcome.resolverRejected,
      ScrollResolutionStatus.unsupported => ScrollOutcome.unsupported,
    };

int _finiteItemCount(SeekoIndexDelegate<Object> delegate) {
  final int? itemCount = delegate.itemCount;
  if (itemCount == null) {
    throw StateError(
      'SeekoIndexedSliver requires a finite itemCount. '
      'Open data is handled by the paging driver.',
    );
  }
  return itemCount;
}
