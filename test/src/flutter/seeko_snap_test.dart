import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('user scrolling snaps the nearest visible key to placement', (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController(
      snapConfiguration: const SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.nearestVisible(),
        placement: ScrollPlacement.start(),
        motion: ScrollMotion.duration(
          duration: Duration(milliseconds: 80),
          curve: Curves.linear,
        ),
      ),
    );
    await tester.pumpWidget(_taggedList(controller));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(const Key('snap-list'))),
        scrollDelta: const Offset(0, 95),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(controller.offset, closeTo(120, 0.5));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('programmatic writes do not trigger automatic snap', (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController(
      snapConfiguration: const SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.nearestVisible(),
      ),
    );
    await tester.pumpWidget(_taggedList(controller));

    controller.jumpTo(95);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.offset, closeTo(95, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('nearest-visible snap supports mounted index-only tags', (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController(
      snapConfiguration: const SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.nearestVisible(),
        placement: ScrollPlacement.start(),
        motion: ScrollMotion.instant(),
      ),
    );
    await tester.pumpWidget(_taggedList(controller, includeKeys: false));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(const Key('snap-list'))),
        scrollDelta: const Offset(0, 95),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(120, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('manual snap uses an asynchronous custom target resolver', (
    WidgetTester tester,
  ) async {
    var resolveCount = 0;
    final SeekoController controller = SeekoController(
      snapConfiguration: SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.custom((ScrollSnapshot snapshot) async {
          resolveCount += 1;
          await Future<void>.delayed(Duration.zero);
          return ScrollTarget.key(7);
        }),
        placement: const ScrollPlacement.start(),
        motion: const ScrollMotion.instant(),
      ),
    );
    await tester.pumpWidget(_taggedList(controller));

    final ScrollResult? result = await pumpScrollCommand(
      tester,
      controller.snap(),
      maxFrames: 30,
      frameDuration: const Duration(microseconds: 1),
    );

    expect(resolveCount, 1);
    expect(result, isNotNull);
    expect(result!.isSuccess, isTrue);
    expect(controller.offset, closeTo(420, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('programmatic writes cancel a pending custom snap resolver', (
    WidgetTester tester,
  ) async {
    final Completer<ScrollTarget?> resolver = Completer<ScrollTarget?>();
    final SeekoController controller = SeekoController(
      snapConfiguration: SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.custom((_) => resolver.future),
        motion: const ScrollMotion.instant(),
      ),
    );
    await tester.pumpWidget(_taggedList(controller));

    final Future<ScrollResult?> snap = controller.snap();
    await tester.pump();
    controller.jumpTo(300);
    final ScrollResult? result = await pumpScrollCommand(
      tester,
      snap,
      maxFrames: 5,
    );

    expect(result, isNull);
    expect(controller.offset, closeTo(300, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('user input interrupts an active snap animation', (
    WidgetTester tester,
  ) async {
    var resolveCount = 0;
    final SeekoController controller = SeekoController(
      snapConfiguration: SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.custom((_) {
          resolveCount += 1;
          return resolveCount == 1 ? ScrollTarget.offset(1000) : null;
        }),
        motion: const ScrollMotion.duration(
          duration: Duration(seconds: 1),
          curve: Curves.linear,
        ),
      ),
    );
    await tester.pumpWidget(_taggedList(controller));

    final Future<ScrollResult?> snap = controller.snap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(const Key('snap-list'))),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pumpAndSettle();
    final ScrollResult? result = await snap;

    expect(result, isNotNull);
    expect(result!.outcome, ScrollOutcome.interruptedByUser);
    expect(controller.offset, isNot(closeTo(1000, 0.5)));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('disposing cancels a pending custom snap resolver', (
    WidgetTester tester,
  ) async {
    final Completer<ScrollTarget?> resolver = Completer<ScrollTarget?>();
    final SeekoController controller = SeekoController(
      snapConfiguration: SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.custom((_) => resolver.future),
      ),
    );
    await tester.pumpWidget(_taggedList(controller));

    final Future<ScrollResult?> snap = controller.snap();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    final ScrollResult? result = await pumpScrollCommand(
      tester,
      snap,
      maxFrames: 5,
    );

    expect(result, isNull);
  });

  testWidgets('sync followers do not start duplicate snap transactions', (
    WidgetTester tester,
  ) async {
    var leaderResolves = 0;
    var followerResolves = 0;
    const SeekoSnapResolver nearest = SeekoSnapResolver.nearestVisible();
    final SeekoController leader = SeekoController(
      snapConfiguration: SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.custom((ScrollSnapshot snapshot) {
          leaderResolves += 1;
          return nearest.resolve(snapshot);
        }),
        placement: const ScrollPlacement.start(),
        motion: const ScrollMotion.instant(),
      ),
    );
    final SeekoController follower = SeekoController(
      snapConfiguration: SeekoSnapConfiguration(
        resolver: SeekoSnapResolver.custom((ScrollSnapshot snapshot) {
          followerResolves += 1;
          return nearest.resolve(snapshot);
        }),
        placement: const ScrollPlacement.start(),
        motion: const ScrollMotion.instant(),
      ),
    );
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    group.add(leader, id: 'leader');
    group.add(follower, id: 'follower');
    await tester.pumpWidget(_twoTaggedLists(leader, follower));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(const Key('snap-left'))),
        scrollDelta: const Offset(0, 95),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(leader.offset, closeTo(120, 0.5));
    expect(follower.offset, closeTo(120, 0.5));
    expect(leaderResolves, 1);
    expect(followerResolves, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    leader.dispose();
    follower.dispose();
  });
}

Widget _taggedList(
  SeekoController controller, {
  bool includeKeys = true,
}) {
  return MaterialApp(
    home: SizedBox(
      height: 200,
      child: ListView.builder(
        key: const Key('snap-list'),
        controller: controller,
        itemExtent: 60,
        itemCount: 50,
        itemBuilder: (BuildContext context, int index) => SeekoTag(
          controller: controller,
          targetKey: includeKeys ? index : null,
          index: index,
          child: Text('Item $index'),
        ),
      ),
    ),
  );
}

Widget _twoTaggedLists(
  SeekoController left,
  SeekoController right,
) {
  return MaterialApp(
    home: Row(
      children: <Widget>[
        Expanded(child: _bareTaggedList(left, const Key('snap-left'))),
        Expanded(child: _bareTaggedList(right, const Key('snap-right'))),
      ],
    ),
  );
}

Widget _bareTaggedList(SeekoController controller, Key key) {
  return ListView.builder(
    key: key,
    controller: controller,
    itemExtent: 60,
    itemCount: 50,
    itemBuilder: (BuildContext context, int index) => SeekoTag(
      controller: controller,
      targetKey: index,
      index: index,
      child: Text('Item $index'),
    ),
  );
}
