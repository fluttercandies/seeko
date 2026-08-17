import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('mounted body target collapses the header and scrolls inner', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();

    await tester.pumpWidget(
      _nestedScrollView(
        controller: controller,
        nestedKey: nestedKey,
      ),
    );
    await tester.pump();

    final ScrollPosition outer =
        nestedKey.currentState!.outerController.position;
    final ScrollPosition inner =
        nestedKey.currentState!.innerController.position;
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'item-5',
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(outer.pixels, closeTo(outer.maxScrollExtent, 0.5));
    expect(inner.pixels, greaterThan(200));
    expect(
      result.finalLogicalPixels,
      closeTo(
        outer.maxScrollExtent -
            outer.minScrollExtent +
            inner.pixels -
            inner.minScrollExtent,
        0.5,
      ),
    );
    expect(tester.getTopLeft(find.text('Item 5')).dy, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('snapshot reports the combined outer and inner coordinate', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedScrollView(
        controller: controller,
        nestedKey: nestedKey,
      ),
    );
    await tester.pump();

    await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'item-5',
        placement: const ScrollPlacement.start(),
      ),
    );
    await tester.pump();

    final ScrollPosition outer =
        nestedKey.currentState!.outerController.position;
    final ScrollPosition inner =
        nestedKey.currentState!.innerController.position;
    final double combinedPixels = outer.pixels -
        outer.minScrollExtent +
        inner.pixels -
        inner.minScrollExtent;
    final double combinedExtent = outer.maxScrollExtent -
        outer.minScrollExtent +
        inner.maxScrollExtent -
        inner.minScrollExtent;

    expect(controller.state.value.pixels, closeTo(combinedPixels, 0.5));
    expect(
      controller.state.value.maxScrollExtent,
      closeTo(combinedExtent, 0.5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('snapshot includes visible inner semantic targets', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedScrollView(controller: controller, nestedKey: nestedKey),
    );
    await tester.pump();

    expect(
      controller.state.value.visibleTargets
          .map((ScrollVisibleTarget target) => target.key),
      contains('item-0'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('animation follows one natural composite trajectory', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedScrollView(
        controller: controller,
        nestedKey: nestedKey,
      ),
    );
    await tester.pump();

    final Future<ScrollResult> result = controller.animateToKey(
      'item-5',
      placement: const ScrollPlacement.start(),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 240),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(controller.state.value.phase, ScrollPhase.programmatic);
    await tester.pumpAndSettle();
    expect((await result).outcome, ScrollOutcome.completed);
    expect(tester.getTopLeft(find.text('Item 5')).dy, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('inner user drag interrupts a composite animation', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedScrollView(
        controller: controller,
        nestedKey: nestedKey,
      ),
    );
    await tester.pump();

    final Future<ScrollResult> result = controller.animateToKey(
      'item-5',
      placement: const ScrollPlacement.start(),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
    final TestGesture gesture = await tester.startGesture(
      const Offset(100, 400),
    );
    await gesture.moveBy(const Offset(0, -80));
    await gesture.up();
    await tester.pumpAndSettle();

    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    expect(controller.state.value.origin, ScrollEventOrigin.user);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('unmounted indexed body target uses the composite coordinate', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedIndexedScrollView(
        controller: controller,
        nestedKey: nestedKey,
        revision: revision,
      ),
    );
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(
        80,
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 20,
    );

    final ScrollPosition outer =
        nestedKey.currentState!.outerController.position;
    final ScrollPosition inner =
        nestedKey.currentState!.innerController.position;
    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('indexed-80'));
    expect(outer.pixels, closeTo(outer.maxScrollExtent, 0.5));
    expect(inner.pixels, closeTo(4800, 0.5));
    expect(tester.getTopLeft(find.text('Indexed 80')).dy, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('multiple inner positions require an explicit selector', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedMultiBodyScrollView(
        controller: controller,
        nestedKey: nestedKey,
      ),
    );
    await tester.pump();

    expect(nestedKey.currentState!.innerController.positions.length, 2);
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey('first-3'),
    );

    expect(result.outcome, ScrollOutcome.resolverRejected);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('explicit selector targets one attached inner position', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedMultiBodyScrollView(
        controller: controller,
        nestedKey: nestedKey,
        selector: (List<ScrollPosition> positions) => positions.first,
      ),
    );
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'first-3',
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(tester.getTopLeft(find.text('first 3')).dy, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('inner placement honors explicit pinned-header obstruction', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController(
      obstructionResolver: (ScrollViewportGeometry viewport) {
        return VisibleRegion.fromIntervals(<LogicalInterval>[
          LogicalInterval(80, viewport.viewportExtent),
        ]);
      },
    );
    await tester.pumpWidget(
      _nestedScrollView(
        controller: controller,
        nestedKey: nestedKey,
      ),
    );
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'item-5',
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(tester.getTopLeft(find.text('Item 5')).dy, closeTo(80, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('outer header target expands after inner content scrolled', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedOuterTargetScrollView(
        controller: controller,
        nestedKey: nestedKey,
      ),
    );
    await tester.pump();

    await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'body-5',
        placement: const ScrollPlacement.start(),
      ),
    );
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'outer-target',
        placement: const ScrollPlacement.start(),
      ),
    );

    final ScrollPosition outer =
        nestedKey.currentState!.outerController.position;
    final ScrollPosition inner =
        nestedKey.currentState!.innerController.position;
    expect(result.outcome, ScrollOutcome.completed);
    expect(outer.pixels, closeTo(outer.minScrollExtent, 0.5));
    expect(inner.pixels, closeTo(inner.minScrollExtent, 0.5));
    expect(tester.getTopLeft(find.text('Outer target')).dy, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('binding follows a replacement NestedScrollView position pair', (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController();
    final GlobalKey<NestedScrollViewState> firstKey =
        GlobalKey<NestedScrollViewState>();
    await tester.pumpWidget(
      _nestedScrollView(controller: controller, nestedKey: firstKey),
    );
    await tester.pump();

    final GlobalKey<NestedScrollViewState> secondKey =
        GlobalKey<NestedScrollViewState>();
    await tester.pumpWidget(
      _nestedScrollView(controller: controller, nestedKey: secondKey),
    );
    await tester.pump();
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'item-5',
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(secondKey.currentState!.innerController.position.pixels, 300);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('stop preserves the reached composite position', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      _nestedScrollView(controller: controller, nestedKey: nestedKey),
    );
    await tester.pump();

    final Future<ScrollResult> result = controller.animateToKey(
      'item-5',
      placement: const ScrollPlacement.start(),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final ScrollPosition outer =
        nestedKey.currentState!.outerController.position;
    final ScrollPosition inner =
        nestedKey.currentState!.innerController.position;
    final double beforeStop = outer.pixels -
        outer.minScrollExtent +
        inner.pixels -
        inner.minScrollExtent;
    controller.stop();
    await tester.pumpAndSettle();

    final double afterStop = outer.pixels -
        outer.minScrollExtent +
        inner.pixels -
        inner.minScrollExtent;

    expect((await result).outcome, ScrollOutcome.cancelled);
    expect(afterStop, closeTo(beforeStop, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('progress sync applies to the composite follower extent', (
    WidgetTester tester,
  ) async {
    final SeekoController leader = SeekoController();
    final SeekoController follower = SeekoController();
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    group.add(leader, id: 'leader');
    group.add(follower, id: 'follower');
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                controller: leader,
                itemExtent: 50,
                itemCount: 100,
                itemBuilder: (_, int index) => Text('Leader $index'),
              ),
            ),
            Expanded(
              child: SeekoNestedScrollBinding(
                controller: follower,
                nestedScrollViewKey: nestedKey,
                child: NestedScrollView(
                  key: nestedKey,
                  controller: follower,
                  headerSliverBuilder: (context, scrolled) => const <Widget>[
                    SliverAppBar(expandedHeight: 200, pinned: true),
                  ],
                  body: ListView.builder(
                    itemExtent: 60,
                    itemCount: 100,
                    itemBuilder: (_, int index) => Text('Follower $index'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    leader.jumpTo(leader.position.maxScrollExtent / 2);
    await tester.pump();

    final ScrollPosition outer =
        nestedKey.currentState!.outerController.position;
    final ScrollPosition inner =
        nestedKey.currentState!.innerController.position;
    final double followerPixels = outer.pixels -
        outer.minScrollExtent +
        inner.pixels -
        inner.minScrollExtent;
    final double followerExtent = outer.maxScrollExtent -
        outer.minScrollExtent +
        inner.maxScrollExtent -
        inner.minScrollExtent;
    expect(
      followerPixels / followerExtent,
      closeTo(0.5, 1e-9),
      reason: 'leader=${leader.offset}/${leader.position.maxScrollExtent}, '
          'outer=${outer.pixels}/${outer.maxScrollExtent}, '
          'inner=${inner.pixels}/${inner.maxScrollExtent}, '
          'snapshot=${follower.state.value.pixels}/'
          '${follower.state.value.maxScrollExtent}',
    );

    group.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    leader.dispose();
    follower.dispose();
  });

  testWidgets('semantic sync resolves an indexed inner target', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leaderRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> followerRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leaderDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 100,
      revision: leaderRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final ListSeekoIndexDelegate<int> followerDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 100,
      revision: followerRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController leader =
        SeekoController(indexDelegate: leaderDelegate);
    final SeekoController follower =
        SeekoController(indexDelegate: followerDelegate);
    final GlobalKey<NestedScrollViewState> nestedKey =
        GlobalKey<NestedScrollViewState>();
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    group.add(leader, id: 'leader');
    group.add(follower, id: 'follower');
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              child: CustomScrollView(
                controller: leader,
                slivers: <Widget>[
                  SeekoIndexedSliver(
                    controller: leader,
                    indexDelegate: leaderDelegate,
                    estimatedExtent: 50,
                    delegate: SliverChildBuilderDelegate(
                      (_, int index) => SizedBox(
                        height: 50,
                        child: Text('Leader semantic $index'),
                      ),
                      childCount: 100,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SeekoNestedScrollBinding(
                controller: follower,
                nestedScrollViewKey: nestedKey,
                child: NestedScrollView(
                  key: nestedKey,
                  controller: follower,
                  headerSliverBuilder: (context, scrolled) => const <Widget>[
                    SliverAppBar(expandedHeight: 200, pinned: true),
                  ],
                  body: CustomScrollView(
                    slivers: <Widget>[
                      SeekoIndexedSliver(
                        controller: follower,
                        indexDelegate: followerDelegate,
                        estimatedExtent: 70,
                        delegate: SliverChildBuilderDelegate(
                          (_, int index) => SizedBox(
                            height: 70,
                            child: Text('Follower semantic $index'),
                          ),
                          childCount: 100,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      leader.jumpToKey(50, placement: const ScrollPlacement.start()),
      maxFrames: 20,
    );
    await tester.pump();
    await tester.pump();

    expect(result.outcome, ScrollOutcome.completed);
    expect(follower.state.value.firstVisibleTarget?.key, 50);

    group.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    leader.dispose();
    follower.dispose();
    leaderRevision.dispose();
    followerRevision.dispose();
  });
}

Widget _nestedScrollView({
  required SeekoController controller,
  required GlobalKey<NestedScrollViewState> nestedKey,
}) {
  return MaterialApp(
    home: SeekoNestedScrollBinding(
      controller: controller,
      nestedScrollViewKey: nestedKey,
      child: NestedScrollView(
        key: nestedKey,
        controller: controller,
        headerSliverBuilder: (
          BuildContext context,
          bool innerBoxIsScrolled,
        ) {
          return const <Widget>[
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(title: Text('Header')),
            ),
          ];
        },
        body: ListView.builder(
          itemExtent: 60,
          itemCount: 100,
          itemBuilder: (BuildContext context, int index) {
            return SeekoTag(
              controller: controller,
              targetKey: 'item-$index',
              index: index,
              child: Text('Item $index'),
            );
          },
        ),
      ),
    ),
  );
}

Widget _nestedIndexedScrollView({
  required SeekoController controller,
  required GlobalKey<NestedScrollViewState> nestedKey,
  required ValueNotifier<int> revision,
}) {
  final ListSeekoIndexDelegate<String> delegate =
      ListSeekoIndexDelegate<String>(
    itemCount: 100,
    revision: revision,
    keyAt: (int index) => 'indexed-$index',
    indexOfKey: (String key) {
      if (!key.startsWith('indexed-')) {
        return null;
      }
      return int.tryParse(key.substring('indexed-'.length));
    },
  );
  return MaterialApp(
    home: SeekoNestedScrollBinding(
      controller: controller,
      nestedScrollViewKey: nestedKey,
      child: NestedScrollView(
        key: nestedKey,
        controller: controller,
        headerSliverBuilder: (BuildContext context, bool scrolled) =>
            const <Widget>[
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(title: Text('Header')),
          ),
        ],
        body: CustomScrollView(
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: delegate,
              estimatedExtent: 60,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => SizedBox(
                  height: 60,
                  child: Text('Indexed $index'),
                ),
                childCount: 100,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _nestedMultiBodyScrollView({
  required SeekoController controller,
  required GlobalKey<NestedScrollViewState> nestedKey,
  SeekoNestedInnerPositionSelector? selector,
}) {
  Widget list(String prefix) {
    return ListView.builder(
      primary: true,
      itemExtent: 60,
      itemCount: 30,
      itemBuilder: (BuildContext context, int index) => SeekoTag(
        controller: controller,
        targetKey: '$prefix-$index',
        child: Text('$prefix $index'),
      ),
    );
  }

  return MaterialApp(
    home: SeekoNestedScrollBinding(
      controller: controller,
      nestedScrollViewKey: nestedKey,
      innerPositionSelector: selector,
      child: NestedScrollView(
        key: nestedKey,
        controller: controller,
        headerSliverBuilder: (BuildContext context, bool scrolled) =>
            const <Widget>[
          SliverAppBar(expandedHeight: 160, pinned: true),
        ],
        body: Stack(
          children: <Widget>[
            list('first'),
            Offstage(child: list('second')),
          ],
        ),
      ),
    ),
  );
}

Widget _nestedOuterTargetScrollView({
  required SeekoController controller,
  required GlobalKey<NestedScrollViewState> nestedKey,
}) {
  return MaterialApp(
    home: SeekoNestedScrollBinding(
      controller: controller,
      nestedScrollViewKey: nestedKey,
      child: NestedScrollView(
        key: nestedKey,
        controller: controller,
        headerSliverBuilder: (BuildContext context, bool scrolled) => <Widget>[
          SliverToBoxAdapter(
            child: SeekoTag(
              controller: controller,
              targetKey: 'outer-target',
              child: const SizedBox(
                height: 100,
                child: Text('Outer target'),
              ),
            ),
          ),
          const SliverAppBar(expandedHeight: 160, pinned: true),
        ],
        body: ListView.builder(
          itemExtent: 60,
          itemCount: 50,
          itemBuilder: (BuildContext context, int index) => SeekoTag(
            controller: controller,
            targetKey: 'body-$index',
            child: Text('Body $index'),
          ),
        ),
      ),
    ),
  );
}
