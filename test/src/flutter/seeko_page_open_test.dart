import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  test('page targets and open key resolution preserve value semantics', () {
    final SeekoPageItemTarget first = SeekoPageItemTarget(
      page: 2,
      item: ScrollTarget.key('item'),
      itemPlacement: const ScrollPlacement.center(),
    );
    final SeekoPageItemTarget second = SeekoPageItemTarget(
      page: 2,
      item: ScrollTarget.key('item'),
      itemPlacement: const ScrollPlacement.center(),
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(() => SeekoPageItemTarget.page(-1), throwsRangeError);
    expect(
      () => SeekoPageControllerAdapter(
        pageController: PageController(),
        itemControllerForPage: (_) => null,
        pageCount: -1,
      ),
      throwsRangeError,
    );

    final SeekoOpenDataController<String> data =
        SeekoOpenDataController<String>();
    data.applyPage(
      SeekoOpenPage<String>(
        items: const <SeekoOpenItem<String>>[
          SeekoOpenItem<String>(logicalIndex: 0, key: 'zero', extent: 40),
        ],
        hasMoreBefore: false,
        hasMoreAfter: false,
        revision: 1,
      ),
    );
    expect(data.resolveKey('zero').status, SeekoOpenResolutionStatus.resolved);
    expect(data.resolveKey('missing').status, SeekoOpenResolutionStatus.absent);
  });

  testWidgets('open adapter loads, cancels, and reports finite failures', (
    WidgetTester tester,
  ) async {
    var nextIndex = 1;
    final SeekoOpenDataController<String> data =
        SeekoOpenDataController<String>(
      source: CallbackSeekoOpenDataSource<String>((
        SeekoOpenLoadRequest request,
      ) {
        final int index = nextIndex++;
        return SeekoOpenPage<String>(
          items: <SeekoOpenItem<String>>[
            SeekoOpenItem<String>(
              logicalIndex: index,
              key: 'item-$index',
              extent: 40,
            ),
          ],
          hasMoreBefore: false,
          hasMoreAfter: index < 3,
          revision: request.revision + 1,
        );
      }),
    );
    data.applyPage(
      SeekoOpenPage<String>(
        items: const <SeekoOpenItem<String>>[
          SeekoOpenItem<String>(logicalIndex: 0, key: 'item-0', extent: 40),
        ],
        hasMoreBefore: false,
        hasMoreAfter: true,
        revision: 1,
      ),
    );
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, int index) => Text('row-$index'),
        ),
      ),
    );
    final SeekoOpenScrollAdapter<String> adapter =
        SeekoOpenScrollAdapter<String>(
      controller: controller,
      data: data,
      maxPageLoads: 3,
    );

    final ScrollResult loaded = await pumpScrollCommand(
      tester,
      adapter.jumpToIndex(3),
    );
    expect(loaded.isSuccess, isTrue);
    expect(data.lastLoadedIndex, 3);
    expect(controller.offset, closeTo(120, 0.1));

    final ScrollResult keyResult = await pumpScrollCommand(
      tester,
      adapter.jumpToKey('item-2'),
    );
    expect(keyResult.isSuccess, isTrue);
    expect(controller.offset, closeTo(80, 0.1));
    final ScrollResult missingKey = await adapter.jumpToKey('missing');
    expect(missingKey.outcome, ScrollOutcome.targetDeleted);

    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    cancellation.cancel();
    final ScrollResult cancelled = await adapter.animateToIndex(
      2,
      options: ScrollCommandOptions(cancellationToken: cancellation.token),
    );
    expect(cancelled.outcome, ScrollOutcome.cancelled);
    expect(cancelled.commandId, -1);
    expect(cancelled.diagnostics?['loadedCount'], 4);

    final ScrollResult outOfRange = await adapter.jumpToIndex(8);
    expect(outOfRange.outcome, ScrollOutcome.targetOutOfRange);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    data.dispose();
  });

  testWidgets('open adapter bounds incomplete loading and preserves correction',
      (
    WidgetTester tester,
  ) async {
    final Completer<SeekoOpenPage<String>> page =
        Completer<SeekoOpenPage<String>>();
    final SeekoOpenDataController<String> data =
        SeekoOpenDataController<String>(
      source: CallbackSeekoOpenDataSource<String>((_) => page.future),
    );
    data.applyPage(
      SeekoOpenPage<String>(
        items: const <SeekoOpenItem<String>>[
          SeekoOpenItem<String>(logicalIndex: 0, key: 'zero', extent: 40),
        ],
        hasMoreBefore: true,
        hasMoreAfter: true,
        revision: 1,
      ),
    );
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final SeekoOpenScrollAdapter<String> adapter =
        SeekoOpenScrollAdapter<String>(
      controller: controller,
      data: data,
      maxPageLoads: 1,
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Future<ScrollResult> pending = adapter.jumpToIndex(
      -2,
      options: ScrollCommandOptions(cancellationToken: cancellation.token),
    );
    cancellation.cancel();
    page.complete(
      SeekoOpenPage<String>(
        items: const <SeekoOpenItem<String>>[
          SeekoOpenItem<String>(logicalIndex: -1, key: 'minus', extent: 40),
        ],
        hasMoreBefore: true,
        hasMoreAfter: true,
        revision: 2,
      ),
    );
    expect((await pending).outcome, ScrollOutcome.cancelled);

    final SeekoOpenScrollAdapter<String> bounded =
        SeekoOpenScrollAdapter<String>(
      controller: controller,
      data: data,
      maxPageLoads: 1,
    );
    expect(
        (await bounded.jumpToIndex(-3)).outcome, ScrollOutcome.targetNotLoaded);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    data.dispose();
  });

  testWidgets('page adapter enforces boundaries, restoration, and sync', (
    WidgetTester tester,
  ) async {
    final PageController sourceController = PageController();
    final PageController followerController = PageController(
      viewportFraction: 0.8,
    );
    final List<SeekoController> itemControllers = <SeekoController>[
      SeekoController(),
      SeekoController(),
      SeekoController(),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: sourceController,
                itemCount: 3,
                itemBuilder: (_, int page) => ListView.builder(
                  controller: itemControllers[page],
                  itemCount: 60,
                  itemExtent: 40,
                  itemBuilder: (_, int item) => Text('$page:$item'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: followerController,
                itemCount: 5,
                itemBuilder: (_, int page) => Text('follower-$page'),
              ),
            ),
          ],
        ),
      ),
    );
    final SeekoPageControllerAdapter source = SeekoPageControllerAdapter(
      pageController: sourceController,
      itemControllerForPage: (int page) => itemControllers[page],
      pageCount: 3,
    );
    final SeekoPageControllerAdapter follower = SeekoPageControllerAdapter(
      pageController: followerController,
      itemControllerForPage: (_) => null,
      pageCount: 5,
    );

    final SeekoPageItemResult clamped = await source.jumpToTarget(
      SeekoPageItemTarget.page(20),
    );
    expect(clamped.outcome, ScrollOutcome.clamped);
    expect(clamped.achievedPage, 2);
    expect(
      (await source.jumpToTarget(
        SeekoPageItemTarget.page(20),
        options: const ScrollCommandOptions(
          boundaryPolicy: ScrollBoundaryPolicy.reject,
        ),
      ))
          .outcome,
      ScrollOutcome.targetOutOfRange,
    );
    expect(
      (await source.jumpToTarget(
        SeekoPageItemTarget.page(20),
        options: const ScrollCommandOptions(
          boundaryPolicy: ScrollBoundaryPolicy.allowPhysicsOverscroll,
        ),
      ))
          .outcome,
      ScrollOutcome.unsupported,
    );

    final SeekoPageRestorationState captured = source.captureRestorationState();
    expect(captured.page, 2);
    expect((await source.restore(captured)).isSuccess, isTrue);
    expect(
      (await source.ensureTargetVisible(SeekoPageItemTarget.page(1))).isSuccess,
      isTrue,
    );

    final SeekoPageSyncGroup group = SeekoPageSyncGroup()
      ..add(
        source,
        member: const SeekoPageSyncMember(
          role: SeekoPageSyncRole.leader,
          priority: 10,
        ),
      )
      ..add(
        follower,
        member: const SeekoPageSyncMember(
          role: SeekoPageSyncRole.follower,
        ),
      );
    expect(group.length, 2);
    expect(group.adapters,
        containsAll(<SeekoPageControllerAdapter>[source, follower]));
    expect(() => group.add(source), throwsStateError);
    sourceController.jumpToPage(1);
    await tester.pump();
    expect(followerController.page, closeTo(2, 0.05));
    expect(group.leader, source);
    expect(group.remove(follower), isTrue);
    expect(group.remove(follower), isFalse);
    group.dispose();
    expect(() => group.add(follower), throwsStateError);

    source.dispose();
    follower.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    sourceController.dispose();
    followerController.dispose();
    for (final SeekoController controller in itemControllers) {
      controller.dispose();
    }
  });
}
