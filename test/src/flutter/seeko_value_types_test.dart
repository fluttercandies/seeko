import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('two-dimensional value objects expose geometry and identity', () {
    expect(() => SeekoCellCoordinate(-1, 0), throwsRangeError);
    expect(() => SeekoCellTarget.cell(0, -1), throwsRangeError);

    final SeekoCellCoordinate coordinate = SeekoCellCoordinate(2, 3);
    expect(coordinate, SeekoCellCoordinate(2, 3));
    expect(coordinate.toString(), 'SeekoCellCoordinate(2, 3)');
    expect(SeekoCellCoordinate.zero, isNot(coordinate));

    final SeekoCellTarget cell = SeekoCellTarget.cell(2, 3);
    final SeekoCellTarget sameCell = SeekoCellTarget.cell(2, 3);
    final SeekoCellTarget key = SeekoCellTarget.key('cell-2-3');
    expect(cell.coordinate, coordinate);
    expect(cell.key, isNull);
    expect(cell, sameCell);
    expect(cell.toString(), 'SeekoCellTarget.cell(2, 3)');
    expect(key.coordinate, isNull);
    expect(key.key, 'cell-2-3');
    expect(key.toString(), 'SeekoCellTarget.key(cell-2-3)');
    expect(key, SeekoCellTarget.key('cell-2-3'));
    expect(key, isNot(cell));

    const SeekoTwoDimensionalPlacement placement = SeekoTwoDimensionalPlacement(
      vertical: SeekoAxisPlacement.end,
      horizontal: SeekoAxisPlacement.start,
      verticalOffset: 4,
      horizontalOffset: -2,
    );
    expect(placement.vertical, SeekoAxisPlacement.end);
    expect(placement.horizontal, SeekoAxisPlacement.start);
    expect(placement.verticalOffset, 4);
    expect(placement.horizontalOffset, -2);
    const SeekoTwoDimensionalPlacement nearest =
        SeekoTwoDimensionalPlacement.nearest();
    const SeekoTwoDimensionalPlacement center =
        SeekoTwoDimensionalPlacement.center();
    expect(nearest.vertical, SeekoAxisPlacement.nearest);
    expect(center.horizontal, SeekoAxisPlacement.center);

    final SeekoExtentTable fixed = SeekoExtentTable.fixed(count: 3, extent: 10);
    expect(fixed.extentAt(1), 10);
    expect(fixed.offsetOf(2), 20);
    expect(fixed.indexAt(0), 0);
    expect(fixed.indexAt(99), 2);
    expect(fixed.totalExtent, 30);
    expect(() => fixed.extentAt(3), throwsRangeError);
    expect(() => fixed.offsetOf(4), throwsRangeError);
    expect(() => fixed.indexAt(-1), throwsArgumentError);
    expect(() => fixed.indexAt(double.infinity), throwsArgumentError);
    expect(
      () => SeekoExtentTable.fixed(count: -1, extent: 10),
      throwsRangeError,
    );
    expect(
      () => SeekoExtentTable.fixed(count: 1, extent: 0),
      throwsArgumentError,
    );

    final SeekoExtentTable variable = SeekoExtentTable.variable(<double>[4, 6]);
    expect(variable.extentAt(0), 4);
    expect(variable.offsetOf(2), 10);
    expect(variable.indexAt(0), 0);
    expect(variable.indexAt(4), 1);
    expect(variable.indexAt(100), 1);
    expect(
      () => SeekoExtentTable.variable(<double>[double.nan]),
      throwsArgumentError,
    );

    final SeekoFiniteTwoDimensionalLayout layout =
        SeekoFiniteTwoDimensionalLayout.variable(
      rowExtents: <double>[20, 30],
      columnExtents: <double>[40, 50],
      keyAt: (int row, int column) => '$row:$column',
      coordinateOfKey: (Object value) {
        final String text = value as String;
        if (!text.contains(':')) {
          return null;
        }
        final List<int> parts = text.split(':').map(int.parse).toList();
        return SeekoCellCoordinate(parts[0], parts[1]);
      },
    );
    final SeekoCellGeometry geometry = layout.geometryFor(
      SeekoCellCoordinate(1, 0),
    );
    expect(geometry.left, 0);
    expect(geometry.top, 20);
    expect(geometry.right, 40);
    expect(geometry.bottom, 50);
    expect(geometry.rect, const Rect.fromLTWH(0, 20, 40, 30));
    expect(geometry.key, '1:0');
    expect(layout.rowCount, 2);
    expect(layout.columnCount, 2);
    expect(layout.rowAtOffset(25), 1);
    expect(layout.columnAtOffset(45), 1);
    expect(layout.coordinateOfKey('1:0'), SeekoCellCoordinate(1, 0));
    expect(layout.coordinateOfKey('missing'), isNull);

    final SeekoVisibleCell visible = SeekoVisibleCell(
      coordinate: SeekoCellCoordinate(1, 0),
      rect: geometry.rect,
      visibleFraction: 0.5,
      key: '1:0',
    );
    expect(
        visible,
        isNot(SeekoVisibleCell(
          coordinate: SeekoCellCoordinate.zero,
          rect: Rect.zero,
          visibleFraction: 1,
        )));
    expect(visible.hashCode, isNot(0));

    const SeekoTwoDimensionalSnapshot detached =
        SeekoTwoDimensionalSnapshot.detached();
    expect(detached.horizontalProgress, 0);
    expect(detached.verticalProgress, 0);
    final SeekoTwoDimensionalSnapshot snapshot = SeekoTwoDimensionalSnapshot(
      horizontalPixels: 5,
      verticalPixels: 10,
      horizontalMax: 20,
      verticalMax: 40,
      viewportSize: const Size(100, 80),
      visibleCells: <SeekoVisibleCell>[visible],
      phase: ScrollCommandPhase.moving,
      activeCommandId: 7,
      userScrollDirection: ScrollDirection.reverse,
    );
    expect(snapshot.horizontalProgress, 0.25);
    expect(snapshot.verticalProgress, 0.25);
    expect(snapshot, snapshot);
    expect(snapshot.hashCode, isNot(0));
    expect(snapshot, isNot(detached));
  });

  test('two-dimensional controller reports detached and invalid paths',
      () async {
    final SeekoTwoDimensionalController controller =
        SeekoTwoDimensionalController(
      layout: SeekoFiniteTwoDimensionalLayout.fixed(
        rowCount: 2,
        columnCount: 2,
      ),
      viewportSize: const Size(80, 80),
    );
    expect(controller.verticalController, same(controller.vertical));
    expect(controller.horizontalController, same(controller.horizontal));
    expect(controller.obstruction.left, 0);
    expect(
      (await controller.jumpToCell(SeekoCellTarget.cell(9, 9))).outcome,
      ScrollOutcome.detached,
    );
    expect(
      (await controller.jumpToCell(SeekoCellTarget.key('missing'))).outcome,
      ScrollOutcome.detached,
    );
    expect(
      (await controller.jumpTo(horizontalPixels: 5)).outcome,
      ScrollOutcome.detached,
    );
    expect(
      (await controller.animateTo(horizontalPixels: 5, verticalPixels: 5))
          .outcome,
      ScrollOutcome.detached,
    );
    expect(
      (await controller.ensureCellVisible(SeekoCellTarget.cell(0, 0))).outcome,
      ScrollOutcome.detached,
    );
    expect(
      () => controller.setViewportSize(const Size(double.nan, 10)),
      throwsArgumentError,
    );
    expect(
      () => controller.setViewportSize(const Size(-1, 10)),
      throwsArgumentError,
    );
    await expectLater(
      controller.animateTo(
          horizontalPixels: double.infinity, verticalPixels: 0),
      throwsArgumentError,
    );
    controller.setLayout(null);
    controller.setViewportSize(const Size(100, 100));
    controller.setObstruction(const SeekoTwoDimensionalObstruction(
      left: 2,
      top: 3,
      right: 4,
      bottom: 5,
    ));
    controller.stop();
    controller.dispose();
    controller.dispose();
  });

  test('two-dimensional sync group validates membership and lifecycle',
      () async {
    final SeekoTwoDimensionalSyncGroup group = SeekoTwoDimensionalSyncGroup(
      mode: SeekoTwoDimensionalSyncMode.pixels,
    );
    final SeekoTwoDimensionalController first = SeekoTwoDimensionalController();
    final SeekoTwoDimensionalController second =
        SeekoTwoDimensionalController();
    expect(group.length, 0);
    expect(group.remove(first), isFalse);
    group.add(first);
    expect(group.length, 1);
    expect(group.controllers, contains(first));
    expect(() => group.add(first), throwsStateError);
    expect(
      () => group.add(
        second,
        member: const SeekoTwoDimensionalSyncMember(
          horizontal: false,
          vertical: false,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      (await group.animateToCell(SeekoCellTarget.cell(0, 0))).outcome,
      ScrollOutcome.detached,
    );
    expect(group.remove(first), isTrue);
    expect(group.leader, isNull);
    group.dispose();
    expect(() => group.add(second), throwsStateError);
    first.dispose();
    second.dispose();
  });

  test('table and tree metadata support mutation and keyboard policy', () {
    final List<SeekoTableColumn<String>> columns = <SeekoTableColumn<String>>[
      const SeekoTableColumn<String>(key: 'name', width: 100),
      const SeekoTableColumn<String>(
        key: 'locked',
        width: 80,
        resizable: false,
        semanticLabel: 'Locked column',
      ),
    ];
    final SeekoTableLayout<int, String> layout = SeekoTableLayout<int, String>(
      rowCount: 3,
      rowExtents: <double>[20, 30, 40],
      columns: columns,
      rowKeyAt: (int row) => row,
      rowIndexOf: (int key) => key >= 0 && key < 3 ? key : null,
      frozenPanes: const SeekoFrozenPaneConfiguration(rows: 1, columns: 1),
    );
    expect(layout.frozenPanes.isEmpty, isFalse);
    expect(layout.rowOffset(2), 50);
    expect(layout.rowAtOffset(51), 2);
    expect(layout.columnOffset(1), 100);
    expect(
      layout.keyAt(1, 0),
      const SeekoTableCellKey<int, String>(1, 'name'),
    );
    expect(
      layout.coordinateOfKey(
        const SeekoTableCellKey<int, String>(1, 'name'),
      ),
      SeekoCellCoordinate(1, 0),
    );
    expect(
      layout.coordinateOfKey(
        const SeekoTableCellKey<int, String>(9, 'name'),
      ),
      isNull,
    );
    expect(layout.coordinateOfKey('not-a-cell'), isNull);
    expect(() => layout.resizeColumn('missing', 90), throwsStateError);
    expect(() => layout.resizeColumn('locked', 90), throwsStateError);
    expect(layout.resizeColumn('name', 120), 20);
    expect(layout.totalWidth, 200);
    expect(
      () => layout.reorderColumns(<String>['name']),
      throwsArgumentError,
    );
    expect(
      () => layout.reorderColumns(<String>['name', 'unknown']),
      throwsArgumentError,
    );
    layout.reorderColumns(<String>['locked', 'name']);
    expect(layout.columns.first.key, 'locked');
    expect(layout.columnOffset(1), 80);
    layout.dispose();

    expect(
      () => SeekoTableLayout<int, String>(
        rowCount: 2,
        rowExtents: const <double>[20],
        columns: columns,
        rowKeyAt: (int row) => row,
        rowIndexOf: (int key) => key,
      ),
      throwsArgumentError,
    );
    expect(
      () => SeekoTableNavigationController(rowCount: 0, columnCount: 1),
      throwsRangeError,
    );
    final SeekoTableNavigationController navigation =
        SeekoTableNavigationController(
      rowCount: 4,
      columnCount: 3,
      initial: SeekoCellCoordinate(9, 9),
    );
    expect(navigation.current, SeekoCellCoordinate(3, 2));
    for (final SeekoTableNavigationIntent intent
        in SeekoTableNavigationIntent.values) {
      navigation.move(intent, visibleRows: 2);
    }
    expect(navigation.target.coordinate, navigation.current);
    expect(
      navigation.select(SeekoCellCoordinate.zero),
      SeekoCellCoordinate.zero,
    );
    navigation.dispose();

    final Map<String, SeekoTreeNodeDescriptor<String>> nodes =
        <String, SeekoTreeNodeDescriptor<String>>{
      'root': const SeekoTreeNodeDescriptor<String>(
        key: 'root',
        children: <String>['leaf'],
        semanticLabel: 'Root',
      ),
      'leaf': const SeekoTreeNodeDescriptor<String>(
        key: 'leaf',
        children: <String>[],
        extent: 24,
        semanticLabel: 'Leaf',
      ),
    };
    final SeekoTreeTableController<String> tree =
        SeekoTreeTableController<String>(
      roots: const <String>['root'],
      resolveNode: (String key) => nodes[key]!,
    );
    expect(tree.captureAnchor('missing'), isNull);
    expect(
      () => tree.captureAnchor('root', viewportOffset: double.nan),
      throwsArgumentError,
    );
    expect(tree.setExpanded('leaf', true).visibleRowCount, 1);
    expect(tree.toggle('root').visibleRowCount, 2);
    expect(tree.visibleRows.last.semanticLabel, 'Leaf');
    expect(tree.replaceRoots(const <String>['leaf']).visibleRowCount, 1);
    expect(tree.expandedKeys, isNotEmpty);
    tree.dispose();
  });

  test('scroll snapshot value objects compare structural state', () {
    final ScrollVisibleTarget partial = ScrollVisibleTarget(
      key: 'one',
      index: 1,
      leadingPixels: 0,
      trailingPixels: 20,
      leadingViewportFraction: 0,
      trailingViewportFraction: 0.5,
      visibleFraction: 0.5,
    );
    final ScrollVisibleTarget full = ScrollVisibleTarget(
      key: 'two',
      index: 2,
      leadingPixels: 20,
      trailingPixels: 40,
      leadingViewportFraction: 0.5,
      trailingViewportFraction: 1,
      visibleFraction: 1,
    );
    expect(partial.isFullyVisible, isFalse);
    expect(full.isFullyVisible, isTrue);
    expect(partial, isNot(full));
    expect(
        partial,
        ScrollVisibleTarget(
          key: 'one',
          index: 1,
          leadingPixels: 0,
          trailingPixels: 20,
          leadingViewportFraction: 0,
          trailingViewportFraction: 0.5,
          visibleFraction: 0.5,
        ));

    const ScrollSemanticAnchor anchor = ScrollSemanticAnchor(
      key: 'one',
      index: 1,
      itemAnchor: 0.25,
      viewportAnchor: 0.5,
      logicalOffset: 4,
    );
    const ScrollRawEvent raw = ScrollRawEvent(
      sequence: 3,
      pixels: 40,
      velocity: 20,
      phase: ScrollPhase.programmatic,
      origin: ScrollEventOrigin.programmatic,
      commandId: 8,
      syncTransactionId: 9,
    );
    expect(anchor.hashCode, isNot(0));
    expect(raw.sequence, 3);
    expect(raw.phase, ScrollPhase.programmatic);

    const ScrollExtentSnapshot extent = ScrollExtentSnapshot(
      itemCount: 10,
      measuredItemCount: 4,
      measuredExtent: 80,
      estimatedExtent: 120,
      sourceCount: 10,
      reportedSourceCount: 10,
    );
    expect(extent.estimatedItemCount, 6);
    expect(extent.totalExtent, 200);
    expect(extent.estimateConfidence, 0.4);
    expect(extent.isComplete, isTrue);
    const ScrollExtentSnapshot emptyExtent = ScrollExtentSnapshot(
      itemCount: 0,
      measuredItemCount: 0,
      measuredExtent: 0,
      estimatedExtent: 0,
      sourceCount: 0,
      reportedSourceCount: 0,
    );
    expect(emptyExtent.estimateConfidence, 1);

    final ScrollSnapshot snapshot = ScrollSnapshot(
      pixels: 40,
      minScrollExtent: 0,
      maxScrollExtent: 200,
      viewportExtent: 80,
      progress: 0.2,
      axis: Axis.vertical,
      axisDirection: AxisDirection.down,
      userScrollDirection: ScrollDirection.forward,
      velocity: 20,
      phase: ScrollPhase.programmatic,
      origin: ScrollEventOrigin.programmatic,
      atLeadingEdge: false,
      atTrailingEdge: false,
      visibleTargets: <ScrollVisibleTarget>[partial, full],
      anchor: anchor,
      activeCommandId: 8,
      synchronized: true,
      syncTransactionId: 9,
      pendingMetricsCorrection: true,
      dataRevision: 2,
      effectiveViewportIntervals: const <LogicalInterval>[
        LogicalInterval(0, 40),
      ],
      extent: extent,
    );
    expect(snapshot.firstVisibleTarget, partial);
    expect(snapshot.lastVisibleTarget, full);
    expect(snapshot, snapshot);
    expect(snapshot.hashCode, isNot(0));
    expect(snapshot, isNot(const ScrollSnapshot.detached()));
    expect(const ScrollSnapshot.detached().firstVisibleTarget, isNull);
    final ScrollSnapshotNotifier notifier = ScrollSnapshotNotifier();
    expect(notifier.value, const ScrollSnapshot.detached());
    notifier.dispose();
  });

  test('core target and driver result value contracts cover failures',
      () async {
    final List<ScrollResolutionStatus> statuses = <ScrollResolutionStatus>[
      ScrollResolutionStatus.targetNotLoaded,
      ScrollResolutionStatus.targetDeleted,
      ScrollResolutionStatus.targetOutOfRange,
      ScrollResolutionStatus.resolverRejected,
      ScrollResolutionStatus.unsupported,
    ];
    final List<ScrollResolution> failures = <ScrollResolution>[
      const ScrollResolution.targetNotLoaded(),
      const ScrollResolution.targetDeleted(),
      const ScrollResolution.targetOutOfRange(),
      const ScrollResolution.resolverRejected(
        diagnostics: <String, Object?>{'reason': 'invalid'},
      ),
      const ScrollResolution.unsupported(),
    ];
    expect(failures.map((ScrollResolution value) => value.status), statuses);
    expect(
        failures.every((ScrollResolution value) => !value.isResolved), isTrue);
    final ScrollResolution resolved = ScrollResolution.resolved(
      target: ScrollTarget.key('item'),
      logicalPixels: 12,
      mode: ScrollResolutionMode.estimated,
      dataRevision: 3,
      diagnostics: const <String, Object?>{'source': 'index'},
    );
    expect(resolved.isResolved, isTrue);
    expect(resolved == resolved, isTrue);
    expect(resolved.hashCode, isNot(0));

    final List<ScrollCustomTargetResolution> customFailures =
        <ScrollCustomTargetResolution>[
      const ScrollCustomTargetResolution.targetNotLoaded(),
      const ScrollCustomTargetResolution.targetDeleted(),
      const ScrollCustomTargetResolution.targetOutOfRange(),
      const ScrollCustomTargetResolution.resolverRejected(),
      const ScrollCustomTargetResolution.unsupported(),
    ];
    expect(
      customFailures.every(
        (ScrollCustomTargetResolution value) => !value.isResolved,
      ),
      isTrue,
    );
    const ScrollCustomTargetResolution customResolved =
        ScrollCustomTargetResolution.resolved(
      targetInterval: LogicalInterval(10, 30),
      mode: ScrollResolutionMode.searched,
      dataRevision: 4,
    );
    expect(customResolved.isResolved, isTrue);
    expect(customResolved.targetInterval!.extent, 20);

    expect(ScrollTarget.offset(12).toString(), 'ScrollTarget.offset(12.0)');
    expect(ScrollTarget.index(4).toString(), 'ScrollTarget.index(4)');
    expect(
      ScrollTarget.index(4, tracking: IndexTracking.liveSlot).toString(),
      contains('liveSlot'),
    );
    expect(ScrollTarget.key('x').toString(), 'ScrollTarget.key(x)');
    expect(
        const ScrollTarget.edge(ScrollEdge.leading).edge, ScrollEdge.leading);
    expect(ScrollTarget.progress(0.5).toString(),
        contains('ProgressScrollTarget'));
    expect(ScrollTarget.custom('x').toString(), contains('CustomScrollTarget'));

    final ScrollDriverResult success = const ScrollDriverResult(
      finalLogicalPixels: 10,
      finalError: 0,
    );
    final ScrollDriverResult clamped = const ScrollDriverResult(
      finalLogicalPixels: 8,
      finalError: 2,
      outcome: ScrollOutcome.clamped,
      clamped: true,
      clampReason: 'extent',
      correctionCount: 1,
      replanCount: 2,
      endRevision: 5,
    );
    expect(success.isSuccess, isTrue);
    expect(clamped.isSuccess, isTrue);
    expect(clamped.clampReason, 'extent');
    expect(
        const ScrollDriverResult(
          finalLogicalPixels: 0,
          finalError: 0,
          outcome: ScrollOutcome.cancelled,
        ).isSuccess,
        isFalse);

    final DeterministicScrollClock clock = DeterministicScrollClock();
    expect(() => clock.delay(const Duration(milliseconds: -1)),
        throwsArgumentError);
    expect(() => clock.elapse(const Duration(milliseconds: -1)),
        throwsArgumentError);
    expect(SystemScrollClock().now, isA<Duration>());
    await clock.delay(Duration.zero);
  });

  test('motion planning and placement cover every public policy', () {
    const AdaptiveMotionPlanner planner = AdaptiveMotionPlanner();
    const Duration frame = Duration(microseconds: 8333);
    final ScrollMotionPlan adaptive = planner.plan(
      distance: 2000,
      viewportExtent: 100,
      frameInterval: frame,
    );
    expect(adaptive.requiresWindowRebase, isTrue);
    expect(adaptive.positionAt(Duration.zero), 0);
    expect(adaptive.positionAt(adaptive.duration), 2000);
    expect(
      planner
          .plan(
            distance: 100,
            viewportExtent: 100,
            frameInterval: frame,
            motion: const ScrollMotion.velocity(pixelsPerSecond: 500),
          )
          .duration,
      isNot(Duration.zero),
    );
    expect(
      planner
          .plan(
            distance: 100,
            viewportExtent: 100,
            frameInterval: frame,
            motion: const ScrollMotion.spring(),
          )
          .curve,
      isA<Curve>(),
    );
    expect(
      planner
          .plan(
            distance: 100,
            viewportExtent: 100,
            frameInterval: frame,
            motion: const ScrollMotion.duration(
              duration: Duration(milliseconds: 200),
              curve: Curves.linear,
            ),
          )
          .duration,
      const Duration(milliseconds: 200),
    );
    expect(
      planner
          .plan(
            distance: 100,
            viewportExtent: 100,
            frameInterval: frame,
            reducedMotion: true,
          )
          .duration,
      Duration.zero,
    );
    expect(
      () => planner.plan(
        distance: double.nan,
        viewportExtent: 100,
        frameInterval: frame,
      ),
      throwsArgumentError,
    );
    expect(
      () => planner.plan(
        distance: 1,
        viewportExtent: 0,
        frameInterval: frame,
      ),
      throwsArgumentError,
    );
    expect(
      () => planner.plan(
        distance: 1,
        viewportExtent: 100,
        frameInterval: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => planner.plan(
        distance: 1,
        viewportExtent: 100,
        frameInterval: frame,
        motion: const ScrollMotion.velocity(pixelsPerSecond: 0),
      ),
      throwsArgumentError,
    );

    final VisibleRegion region = VisibleRegion.fromIntervals(
      const <LogicalInterval>[
        LogicalInterval(0, 40),
        LogicalInterval(60, 100),
      ],
    );
    final ScrollPlacementResolution exact = resolveScrollPlacement(
      placement: ScrollPlacement.exact(
        targetAnchor: 0.5,
        viewportAnchor: 0.5,
        viewportInterval: const ScrollViewportInterval.at(1),
      ),
      target: const LogicalInterval(150, 170),
      visibleRegion: region,
      currentPixels: 0,
    );
    expect(exact.pixels, 80);
    expect(exact.alreadySatisfied, isFalse);
    expect(
      resolveScrollPlacement(
        placement: const ScrollPlacement.nearest(),
        target: const LogicalInterval(10, 20),
        visibleRegion: region,
        currentPixels: 0,
      ).alreadySatisfied,
      isTrue,
    );
    expect(
      resolveScrollPlacement(
        placement: const ScrollPlacement.visible(),
        target: const LogicalInterval(45, 65),
        visibleRegion: region,
        currentPixels: 0,
      ).alreadySatisfied,
      isTrue,
    );
    expect(
      () => resolveScrollPlacement(
        placement: const ScrollPlacement.start(),
        target: const LogicalInterval(0, 1),
        visibleRegion: region,
        currentPixels: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => resolveScrollPlacement(
        placement: const ScrollPlacement.start(),
        target: const LogicalInterval(0, 1),
        visibleRegion: VisibleRegion.fromIntervals(
          const <LogicalInterval>[],
        ),
        currentPixels: 0,
      ),
      throwsStateError,
    );
  });
}
