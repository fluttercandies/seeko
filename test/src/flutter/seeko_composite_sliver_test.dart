import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('stable keys resolve across multiple indexed slivers', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _compositeScrollView(controller: controller, revision: revision),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'b-10',
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(1880, 0.5));
    expect(controller.state.value.firstVisibleTarget?.key, 'b-10');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('global indexes span finite indexed slivers in tree order', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _compositeScrollView(controller: controller, revision: revision),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(
        25,
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('b-5'));
    expect(controller.offset, closeTo(1530, 0.5));
    expect(controller.state.value.firstVisibleTarget?.index, 25);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('initial targets resolve in a later indexed sliver', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController(
      initialTarget: ScrollTarget.key('b-10'),
      initialPlacement: const ScrollPlacement.start(),
    );
    final Future<SeekoInitialTargetResult> initial =
        controller.initialTargetResult!;

    await tester.pumpWidget(
      _compositeScrollView(controller: controller, revision: revision),
    );
    final SeekoInitialTargetResult result = await pumpScrollCommand(
      tester,
      initial,
      maxFrames: 10,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalLogicalPixels, closeTo(1880, 0.5));
    expect(controller.offset, closeTo(1880, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('far animation rebases only the resolved indexed sliver', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _compositeScrollView(
        controller: controller,
        revision: revision,
        firstCount: 200,
        secondCount: 200,
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.animateToKey(
        'b-150',
        placement: const ScrollPlacement.start(),
        motion: const ScrollMotion.duration(
          duration: Duration(milliseconds: 160),
          curve: Curves.linear,
        ),
      ),
      maxFrames: 30,
      frameDuration: const Duration(milliseconds: 16),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(20680, 0.5));
    expect(controller.state.value.firstVisibleTarget?.key, 'b-150');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('duplicate stable keys across slivers are rejected', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    final ListSeekoIndexDelegate<String> first = ListSeekoIndexDelegate<String>(
      itemCount: 1,
      revision: revision,
      keyAt: (_) => 'duplicate',
      indexOfKey: (String key) => key == 'duplicate' ? 0 : null,
    );
    final ListSeekoIndexDelegate<String> second =
        ListSeekoIndexDelegate<String>(
      itemCount: 1,
      revision: revision,
      keyAt: (_) => 'duplicate',
      indexOfKey: (String key) => key == 'duplicate' ? 0 : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            _indexedSliver(controller, first, 60),
            _indexedSliver(controller, second, 60),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey('duplicate'),
    );

    expect(result.outcome, ScrollOutcome.resolverRejected);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('global indexes follow dynamic sliver tree order', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    final ListSeekoIndexDelegate<String> first = ListSeekoIndexDelegate<String>(
      itemCount: 10,
      revision: revision,
      keyAt: (int index) => 'a-$index',
      indexOfKey: (String key) => _indexFor(key, 'a-'),
    );
    final ListSeekoIndexDelegate<String> second =
        ListSeekoIndexDelegate<String>(
      itemCount: 10,
      revision: revision,
      keyAt: (int index) => 'b-$index',
      indexOfKey: (String key) => _indexFor(key, 'b-'),
    );

    await tester.pumpWidget(
      _reorderedComposite(
        controller: controller,
        first: first,
        second: second,
        swapped: false,
      ),
    );
    final ScrollResult before = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(12),
    );

    await tester.pumpWidget(
      _reorderedComposite(
        controller: controller,
        first: first,
        second: second,
        swapped: true,
      ),
    );
    await tester.pump();
    final ScrollResult after = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(12),
    );

    expect(before.capturedTarget, ScrollTarget.key('b-2'));
    expect(after.capturedTarget, ScrollTarget.key('a-2'));
    expect(after.outcome, ScrollOutcome.completed);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  final List<({Axis axis, bool reverse, TextDirection direction})> cases =
      <({Axis axis, bool reverse, TextDirection direction})>[
    (axis: Axis.vertical, reverse: false, direction: TextDirection.ltr),
    (axis: Axis.vertical, reverse: true, direction: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: false, direction: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: true, direction: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: false, direction: TextDirection.rtl),
    (axis: Axis.horizontal, reverse: true, direction: TextDirection.rtl),
  ];
  for (final config in cases) {
    testWidgets(
      'composite target uses logical leading for ${config.axis.name} '
      'reverse=${config.reverse} ${config.direction.name}',
      (WidgetTester tester) async {
        final ValueNotifier<int> revision = ValueNotifier<int>(0);
        final SeekoController controller = SeekoController();
        await tester.pumpWidget(
          _directionalComposite(
            controller: controller,
            revision: revision,
            axis: config.axis,
            reverse: config.reverse,
            direction: config.direction,
          ),
        );

        final ScrollResult result = await pumpScrollCommand(
          tester,
          controller.jumpToKey(
            'b-3',
            placement: const ScrollPlacement.start(),
          ),
        );

        final Rect target = tester.getRect(
          find.byKey(const ValueKey<String>('target-b-3')),
        );
        final Rect viewport = tester.getRect(
          find.byKey(const ValueKey<String>('directional-viewport')),
        );
        final bool physicalLeadingAtStart = config.axis == Axis.vertical
            ? !config.reverse
            : config.reverse == (config.direction == TextDirection.rtl);
        final double targetLeading = config.axis == Axis.vertical
            ? (physicalLeadingAtStart ? target.top : target.bottom)
            : (physicalLeadingAtStart ? target.left : target.right);
        final double viewportLeading = config.axis == Axis.vertical
            ? (physicalLeadingAtStart ? viewport.top : viewport.bottom)
            : (physicalLeadingAtStart ? viewport.left : viewport.right);

        expect(result.outcome, ScrollOutcome.completed);
        expect(targetLeading, closeTo(viewportLeading, 0.5));
        expect(controller.state.value.firstVisibleTarget?.key, 'b-3');

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        revision.dispose();
      },
    );
  }
}

Widget _compositeScrollView({
  required SeekoController controller,
  required ValueNotifier<int> revision,
  int firstCount = 20,
  int secondCount = 20,
}) {
  final ListSeekoIndexDelegate<String> first = ListSeekoIndexDelegate<String>(
    itemCount: firstCount,
    revision: revision,
    keyAt: (int index) => 'a-$index',
    indexOfKey: (String key) => _indexFor(key, 'a-'),
  );
  final ListSeekoIndexDelegate<String> second = ListSeekoIndexDelegate<String>(
    itemCount: secondCount,
    revision: revision,
    keyAt: (int index) => 'b-$index',
    indexOfKey: (String key) => _indexFor(key, 'b-'),
  );
  return MaterialApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 300,
        child: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
            _indexedSliver(controller, first, 50),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
            _indexedSliver(controller, second, 70),
          ],
        ),
      ),
    ),
  );
}

SeekoIndexedSliver _indexedSliver(
  SeekoController controller,
  SeekoIndexDelegate<Object> indexDelegate,
  double extent,
) {
  return SeekoIndexedSliver(
    controller: controller,
    indexDelegate: indexDelegate,
    estimatedExtent: extent,
    delegate: SliverChildBuilderDelegate(
      (_, int index) => SizedBox(
        height: extent,
        child: ColoredBox(
          color: index.isEven ? Colors.white : Colors.black12,
        ),
      ),
      childCount: indexDelegate.itemCount,
    ),
  );
}

int? _indexFor(String key, String prefix) {
  if (!key.startsWith(prefix)) {
    return null;
  }
  return int.tryParse(key.substring(prefix.length));
}

Widget _reorderedComposite({
  required SeekoController controller,
  required SeekoIndexDelegate<Object> first,
  required SeekoIndexDelegate<Object> second,
  required bool swapped,
}) {
  final Widget firstSliver = KeyedSubtree(
    key: const ValueKey<String>('first-sliver'),
    child: _indexedSliver(controller, first, 50),
  );
  final Widget secondSliver = KeyedSubtree(
    key: const ValueKey<String>('second-sliver'),
    child: _indexedSliver(controller, second, 70),
  );
  return MaterialApp(
    home: SizedBox(
      height: 300,
      child: CustomScrollView(
        controller: controller,
        slivers: swapped
            ? <Widget>[secondSliver, firstSliver]
            : <Widget>[firstSliver, secondSliver],
      ),
    ),
  );
}

Widget _directionalComposite({
  required SeekoController controller,
  required ValueNotifier<int> revision,
  required Axis axis,
  required bool reverse,
  required TextDirection direction,
}) {
  final ListSeekoIndexDelegate<String> first = ListSeekoIndexDelegate<String>(
    itemCount: 5,
    revision: revision,
    keyAt: (int index) => 'a-$index',
    indexOfKey: (String key) => _indexFor(key, 'a-'),
  );
  final ListSeekoIndexDelegate<String> second = ListSeekoIndexDelegate<String>(
    itemCount: 10,
    revision: revision,
    keyAt: (int index) => 'b-$index',
    indexOfKey: (String key) => _indexFor(key, 'b-'),
  );
  Widget mainAxisBox(double extent) => SizedBox(
        width: axis == Axis.horizontal ? extent : null,
        height: axis == Axis.vertical ? extent : null,
      );

  return MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          height: 240,
          child: CustomScrollView(
            key: const ValueKey<String>('directional-viewport'),
            controller: controller,
            scrollDirection: axis,
            reverse: reverse,
            slivers: <Widget>[
              SliverToBoxAdapter(child: mainAxisBox(40)),
              _directionalIndexedSliver(controller, first, 50, axis),
              SliverToBoxAdapter(child: mainAxisBox(30)),
              _directionalIndexedSliver(controller, second, 70, axis),
            ],
          ),
        ),
      ),
    ),
  );
}

SeekoIndexedSliver _directionalIndexedSliver(
  SeekoController controller,
  SeekoIndexDelegate<Object> delegate,
  double extent,
  Axis axis,
) {
  return SeekoIndexedSliver(
    controller: controller,
    indexDelegate: delegate,
    estimatedExtent: extent,
    delegate: SliverChildBuilderDelegate(
      (BuildContext context, int index) => SizedBox(
        key: delegate.keyAt(index) == 'b-3'
            ? const ValueKey<String>('target-b-3')
            : null,
        width: axis == Axis.horizontal ? extent : null,
        height: axis == Axis.vertical ? extent : null,
      ),
      childCount: delegate.itemCount,
    ),
  );
}
