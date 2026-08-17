import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('invalid obstruction geometry returns resolverRejected',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController(
      obstructionResolver: (_) =>
          VisibleRegion.fromIntervals(const <LogicalInterval>[]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: SingleChildScrollView(
            controller: controller,
            child: SeekoTag(
              controller: controller,
              targetKey: 'target',
              child: const SizedBox(height: 1000),
            ),
          ),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.key('target')),
    );

    expect(result.outcome, ScrollOutcome.resolverRejected);
    controller.dispose();
  });

  testWidgets('mounted key and index targets reveal through a minimal tag',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 300,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: List<Widget>.generate(
                  30,
                  (int index) => SeekoTag(
                    controller: controller,
                    targetKey: 'item-$index',
                    index: index,
                    child: SizedBox(
                      height: 100,
                      child: Text('Item $index'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final ScrollResult byKey = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('item-8'),
        placement: const ScrollPlacement.center(),
      ),
    );
    await tester.pump();
    expect(byKey.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(700, 0.5));

    final ScrollResult byIndex = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.index(3),
        placement: const ScrollPlacement.start(),
      ),
    );
    await tester.pump();
    expect(byIndex.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(300, 0.5));
    controller.dispose();
  });

  testWidgets('keyed reorder atomically rebuilds mounted index lookup',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final ValueNotifier<List<String>> items =
        ValueNotifier<List<String>>(<String>['a', 'b', 'c', 'd']);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 100,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: items,
              builder: (_, List<String> value, __) => SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: List<Widget>.generate(
                    value.length,
                    (int index) => SeekoTag(
                      key: ValueKey<String>(value[index]),
                      controller: controller,
                      targetKey: value[index],
                      index: index,
                      child: SizedBox(height: 100, child: Text(value[index])),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    items.value = <String>['c', 'a', 'b', 'd'];
    await tester.pump();

    expect(tester.takeException(), isNull);
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.index(2, tracking: IndexTracking.liveSlot),
        placement: const ScrollPlacement.start(),
      ),
    );
    expect(result.clampReason, isNull);
    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalLogicalPixels, closeTo(200, 0.5));
    expect(controller.offset, closeTo(200, 0.5));
    controller.dispose();
    items.dispose();
  });

  testWidgets('unkeyed target-key swap commits atomically after the frame',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final ValueNotifier<List<String>> items =
        ValueNotifier<List<String>>(<String>['a', 'b']);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 100,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: items,
              builder: (_, List<String> value, __) => SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: List<Widget>.generate(
                    value.length,
                    (int index) => SeekoTag(
                      controller: controller,
                      targetKey: value[index],
                      index: index,
                      child: SizedBox(height: 100, child: Text(value[index])),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    items.value = <String>['b', 'a'];
    await tester.pump();

    expect(tester.takeException(), isNull);
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('a'),
        placement: const ScrollPlacement.start(),
      ),
    );
    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(100, 0.5));
    controller.dispose();
    items.dispose();
  });

  testWidgets('post-frame index registration schedules its commit frame',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final GlobalKey target = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: controller,
          child: SizedBox(key: target, height: 1000),
        ),
      ),
    );

    SchedulerBinding.instance.addPostFrameCallback((_) {
      controller.registerMountedTarget(target.currentContext!, index: 0);
    });
    controller.jumpTo(1);
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    controller.dispose();
  });

  testWidgets('duplicate index commit fails a waiting command atomically',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final GlobalKey first = GlobalKey();
    final GlobalKey second = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 100,
          child: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: <Widget>[
                SeekoTag(
                  key: first,
                  controller: controller,
                  targetKey: 'a',
                  index: 0,
                  child: const SizedBox(height: 100),
                ),
                SeekoTag(
                  key: second,
                  controller: controller,
                  targetKey: 'b',
                  index: 1,
                  child: const SizedBox(height: 100),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    late Future<ScrollResult> pending;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      controller.registerMountedTarget(
        second.currentContext!,
        key: 'b',
        index: 0,
      );
      pending = controller.jumpToTarget(
        ScrollTarget.index(0, tracking: IndexTracking.liveSlot),
      );
    });
    controller.jumpTo(1);
    await tester.pump();
    final Future<void> expectation = expectLater(
      pending,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message.toString(),
          'message',
          contains('Duplicate mounted Seeko index: 0'),
        ),
      ),
    );
    await tester.pump();
    await expectation;
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('exact placement honors the target anchor',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(_taggedScrollView(controller));

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('item-8'),
        placement: ScrollPlacement.exact(
          targetAnchor: 1,
          viewportAnchor: 0,
        ),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(900, 0.5));
    controller.dispose();
  });

  testWidgets('nearest placement does not move an already visible target',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(_taggedScrollView(controller));
    controller.jumpTo(250);
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.key('item-3')),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(250, 0.5));
    controller.dispose();
  });

  testWidgets('placement uses the unobstructed viewport intervals',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController(
      obstructionResolver: (ScrollViewportGeometry viewport) =>
          VisibleRegion.fromIntervals(
        <LogicalInterval>[
          LogicalInterval(80, viewport.viewportExtent),
        ],
      ),
    );
    await tester.pumpWidget(_taggedScrollView(controller));

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('item-3'),
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(220, 0.5));
    controller.dispose();
  });

  testWidgets('mounted placement honors reject boundary policy',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(_taggedScrollView(controller));

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('item-0'),
        placement: ScrollPlacement.exact(
          targetAnchor: 0,
          viewportAnchor: 1,
        ),
        options: const ScrollCommandOptions(
          boundaryPolicy: ScrollBoundaryPolicy.reject,
        ),
      ),
    );

    expect(result.outcome, ScrollOutcome.targetOutOfRange);
    expect(controller.offset, 0);
    controller.dispose();
  });

  testWidgets('a tag in another scrollable is explicitly rejected',
      (WidgetTester tester) async {
    final SeekoController outer = SeekoController();
    final SeekoController inner = SeekoController();
    late BuildContext innerTarget;
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: outer,
          children: <Widget>[
            SizedBox(
              height: 300,
              child: ListView(
                controller: inner,
                children: <Widget>[
                  Builder(
                    builder: (BuildContext context) {
                      innerTarget = context;
                      return const SizedBox(height: 100);
                    },
                  ),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
            const SizedBox(height: 1000),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      outer.jumpToTarget(ScrollTarget.mounted(innerTarget)),
    );

    expect(result.outcome, ScrollOutcome.resolverRejected);
    expect(outer.offset, 0);
    outer.dispose();
    inner.dispose();
  });

  testWidgets('mounted geometry handles reverse horizontal RTL',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 100,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: List<Widget>.generate(
                    20,
                    (int index) => SeekoTag(
                      controller: controller,
                      targetKey: index,
                      child: SizedBox(
                        width: 100,
                        child: Text('$index'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key(8),
        placement: const ScrollPlacement.center(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalError, lessThanOrEqualTo(0.5));
    controller.dispose();
  });

  testWidgets('unmounted or removed tags return targetNotLoaded',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: <Widget>[
            SeekoTag(
              controller: controller,
              targetKey: 'mounted',
              child: const SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
    expect(
      (await pumpScrollCommand(
        tester,
        controller.jumpToTarget(ScrollTarget.key('missing')),
      ))
          .outcome,
      ScrollOutcome.targetNotLoaded,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(controller.isAttached, isFalse);
    controller.dispose();
  });
}

Widget _taggedScrollView(SeekoController controller) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 300,
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: List<Widget>.generate(
              30,
              (int index) => SeekoTag(
                controller: controller,
                targetKey: 'item-$index',
                index: index,
                child: SizedBox(
                  height: 100,
                  child: Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
