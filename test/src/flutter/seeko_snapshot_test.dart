import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  testWidgets('snapshot tracks metrics and programmatic phases by frame',
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
    await tester.pump();
    expect(controller.state.value.viewportExtent, greaterThan(0));
    expect(controller.state.value.phase, ScrollPhase.idle);

    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(500),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.state.value.phase, ScrollPhase.programmatic);
    await tester.pumpAndSettle();
    expect((await result).outcome, ScrollOutcome.completed);
    await tester.pump();
    expect(controller.state.value.activeCommandId, isNull);
    expect(controller.state.value.phase, ScrollPhase.idle);
    expect(controller.state.value.pixels, closeTo(500, 0.5));
    controller.dispose();
  });

  testWidgets('user drag interrupts a typed animation',
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
    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(1000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    controller.dispose();
  });

  testWidgets('mouse wheel interrupts a typed animation as user input',
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
    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(1000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();

    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    expect(controller.state.value.origin, ScrollEventOrigin.user);
    controller.dispose();
  });

  testWidgets('trackpad pan interrupts a typed animation as user input',
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
    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(1000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final TestGesture trackpad =
        await tester.createGesture(kind: PointerDeviceKind.trackpad);

    await trackpad.panZoomStart(tester.getCenter(find.byType(ListView)));
    await tester.pump();
    await trackpad.panZoomUpdate(
      tester.getCenter(find.byType(ListView)),
      pan: const Offset(0, -120),
    );
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();

    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    expect(controller.state.value.origin, ScrollEventOrigin.user);
    controller.dispose();
  });

  testWidgets('keyboard scrolling interrupts a typed animation as user input',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Focus(
            autofocus: index == 0,
            child: Text('$index'),
          ),
        ),
      ),
    );
    await tester.pump();
    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(1000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();

    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    expect(controller.state.value.origin, ScrollEventOrigin.user);
    controller.dispose();
  });

  testWidgets(
      'accessibility scrolling interrupts a typed animation as user input',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
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
    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(1000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    tester.semantics.scrollUp();
    await tester.pumpAndSettle();

    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    expect(controller.state.value.origin, ScrollEventOrigin.user);
    controller.dispose();
    semantics.dispose();
  });

  testWidgets('snapshot reports ordered visible targets and semantic anchor',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 250,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: List<Widget>.generate(
                  8,
                  (int index) => SeekoTag(
                    controller: controller,
                    targetKey: 'item-$index',
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
    controller.jumpTo(150);
    await tester.pump();

    final ScrollSnapshot snapshot = controller.state.value;
    expect(
      snapshot.visibleTargets.map((ScrollVisibleTarget item) => item.index),
      <int?>[1, 2, 3],
    );
    expect(snapshot.firstVisibleTarget?.key, 'item-1');
    expect(snapshot.lastVisibleTarget?.key, 'item-3');
    expect(snapshot.firstVisibleTarget?.visibleFraction, closeTo(0.5, 1e-9));
    expect(snapshot.firstVisibleTarget?.leadingPixels, closeTo(-50, 0.5));
    expect(snapshot.lastVisibleTarget?.trailingPixels, closeTo(250, 0.5));
    expect(snapshot.anchor?.key, 'item-1');
    expect(snapshot.anchor?.index, 1);
    expect(snapshot.anchor?.itemAnchor, closeTo(0.5, 1e-9));
    expect(snapshot.anchor?.viewportAnchor, 0);
    expect(snapshot.pendingMetricsCorrection, isFalse);
    expect(snapshot.syncTransactionId, isNull);
    controller.dispose();
  });

  testWidgets('raw events are opt-in and preserve programmatic origin',
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
    final List<ScrollRawEvent> events = <ScrollRawEvent>[];
    final StreamSubscription<ScrollRawEvent> subscription =
        controller.rawEvents.listen(events.add);

    controller.jumpTo(120);
    await tester.pump();

    expect(events, isNotEmpty);
    expect(events.last.origin, ScrollEventOrigin.programmatic);
    expect(events.last.pixels, closeTo(120, 0.5));
    expect(controller.state.value.origin, ScrollEventOrigin.programmatic);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(subscription.cancel());
    controller.dispose();
  });

  testWidgets('lockUserInteraction keeps the current command in control',
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
    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(1000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
      options: const ScrollCommandOptions(lockUserInteraction: true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect((await result).outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(1000, 0.5));

    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(1000));
    controller.dispose();
  });

  testWidgets('a superseded command cannot clear the replacement snapshot',
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

    final Future<ScrollResult> first = controller.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final Future<ScrollResult> replacement = controller.animateToTarget(
      ScrollTarget.offset(2000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    final ScrollResult firstResult = await first;
    await tester.pump();

    expect(firstResult.outcome, ScrollOutcome.superseded);
    expect(controller.state.value.phase, ScrollPhase.programmatic);
    expect(controller.state.value.activeCommandId, isNotNull);

    controller.stop();
    await tester.pump();
    expect((await replacement).outcome, ScrollOutcome.cancelled);
    controller.dispose();
  });

  testWidgets('external cancellation stops the real scroll activity',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
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

    final Future<ScrollResult> future = controller.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
      options: ScrollCommandOptions(
        cancellationToken: cancellation.token,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    cancellation.cancel();
    final ScrollResult result = await future;
    final double cancelledAt = controller.offset;
    await tester.pump(const Duration(milliseconds: 500));

    expect(result.outcome, ScrollOutcome.cancelled);
    expect(controller.offset, closeTo(cancelledAt, 0.5));
    cancellation.dispose();
    controller.dispose();
  });
}
