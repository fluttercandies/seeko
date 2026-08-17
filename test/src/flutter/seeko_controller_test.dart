import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('native controller removes owned listeners on dispose',
      (WidgetTester tester) async {
    final _TrackingSeekoController controller = _TrackingSeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final _TrackingSeekoPosition position = controller.trackingPosition;
    final int baseline = position.listenerBalance;
    final int scrollingBaseline =
        position.trackingScrollingNotifier.listenerBalance;

    controller.dispose();

    expect(position.listenerBalance, baseline - 2);
    expect(
      position.trackingScrollingNotifier.listenerBalance,
      scrollingBaseline - 1,
    );
  });

  testWidgets('controller plugs directly into a native ListView',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: ListView.builder(
            controller: controller,
            itemExtent: 50,
            itemCount: 100,
            itemBuilder: (_, int index) => Text('Item $index'),
          ),
        ),
      ),
    );
    expect(controller.isAttached, isTrue);
    expect(controller.capabilities.supports(ScrollCapability.pixel), isTrue);
    controller.jumpTo(100);
    await tester.pump();
    expect(controller.offset, 100);

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(const ScrollTarget.edge(ScrollEdge.trailing)),
    );
    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, controller.position.maxScrollExtent);
    controller.dispose();
  });

  testWidgets('typed offset commands clamp and report achieved position',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 20,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.offset(100000)),
    );
    expect(result.outcome, ScrollOutcome.clamped);
    expect(result.finalLogicalPixels, controller.position.maxScrollExtent);
    expect(result.clampReason, isNotEmpty);
    controller.dispose();
  });

  testWidgets('jumpBy uses the current logical position',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    controller.jumpTo(100);
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpBy(75),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(175, 0.5));
    controller.dispose();
  });

  testWidgets('animateBy uses the shared cancellable motion pipeline',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    controller.jumpTo(100);
    await tester.pump();

    final Future<ScrollResult> future = controller.animateBy(
      150,
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 100),
        curve: Curves.linear,
      ),
    );
    await tester.pumpAndSettle();
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(250, 0.5));
    controller.dispose();
  });

  testWidgets('unmounted index is explicit unsupported on the L1 driver',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.index(80)),
    );
    expect(result.outcome, ScrollOutcome.unsupported);
    controller.dispose();
  });

  testWidgets('ensureTargetVisible shares the typed nearest command pipeline',
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
                  20,
                  (int index) => SeekoTag(
                    controller: controller,
                    targetKey: index,
                    child: const SizedBox(height: 100),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final ScrollResult first = await pumpScrollCommand(
      tester,
      controller.ensureTargetVisible(ScrollTarget.key(4)),
    );
    final double reached = controller.offset;
    final ScrollResult second = await pumpScrollCommand(
      tester,
      controller.ensureTargetVisible(ScrollTarget.key(4)),
    );

    expect(first.outcome, ScrollOutcome.completed);
    expect(reached, closeTo(200, 0.5));
    expect(second.outcome, ScrollOutcome.completed);
    expect(controller.offset, reached);
    controller.dispose();
  });

  testWidgets('allowPhysicsOverscroll rejects unsupported clamping physics',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          physics: const ClampingScrollPhysics(),
          itemExtent: 50,
          itemCount: 20,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.offset(-20),
        options: const ScrollCommandOptions(
          boundaryPolicy: ScrollBoundaryPolicy.allowPhysicsOverscroll,
        ),
      ),
    );

    expect(result.outcome, ScrollOutcome.unsupported);
    expect(controller.offset, 0);
    controller.dispose();
  });

  testWidgets('supported physics overscroll reports the settled position',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemExtent: 50,
          itemCount: 20,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final Future<ScrollResult> future = controller.jumpToTarget(
      ScrollTarget.offset(-80),
      options: const ScrollCommandOptions(
        boundaryPolicy: ScrollBoundaryPolicy.allowPhysicsOverscroll,
      ),
    );
    await tester.pumpAndSettle();
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.clamped);
    expect(result.finalLogicalPixels, closeTo(0, 0.5));
    expect(result.finalError, closeTo(80, 0.5));
    controller.dispose();
  });

  testWidgets('animated overscroll waits for ballistic settle',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemExtent: 50,
          itemCount: 20,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final Future<ScrollResult> future = controller.animateToTarget(
      ScrollTarget.offset(-80),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 200),
        curve: Curves.linear,
      ),
      options: const ScrollCommandOptions(
        boundaryPolicy: ScrollBoundaryPolicy.allowPhysicsOverscroll,
      ),
    );
    await tester.pumpAndSettle();
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.clamped);
    expect(result.finalLogicalPixels, closeTo(0, 0.5));
    expect(result.finalError, closeTo(80, 0.5));
    controller.dispose();
  });

  testWidgets('adaptive animation uses the attached display frame interval',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    expect(
      controller.frameInterval.inMicroseconds,
      closeTo(
        1000000 / tester.view.display.refreshRate,
        1,
      ),
    );
    controller.dispose();
  });

  testWidgets('jump settles only after distinct stable layout samples',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    var completed = false;
    final Future<ScrollResult> future = controller
        .jumpToTarget(
          ScrollTarget.offset(500),
          options: ScrollCommandOptions(
            executionPolicy: ScrollExecutionPolicy(
              settleSamples: 2,
            ),
          ),
        )
        .whenComplete(() => completed = true);

    await tester.pump();
    expect(completed, isFalse);

    await _pumpUntil(tester, () => completed);
    final ScrollResult result = await future;
    expect(result.outcome, ScrollOutcome.completed);
    expect(result.correctionCount, 0);
    controller.dispose();
  });

  testWidgets('viewport changes replan mounted placement before settling',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final ValueNotifier<double> height = ValueNotifier<double>(300);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: height,
          builder: (_, double value, __) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: value,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: List<Widget>.generate(
                    20,
                    (int index) => SeekoTag(
                      controller: controller,
                      targetKey: index,
                      child: const SizedBox(height: 100),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Future<ScrollResult> future = controller.jumpToTarget(
      ScrollTarget.key(8),
      placement: const ScrollPlacement.center(),
      options: ScrollCommandOptions(
        executionPolicy: ScrollExecutionPolicy(
          settleSamples: 2,
        ),
      ),
    );
    var completed = false;
    unawaited(future.whenComplete(() => completed = true));
    await tester.pump();
    height.value = 500;
    await tester.pump();
    await _pumpUntil(tester, () => completed);

    final ScrollResult result = await future;
    expect(result.outcome, ScrollOutcome.completed);
    expect(result.replanCount, 1);
    expect(result.correctionCount, 1);
    expect(controller.offset, closeTo(600, 0.5));
    controller.dispose();
    height.dispose();
  });

  testWidgets('correction budget exhaustion returns layoutUnstable',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final ValueNotifier<double> height = ValueNotifier<double>(300);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: height,
          builder: (_, double value, __) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: value,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: List<Widget>.generate(
                    20,
                    (int index) => SeekoTag(
                      controller: controller,
                      targetKey: index,
                      child: const SizedBox(height: 100),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Future<ScrollResult> future = controller.jumpToTarget(
      ScrollTarget.key(8),
      placement: const ScrollPlacement.center(),
      options: ScrollCommandOptions(
        executionPolicy: ScrollExecutionPolicy(
          maxCorrections: 0,
          settleSamples: 2,
        ),
      ),
    );
    var completed = false;
    unawaited(future.whenComplete(() => completed = true));
    await tester.pump();
    height.value = 500;
    await tester.pump();
    await _pumpUntil(tester, () => completed);

    final ScrollResult result = await future;
    expect(result.outcome, ScrollOutcome.layoutUnstable);
    expect(result.replanCount, 1);
    expect(result.correctionCount, 1);
    expect(
        result.diagnostics, containsPair('executionPolicy', 'maxCorrections'));
    controller.dispose();
    height.dispose();
  });

  testWidgets('queued index commands capture a stable key before reordering',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ValueNotifier<List<String>> items =
        ValueNotifier<List<String>>(<String>['a', 'b', 'c', 'd', 'e']);
    final ListSeekoIndexDelegate<String> delegate =
        ListSeekoIndexDelegate<String>(
      itemCount: 5,
      revision: revision,
      keyAt: (int index) => items.value[index],
      indexOfKey: (String key) => items.value.indexOf(key),
    );
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
    );
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

    final Future<ScrollResult> active = controller.animateToTarget(
      ScrollTarget.offset(300),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    final Future<ScrollResult> queued = controller.jumpToTarget(
      ScrollTarget.index(2),
      placement: const ScrollPlacement.start(),
      options: const ScrollCommandOptions(
        conflictPolicy: ScrollConflictPolicy.enqueue,
      ),
    );
    items.value = <String>['c', 'a', 'b', 'd', 'e'];
    revision.value = 1;
    await tester.pumpAndSettle();

    expect((await active).outcome, ScrollOutcome.completed);
    final ScrollResult result = await queued;
    expect(result.requestedTarget, ScrollTarget.index(2));
    expect(result.capturedTarget, ScrollTarget.key('c'));
    expect(result.startRevision, 0);
    expect(result.endRevision, 1);
    expect(controller.offset, closeTo(0, 0.5));
    controller.dispose();
    items.dispose();
    revision.dispose();
  });

  testWidgets(
      'mounted index commands capture the registered key without a delegate',
      (WidgetTester tester) async {
    final ValueNotifier<List<String>> items =
        ValueNotifier<List<String>>(<String>['a', 'b', 'c', 'd', 'e']);
    final SeekoController controller = SeekoController();
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

    final Future<ScrollResult> active = controller.animateToTarget(
      ScrollTarget.offset(300),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    final Future<ScrollResult> queued = controller.jumpToTarget(
      ScrollTarget.index(2),
      placement: const ScrollPlacement.start(),
      options: const ScrollCommandOptions(
        conflictPolicy: ScrollConflictPolicy.enqueue,
      ),
    );
    items.value = <String>['c', 'a', 'b', 'd', 'e'];
    await tester.pumpAndSettle();

    expect((await active).outcome, ScrollOutcome.completed);
    final ScrollResult result = await queued;
    expect(result.requestedTarget, ScrollTarget.index(2));
    expect(result.capturedTarget, ScrollTarget.key('c'));
    expect(controller.offset, closeTo(0, 0.5));
    controller.dispose();
    items.dispose();
  });

  testWidgets('index capture reads keyAt when lookup omits the key',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController(
      indexDelegate: _KeylessLookupDelegate(<String>['a', 'b', 'c']),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 100,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: List<Widget>.generate(
                  3,
                  (int index) => SeekoTag(
                    controller: controller,
                    targetKey: <String>['a', 'b', 'c'][index],
                    index: index,
                    child: const SizedBox(height: 100),
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
        ScrollTarget.index(1),
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.capturedTarget, ScrollTarget.key('b'));
    expect(result.outcome, ScrollOutcome.completed);
    controller.dispose();
  });

  testWidgets('index capture distinguishes out of range before execution',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(4);
    final List<String> items = <String>['a', 'b'];
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: const <Widget>[SizedBox(height: 1000)],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.index(8)),
    );

    expect(result.outcome, ScrollOutcome.targetOutOfRange);
    expect(result.startRevision, 4);
    expect(result.endRevision, 4);
    controller.dispose();
    revision.dispose();
  });

  testWidgets('direct detach completes an active command as detached',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 200,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect((await result).outcome, ScrollOutcome.detached);
    expect(controller.state.value.activeCommandId, isNull);
    expect(controller.isAttached, isFalse);
    controller.dispose();
  });

  testWidgets('detach terminates queued commands without starting them',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 200,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final Future<ScrollResult> active = controller.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
    );
    final Future<ScrollResult> queued = controller.jumpToTarget(
      ScrollTarget.offset(500),
      options: const ScrollCommandOptions(
        conflictPolicy: ScrollConflictPolicy.enqueue,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect((await active).outcome, ScrollOutcome.detached);
    expect((await queued).outcome, ScrollOutcome.detached);
    controller.dispose();
  });

  testWidgets('native pixel writes atomically supersede the typed queue',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 200,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final Future<ScrollResult> active = controller.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
    );
    final Future<ScrollResult> queued = controller.jumpToTarget(
      ScrollTarget.offset(500),
      options: const ScrollCommandOptions(
        conflictPolicy: ScrollConflictPolicy.enqueue,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    controller.jumpTo(250);
    await tester.pump();

    expect((await active).outcome, ScrollOutcome.superseded);
    expect((await queued).outcome, ScrollOutcome.superseded);
    expect(controller.offset, closeTo(250, 0.5));
    controller.dispose();
  });

  testWidgets('stop atomically cancels the typed queue',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 200,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final Future<ScrollResult> active = controller.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
    );
    final Future<ScrollResult> queued = controller.jumpToTarget(
      ScrollTarget.offset(500),
      options: const ScrollCommandOptions(
        conflictPolicy: ScrollConflictPolicy.enqueue,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    controller.stop();

    expect((await active).outcome, ScrollOutcome.cancelled);
    expect((await queued).outcome, ScrollOutcome.cancelled);
    controller.dispose();
  });

  test('target commands require an attached position', () async {
    final SeekoController controller = SeekoController();
    await expectLater(
      Future<ScrollResult>.sync(
        () => controller.jumpToTarget(ScrollTarget.offset(10)),
      ),
      throwsStateError,
    );
    controller.dispose();
  });
}

final class _KeylessLookupDelegate implements SeekoIndexDelegate<Object> {
  _KeylessLookupDelegate(this.items);

  final List<String> items;
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  @override
  Listenable get changes => _changes;

  @override
  int get revision => 0;

  @override
  int get itemCount => items.length;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, items.length)]);

  @override
  Object keyAt(int index) => items[index];

  @override
  SeekoKeyLookup<Object> lookupKey(Object key) {
    final int index = key is String ? items.indexOf(key) : -1;
    return index < 0
        ? const SeekoKeyLookup<Object>.absent()
        : SeekoKeyLookup<Object>.found(index);
  }

  @override
  SeekoKeyLookup<Object> captureIndex(int index) =>
      index < 0 || index >= items.length
          ? const SeekoKeyLookup<Object>.absent()
          : SeekoKeyLookup<Object>.found(index);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var frame = 0; frame < 20 && !condition(); frame += 1) {
    await tester.pump();
  }
  expect(condition(), isTrue,
      reason: 'command did not settle within 20 frames');
}

final class _TrackingSeekoController extends SeekoController {
  late _TrackingSeekoPosition trackingPosition;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return trackingPosition = _TrackingSeekoPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

final class _TrackingSeekoPosition extends ScrollPositionWithSingleContext {
  _TrackingSeekoPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    required super.oldPosition,
    required super.debugLabel,
  });

  int listenerBalance = 0;
  final _TrackingValueNotifier trackingScrollingNotifier =
      _TrackingValueNotifier(false);

  @override
  ValueNotifier<bool> get isScrollingNotifier => trackingScrollingNotifier;

  @override
  void addListener(VoidCallback listener) {
    listenerBalance += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerBalance -= 1;
    super.removeListener(listener);
  }
}

final class _TrackingValueNotifier extends ValueNotifier<bool> {
  _TrackingValueNotifier(super.value);

  int listenerBalance = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerBalance += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerBalance -= 1;
    super.removeListener(listener);
  }
}
