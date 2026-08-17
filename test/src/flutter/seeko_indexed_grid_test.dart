import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  final List<({Axis axis, bool reverse, TextDirection textDirection})>
      directionCases =
      <({Axis axis, bool reverse, TextDirection textDirection})>[
    (axis: Axis.vertical, reverse: false, textDirection: TextDirection.ltr),
    (axis: Axis.vertical, reverse: true, textDirection: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: false, textDirection: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: true, textDirection: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: false, textDirection: TextDirection.rtl),
    (axis: Axis.horizontal, reverse: true, textDirection: TextDirection.rtl),
  ];

  for (final config in directionCases) {
    testWidgets(
      'grid start placement uses logical leading for ${config.axis.name} '
      'reverse=${config.reverse} ${config.textDirection.name}',
      (WidgetTester tester) async {
        final ValueNotifier<int> revision = ValueNotifier<int>(0);
        final SeekoController controller = SeekoController();
        const Key viewportKey = ValueKey<String>('grid-viewport');
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: config.textDirection,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  height: 240,
                  child: CustomScrollView(
                    key: viewportKey,
                    controller: controller,
                    scrollDirection: config.axis,
                    reverse: config.reverse,
                    slivers: <Widget>[
                      SeekoIndexedGridSliver(
                        controller: controller,
                        indexDelegate: ListSeekoIndexDelegate<int>(
                          itemCount: 1000,
                          revision: revision,
                          keyAt: (int index) => index,
                          indexOfKey: (int key) => key,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisExtent: 60,
                          mainAxisSpacing: 4,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, int index) => SizedBox(
                            key: ValueKey<int>(index),
                            child: Text('Cell $index'),
                          ),
                          childCount: 1000,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final ScrollResult result = await pumpScrollCommand(
          tester,
          controller.jumpToIndex(
            300,
            placement: const ScrollPlacement.start(),
          ),
        );

        final Rect targetRect =
            tester.getRect(find.byKey(const ValueKey<int>(300)));
        final Rect viewportRect = tester.getRect(find.byKey(viewportKey));
        final bool physicalLeadingAtStart = config.axis == Axis.vertical
            ? !config.reverse
            : config.reverse == (config.textDirection == TextDirection.rtl);
        final double targetLeading = config.axis == Axis.vertical
            ? (physicalLeadingAtStart ? targetRect.top : targetRect.bottom)
            : (physicalLeadingAtStart ? targetRect.left : targetRect.right);
        final double viewportLeading = config.axis == Axis.vertical
            ? (physicalLeadingAtStart ? viewportRect.top : viewportRect.bottom)
            : (physicalLeadingAtStart ? viewportRect.left : viewportRect.right);
        expect(result.outcome, ScrollOutcome.completed);
        expect(targetLeading, closeTo(viewportLeading, 0.5));

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        revision.dispose();
      },
    );
  }

  testWidgets('fixed grid jumps to an unmounted cell and reports visibility', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    final SeekoIndexDelegate<String> indexDelegate =
        ListSeekoIndexDelegate<String>(
      itemCount: 1000,
      revision: revision,
      keyAt: (int index) => 'cell-$index',
      indexOfKey: (String key) => int.tryParse(key.substring(5)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedGridSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 60,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, int index) => SizedBox(
                  key: ValueKey<String>('cell-$index'),
                  child: Text('Cell $index'),
                ),
                childCount: 1000,
              ),
            ),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(
        300,
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 20,
    );
    await tester.pump();

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('cell-300'));
    expect(controller.offset, closeTo(6400, 0.5));
    expect(find.byKey(const ValueKey<String>('cell-300')), findsOneWidget);
    expect(
      controller.state.value.visibleTargets
          .any((ScrollVisibleTarget target) => target.index == 300),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('grid visibility reports every cell after obstruction', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController(
      obstructionResolver: (_) => VisibleRegion.fromIntervals(
        const <LogicalInterval>[LogicalInterval(20, 100)],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 100,
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedGridSliver(
                  controller: controller,
                  indexDelegate: ListSeekoIndexDelegate<int>(
                    itemCount: 100,
                    revision: revision,
                    keyAt: (int index) => index,
                    indexOfKey: (int key) => key,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisExtent: 60,
                    mainAxisSpacing: 4,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, int index) => Text('Cell $index'),
                    childCount: 100,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.offset(30)),
    );
    await tester.pump();
    final Map<int, ScrollVisibleTarget> visible = <int, ScrollVisibleTarget>{
      for (final ScrollVisibleTarget target
          in controller.state.value.visibleTargets)
        target.index!: target,
    };

    for (final int index in <int>[0, 1, 2]) {
      expect(visible[index]!.visibleFraction, closeTo(1 / 6, 1e-6));
    }
    for (final int index in <int>[3, 4, 5]) {
      expect(visible[index]!.visibleFraction, 1);
    }
    for (final int index in <int>[6, 7, 8]) {
      expect(visible[index]!.visibleFraction, closeTo(1 / 30, 1e-6));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('grid cells participate in the target loader revision pipeline', (
    WidgetTester tester,
  ) async {
    final _PagedGridIndexDelegate indexDelegate =
        _PagedGridIndexDelegate(loadedCount: 10);
    final SeekoController controller = SeekoController(
      targetLoader: CallbackScrollTargetLoader((request) {
        indexDelegate.loadThrough(100);
        return ScrollTargetLoadResult.loaded(
          revision: indexDelegate.revision,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 300,
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedGridSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisExtent: 60,
                    mainAxisSpacing: 4,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, int index) => Text('Remote cell $index'),
                    childCount: 100,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(
        80,
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('remote-80'));
    expect(result.startRevision, 0);
    expect(result.endRevision, 1);
    expect(controller.offset, closeTo(1280, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('global indexes span indexed list and grid slivers', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: ListSeekoIndexDelegate<String>(
                itemCount: 6,
                revision: revision,
                keyAt: (int index) => 'list-$index',
                indexOfKey: (String key) => key.startsWith('list-')
                    ? int.tryParse(key.substring(5))
                    : null,
              ),
              estimatedExtent: 50,
              delegate: SliverChildBuilderDelegate(
                (_, int index) => SizedBox(
                  height: 50,
                  child: Text('List $index'),
                ),
                childCount: 6,
              ),
            ),
            SeekoIndexedGridSliver(
              controller: controller,
              indexDelegate: ListSeekoIndexDelegate<String>(
                itemCount: 100,
                revision: revision,
                keyAt: (int index) => 'grid-$index',
                indexOfKey: (String key) => key.startsWith('grid-')
                    ? int.tryParse(key.substring(5))
                    : null,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 60,
                mainAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, int index) => Text('Grid $index'),
                childCount: 100,
              ),
            ),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(
        15,
        placement: const ScrollPlacement.start(),
      ),
    );
    await tester.pump();

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('grid-9'));
    expect(controller.offset, closeTo(492, 0.5));
    expect(
      controller.state.value.visibleTargets.any(
        (ScrollVisibleTarget target) =>
            target.key == 'grid-9' && target.index == 15,
      ),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('grid initial target is positioned before the first paint', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController(
      initialTarget: ScrollTarget.index(90),
      initialPlacement: const ScrollPlacement.start(),
    );
    final Future<SeekoInitialTargetResult> initial =
        controller.initialTargetResult!;
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedGridSliver(
              controller: controller,
              indexDelegate: ListSeekoIndexDelegate<String>(
                itemCount: 300,
                revision: revision,
                keyAt: (int index) => 'cell-$index',
                indexOfKey: (String key) => int.tryParse(key.substring(5)),
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 60,
                mainAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, int index) => Text('Cell $index'),
                childCount: 300,
              ),
            ),
          ],
        ),
      ),
    );

    final SeekoInitialTargetResult result = await pumpScrollCommand(
      tester,
      initial,
      maxFrames: 10,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalLogicalPixels, closeTo(1920, 0.5));
    expect(controller.offset, closeTo(1920, 0.5));
    expect(find.text('Cell 0'), findsNothing);
    expect(find.text('Cell 90'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('custom variable grid geometry resolves a stable cell key', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedGridSliver(
              controller: controller,
              indexDelegate: ListSeekoIndexDelegate<String>(
                itemCount: 100,
                revision: revision,
                keyAt: (int index) => 'variable-$index',
                indexOfKey: (String key) => int.tryParse(key.substring(9)),
              ),
              gridDelegate: const _VariableGridDelegate(),
              delegate: SliverChildBuilderDelegate(
                (_, int index) => Text('Variable $index'),
                childCount: 100,
              ),
            ),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'variable-40',
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(1280, 0.5));
    expect(find.text('Variable 40'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('invalid custom cell geometry is rejected without scrolling', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedGridSliver(
              controller: controller,
              indexDelegate: ListSeekoIndexDelegate<int>(
                itemCount: 1000,
                revision: revision,
                keyAt: (int index) => index,
                indexOfKey: (int key) => key,
              ),
              gridDelegate: const _InvalidTargetGridDelegate(),
              delegate: SliverChildBuilderDelegate(
                (_, int index) => Text('Cell $index'),
                childCount: 1000,
              ),
            ),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(300),
    );

    expect(result.outcome, ScrollOutcome.resolverRejected);
    expect(controller.offset, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets(
    'finite grid rejects an index delegate and child count mismatch',
    (WidgetTester tester) async {
      final ValueNotifier<int> revision = ValueNotifier<int>(0);
      final SeekoController controller = SeekoController();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomScrollView(
            controller: controller,
            slivers: <Widget>[
              SeekoIndexedGridSliver(
                controller: controller,
                indexDelegate: ListSeekoIndexDelegate<int>(
                  itemCount: 1000,
                  revision: revision,
                  keyAt: (int index) => index,
                  indexOfKey: (int key) => key,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 60,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, int index) => Text('Cell $index'),
                  childCount: 100,
                ),
              ),
            ],
          ),
        ),
      );

      final ScrollResult result = await pumpScrollCommand(
        tester,
        controller.jumpToIndex(300),
      );

      expect(result.outcome, ScrollOutcome.resolverRejected);
      expect(controller.offset, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      revision.dispose();
    },
  );

  testWidgets('head insertion preserves the visible grid cell anchor', (
    WidgetTester tester,
  ) async {
    final _MutableGridIndexDelegate indexDelegate = _MutableGridIndexDelegate();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: ListenableBuilder(
            listenable: indexDelegate.changes,
            builder: (BuildContext context, Widget? child) {
              return CustomScrollView(
                controller: controller,
                slivers: <Widget>[
                  SeekoIndexedGridSliver(
                    controller: controller,
                    indexDelegate: indexDelegate,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisExtent: 60,
                      mainAxisSpacing: 4,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, int index) {
                        final String key = indexDelegate.keyAt(index);
                        return SizedBox(
                          key: ValueKey<String>(key),
                          child: Text(key),
                        );
                      },
                      childCount: indexDelegate.itemCount,
                      findChildIndexCallback: (Key key) => indexDelegate
                          .indexOf((key as ValueKey<String>).value),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'cell-30',
        placement: const ScrollPlacement.start(),
      ),
    );
    final double before =
        tester.getTopLeft(find.byKey(const ValueKey<String>('cell-30'))).dy;

    indexDelegate.prepend(3);
    await tester.pump();
    await tester.pump();

    final double after =
        tester.getTopLeft(find.byKey(const ValueKey<String>('cell-30'))).dy;
    expect(after, closeTo(before, 0.5));
    expect(controller.offset, closeTo(704, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('responsive column changes preserve the visible cell anchor', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ValueNotifier<double> width = ValueNotifier<double>(400);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ListenableBuilder(
            listenable: width,
            builder: (BuildContext context, Widget? child) {
              return SizedBox(
                width: width.value,
                height: 300,
                child: CustomScrollView(
                  controller: controller,
                  slivers: <Widget>[
                    SeekoIndexedGridSliver(
                      controller: controller,
                      indexDelegate: ListSeekoIndexDelegate<int>(
                        itemCount: 300,
                        revision: revision,
                        keyAt: (int index) => index,
                        indexOfKey: (int key) => key,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 120,
                        mainAxisExtent: 60,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, int index) => SizedBox(
                          key: ValueKey<int>(index),
                          child: Text('Cell $index'),
                        ),
                        childCount: 300,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToIndex(
        40,
        placement: const ScrollPlacement.start(),
      ),
    );
    final double before =
        tester.getTopLeft(find.byKey(const ValueKey<int>(40))).dy;

    width.value = 250;
    await tester.pump();
    await tester.pump();

    final double after =
        tester.getTopLeft(find.byKey(const ValueKey<int>(40))).dy;
    expect(after, closeTo(before, 0.5));
    expect(controller.offset, closeTo(832, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
    width.dispose();
  });

  testWidgets('far grid animation does not build intermediate cells', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    var childBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedGridSliver(
              controller: controller,
              indexDelegate: ListSeekoIndexDelegate<int>(
                itemCount: 1000000,
                revision: revision,
                keyAt: (int index) => index,
                indexOfKey: (int key) => key,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 60,
                mainAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, int index) {
                  childBuilds += 1;
                  return Text('Cell $index');
                },
                childCount: 1000000,
              ),
            ),
          ],
        ),
      ),
    );
    final int buildsBefore = childBuilds;
    final Future<ScrollResult> future = controller.animateToIndex(
      900000,
      placement: const ScrollPlacement.start(),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 240),
        curve: Curves.easeInOutCubic,
      ),
    );
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final ScrollResult result = await pumpScrollCommand(
      tester,
      future,
      maxFrames: 15,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalError, lessThanOrEqualTo(0.5));
    expect(find.text('Cell 900000'), findsOneWidget);
    expect(childBuilds - buildsBefore, lessThan(1800));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('grid sliver releases listeners across 1000 reattachments', (
    WidgetTester tester,
  ) async {
    final _CountingValueNotifier<int> revision = _CountingValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 20,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );

    for (var iteration = 0; iteration < 1000; iteration += 1) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 120,
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedGridSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 40,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, int index) => const SizedBox(),
                    childCount: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(revision.listenerCount, 1, reason: 'attach $iteration');
      expect(controller.positions, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(revision.listenerCount, 0, reason: 'detach $iteration');
      expect(controller.positions, isEmpty);
    }

    controller.dispose();
    revision.dispose();
  });
}

final class _VariableGridDelegate extends SliverGridDelegate {
  const _VariableGridDelegate();

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    return _VariableGridLayout(
      crossAxisExtent: constraints.crossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(
        constraints.crossAxisDirection,
      ),
    );
  }

  @override
  bool shouldRelayout(covariant _VariableGridDelegate oldDelegate) => false;
}

final class _InvalidTargetGridDelegate extends SliverGridDelegate {
  const _InvalidTargetGridDelegate();

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final SliverGridLayout valid =
        const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisExtent: 60,
      mainAxisSpacing: 4,
    ).getLayout(constraints);
    return _InvalidTargetGridLayout(valid);
  }

  @override
  bool shouldRelayout(covariant _InvalidTargetGridDelegate oldDelegate) =>
      false;
}

final class _InvalidTargetGridLayout extends SliverGridLayout {
  const _InvalidTargetGridLayout(this.valid);

  final SliverGridLayout valid;

  @override
  double computeMaxScrollOffset(int childCount) =>
      valid.computeMaxScrollOffset(childCount);

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (index == 300) {
      return const SliverGridGeometry(
        scrollOffset: double.nan,
        crossAxisOffset: 0,
        mainAxisExtent: 60,
        crossAxisExtent: 60,
      );
    }
    return valid.getGeometryForChildIndex(index);
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      valid.getMaxChildIndexForScrollOffset(scrollOffset);

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      valid.getMinChildIndexForScrollOffset(scrollOffset);
}

final class _VariableGridLayout extends SliverGridLayout {
  const _VariableGridLayout({
    required this.crossAxisExtent,
    required this.reverseCrossAxis,
  });

  final double crossAxisExtent;
  final bool reverseCrossAxis;
  static const double _spacing = 4;

  @override
  double computeMaxScrollOffset(int childCount) {
    final int rowCount = (childCount + 1) ~/ 2;
    return rowCount == 0 ? 0 : _offsetForRow(rowCount) - _spacing;
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final int row = index ~/ 2;
    final int column = index % 2;
    final double cellCrossAxisExtent = (crossAxisExtent - _spacing) / 2;
    final double rawCrossAxisOffset = column * (cellCrossAxisExtent + _spacing);
    return SliverGridGeometry(
      scrollOffset: _offsetForRow(row),
      crossAxisOffset: reverseCrossAxis
          ? crossAxisExtent - rawCrossAxisOffset - cellCrossAxisExtent
          : rawCrossAxisOffset,
      mainAxisExtent: row.isEven ? 40 : 80,
      crossAxisExtent: cellCrossAxisExtent,
    );
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      _rowForOffset(scrollOffset) * 2 + 1;

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      _rowForOffset(scrollOffset) * 2;

  int _rowForOffset(double scrollOffset) {
    var row = 0;
    while (_offsetForRow(row + 1) <= scrollOffset) {
      row += 1;
    }
    return row;
  }

  double _offsetForRow(int row) {
    final int pairs = row ~/ 2;
    var result = pairs * (40 + _spacing + 80 + _spacing);
    if (row.isOdd) {
      result += 40 + _spacing;
    }
    return result;
  }
}

final class _MutableGridIndexDelegate implements SeekoIndexDelegate<String> {
  _MutableGridIndexDelegate()
      : _keys = List<String>.generate(100, (int index) => 'cell-$index'),
        _changes = SeekoChangeNotifier();

  final List<String> _keys;
  final SeekoChangeNotifier _changes;
  final Map<String, int> _indexes = <String, int>{};

  @override
  int get itemCount => _keys.length;

  @override
  int get revision => _changes.revision;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, itemCount)]);

  @override
  Listenable get changes => _changes;

  @override
  String keyAt(int index) => _keys[index];

  int? indexOf(String key) {
    _ensureIndexes();
    return _indexes[key];
  }

  @override
  SeekoKeyLookup<String> lookupKey(String key) {
    final int? index = indexOf(key);
    return index == null
        ? const SeekoKeyLookup<String>.absent()
        : SeekoKeyLookup<String>.found(index, key: key);
  }

  @override
  SeekoKeyLookup<String> captureIndex(int index) {
    if (index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<String>.absent();
    }
    return SeekoKeyLookup<String>.found(index, key: keyAt(index));
  }

  void prepend(int count) {
    final int beforeRevision = revision;
    _keys.insertAll(
      0,
      List<String>.generate(count, (int index) => 'new-$index'),
    );
    _indexes.clear();
    _changes.publish(
      SeekoChangeSet(
        beforeRevision: beforeRevision,
        afterRevision: beforeRevision + 1,
        changes: <SeekoChange>[
          SeekoChange.insert(index: 0, count: count),
        ],
      ),
    );
  }

  void _ensureIndexes() {
    if (_indexes.length == _keys.length) {
      return;
    }
    for (var index = 0; index < _keys.length; index += 1) {
      _indexes[_keys[index]] = index;
    }
  }

  void dispose() => _changes.dispose();
}

final class _PagedGridIndexDelegate implements SeekoIndexDelegate<String> {
  _PagedGridIndexDelegate({required int loadedCount})
      : _loadedCount = loadedCount,
        _revision = ValueNotifier<int>(0);

  int _loadedCount;
  final ValueNotifier<int> _revision;

  @override
  int get itemCount => 100;

  @override
  int get revision => _revision.value;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, _loadedCount)]);

  @override
  Listenable get changes => _revision;

  @override
  String keyAt(int index) => 'remote-$index';

  @override
  SeekoKeyLookup<String> lookupKey(String key) {
    if (!key.startsWith('remote-')) {
      return const SeekoKeyLookup<String>.absent();
    }
    final int? index = int.tryParse(key.substring(7));
    if (index == null || index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<String>.absent();
    }
    if (index >= _loadedCount) {
      return const SeekoKeyLookup<String>.notLoaded();
    }
    return SeekoKeyLookup<String>.found(index, key: key);
  }

  @override
  SeekoKeyLookup<String> captureIndex(int index) {
    if (index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<String>.absent();
    }
    if (index >= _loadedCount) {
      return const SeekoKeyLookup<String>.notLoaded();
    }
    return SeekoKeyLookup<String>.found(index, key: keyAt(index));
  }

  void loadThrough(int count) {
    _loadedCount = count.clamp(0, itemCount);
    _revision.value += 1;
  }

  void dispose() => _revision.dispose();
}

final class _CountingValueNotifier<T> extends ValueNotifier<T> {
  _CountingValueNotifier(super.value);

  var listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    listenerCount += 1;
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    listenerCount -= 1;
  }
}
