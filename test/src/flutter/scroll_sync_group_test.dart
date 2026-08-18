import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('group notifies when members attach to scroll positions', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    group.add(left, id: 'left');
    group.add(right, id: 'right');
    final List<int> observedActiveCounts = <int>[];
    group.addListener(() {
      observedActiveCounts.add(group.activeMemberCount);
    });

    await tester.pumpWidget(_twoLists(left: left, right: right));
    await tester.pump();

    expect(group.activeMemberCount, 2);
    expect(observedActiveCounts, contains(2));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('progress group maps different extents without feedback', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    group.add(left, id: 'left');
    group.add(right, id: 'right');

    await tester.pumpWidget(
      _twoLists(left: left, right: right, leftCount: 100, rightCount: 220),
    );
    left.jumpTo(1200);
    await tester.pump();

    final double leftProgress = left.offset / left.position.maxScrollExtent;
    final double rightProgress = right.offset / right.position.maxScrollExtent;
    expect(rightProgress, closeTo(leftProgress, 1e-9));
    expect(group.transactionCount, 1);
    expect(group.followerApplyCount, 1);
    expect(group.activeLeaderId, 'left');

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('progress group corrects lazy variable-extent metric changes', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    group.add(left, id: 'left');
    group.add(right, id: 'right');

    await tester.pumpWidget(
      _twoVariableLists(left: left, right: right),
    );
    await tester.drag(
        find.byKey(const Key('variable-left')), const Offset(0, -520));
    await tester.pumpAndSettle();

    final double leftProgress = left.offset / left.position.maxScrollExtent;
    final double rightProgress = right.offset / right.position.maxScrollExtent;
    expect(rightProgress, closeTo(leftProgress, 1e-9));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('progress correction does not oscillate after a long drag', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    group.add(left, id: 'left');
    group.add(right, id: 'right');

    await tester.pumpWidget(_twoVariableLists(left: left, right: right));
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('variable-left'))),
    );
    for (var index = 0; index < 120; index += 1) {
      await gesture.moveBy(const Offset(0, -18));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();

    final List<double> settledOffsets = <double>[];
    for (var index = 0; index < 120; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      settledOffsets.add(right.offset);
    }
    expect(
      settledOffsets.skip(20).toSet(),
      hasLength(1),
      reason: 'follower metrics must not reopen the same correction loop',
    );
    expect(
      right.offset / right.position.maxScrollExtent,
      closeTo(left.offset / left.position.maxScrollExtent, 1e-9),
      reason: 'suppressing an oscillation must still settle at the canonical '
          'progress coordinate',
    );

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('either bidirectional member can take over as leader', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    group.add(left, id: 'left', priority: 1);
    group.add(right, id: 'right', priority: 2);
    await tester.pumpWidget(_twoLists(left: left, right: right));

    left.jumpTo(300);
    await tester.pump();
    expect(right.offset, closeTo(300, 0.5));

    right.jumpTo(700);
    await tester.pump();
    expect(left.offset, closeTo(700, 0.5));
    expect(group.activeLeaderId, 'right');
    expect(group.transactionCount, 2);

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('same-frame leader arbitration honors member priority', (
    WidgetTester tester,
  ) async {
    final SeekoController high = SeekoController();
    final SeekoController low = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    group.add(high, id: 'high', priority: 10);
    group.add(low, id: 'low', priority: 1);
    await tester.pumpWidget(_twoLists(left: high, right: low));

    high.jumpTo(400);
    low.jumpTo(700);
    await tester.pump();

    expect(group.activeLeaderId, 'high');
    expect(high.offset, closeTo(400, 0.5));
    expect(low.offset, closeTo(400, 0.5));
    expect(group.transactionCount, 1);

    group.dispose();
    high.dispose();
    low.dispose();
  });

  testWidgets('late reactivation catches the canonical snapshot', (
    WidgetTester tester,
  ) async {
    final SeekoController source = SeekoController();
    final SeekoController follower = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    final ScrollSyncMember sourceMember = group.add(source, id: 'source');
    final ScrollSyncMember followerMember = group.add(follower, id: 'follower');
    await tester.pumpWidget(_twoLists(left: source, right: follower));

    followerMember.participation = ScrollSyncParticipation.offstage;
    source.jumpTo(360);
    await tester.pump();
    sourceMember.remove();

    followerMember.participation = ScrollSyncParticipation.active;
    await tester.pump();

    expect(follower.offset, closeTo(360, 0.5));
    expect(group.activeLeaderId, isNull);

    group.dispose();
    source.dispose();
    follower.dispose();
  });

  testWidgets('stop-at-first-boundary keeps every member aligned', (
    WidgetTester tester,
  ) async {
    final SeekoController long = SeekoController();
    final SeekoController short = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels(
      boundaryPolicy: ScrollSyncBoundaryPolicy.stopAtFirstBoundary,
    );
    group.add(long, id: 'long');
    group.add(short, id: 'short');
    await tester.pumpWidget(
      _twoLists(
        left: long,
        right: short,
        leftCount: 120,
        rightCount: 20,
      ),
    );
    final double sharedBoundary = short.position.maxScrollExtent;

    long.jumpTo(sharedBoundary + 800);
    await tester.pump();

    expect(long.offset, closeTo(sharedBoundary, 0.5));
    expect(short.offset, closeTo(sharedBoundary, 0.5));
    expect(group.activeLeaderId, isNull);

    group.dispose();
    long.dispose();
    short.dispose();
  });

  testWidgets('programmatic group animation uses one canonical ticker', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    group.add(left, id: 'left');
    group.add(right, id: 'right');
    await tester.pumpWidget(
      _twoLists(left: left, right: right, leftCount: 100, rightCount: 220),
    );
    final _CountingTickerProvider vsync = _CountingTickerProvider();

    final Future<GroupScrollResult> future = group.animateToCoordinate(
      0.75,
      vsync: vsync,
      duration: const Duration(milliseconds: 240),
      curve: Curves.linear,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      left.offset / left.position.maxScrollExtent,
      closeTo(0.375, 0.01),
    );
    expect(
      right.offset / right.position.maxScrollExtent,
      closeTo(0.375, 0.01),
    );
    await tester.pump(const Duration(milliseconds: 120));
    final GroupScrollResult result = await future;

    expect(vsync.createdTickerCount, 1);
    expect(result.outcome, GroupScrollOutcome.completed);
    expect(result.members, hasLength(2));
    expect(
      result.members.map((GroupScrollMemberResult value) => value.outcome),
      everyElement(GroupScrollMemberOutcome.completed),
    );
    expect(left.offset / left.position.maxScrollExtent, closeTo(0.75, 1e-9));
    expect(right.offset / right.position.maxScrollExtent, closeTo(0.75, 1e-9));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets(
      'programmatic natural animation waits for member-local settlement', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    final ScrollSyncMember leftMember = group.add(
      left,
      id: 'left',
      naturalPhysicsProfile: _boundedNaturalProfile,
    );
    final ScrollSyncMember rightMember = group.add(
      right,
      id: 'right',
      naturalPhysicsProfile: _boundedNaturalProfile,
    );
    await tester.pumpWidget(
      _twoLists(left: left, right: right, leftCount: 100, rightCount: 220),
    );
    final _CountingTickerProvider vsync = _CountingTickerProvider();
    var completed = false;

    final Future<GroupScrollResult> future = group
        .animateToCoordinate(
          0.75,
          vsync: vsync,
          duration: const Duration(milliseconds: 120),
          curve: Curves.linear,
        )
        .whenComplete(() => completed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(vsync.createdTickerCount, 1);
    expect(leftMember.naturalDiagnostics, isNotNull);
    expect(rightMember.naturalDiagnostics, isNotNull);
    expect(left.offset / left.position.maxScrollExtent, lessThan(0.375));
    expect(right.offset / right.position.maxScrollExtent, lessThan(0.375));

    await tester.pump(const Duration(milliseconds: 60));
    expect(completed, isFalse);
    expect(leftMember.naturalDiagnostics!.isSettled, isFalse);
    expect(rightMember.naturalDiagnostics!.isSettled, isFalse);

    await tester.pump(_boundedNaturalProfile.settleDuration);
    await tester.pump();
    final GroupScrollResult result = await future;

    expect(result.outcome, GroupScrollOutcome.completed);
    expect(leftMember.naturalDiagnostics!.isSettled, isTrue);
    expect(rightMember.naturalDiagnostics!.isSettled, isTrue);
    expect(left.offset / left.position.maxScrollExtent, closeTo(0.75, 1e-9));
    expect(right.offset / right.position.maxScrollExtent, closeTo(0.75, 1e-9));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('user input interrupts a programmatic group animation', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    group.add(left, id: 'left');
    group.add(right, id: 'right');
    await tester.pumpWidget(
      _twoLists(left: left, right: right, leftCount: 100, rightCount: 220),
    );
    final _CountingTickerProvider vsync = _CountingTickerProvider();
    final Future<GroupScrollResult> future = group.animateToCoordinate(
      0.75,
      vsync: vsync,
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(
      find.byKey(const Key('sync-left')),
      const Offset(0, -120),
    );
    await tester.pump();
    final GroupScrollResult result = await future;
    final double userPosition = left.offset;

    expect(result.outcome, GroupScrollOutcome.interruptedByUser);
    expect(
      result.members.map((GroupScrollMemberResult value) => value.outcome),
      everyElement(GroupScrollMemberOutcome.interruptedByUser),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(left.offset, closeTo(userPosition, 0.5));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('semantic mapping aligns stable keys with different extents', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 200,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 200,
      revision: rightRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    group.add(left, id: 'left');
    group.add(right, id: 'right');
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              child: CustomScrollView(
                controller: left,
                slivers: <Widget>[
                  SeekoIndexedSliver(
                    controller: left,
                    indexDelegate: leftDelegate,
                    estimatedExtent: 40,
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) =>
                          SizedBox(height: 40, child: Text('L$index')),
                      childCount: 200,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                controller: right,
                slivers: <Widget>[
                  SeekoIndexedSliver(
                    controller: right,
                    indexDelegate: rightDelegate,
                    estimatedExtent: 76,
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) => SizedBox(
                        height: 64.0 + (index % 4) * 8,
                        child: Text('R$index'),
                      ),
                      childCount: 200,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final ScrollResult command = await pumpScrollCommand(
      tester,
      left.jumpToKey(
        120,
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 30,
    );
    await tester.pump();
    await tester.pump();

    expect(command.isSuccess, isTrue);
    expect(left.state.value.firstVisibleTarget?.key, 120);
    expect(right.state.value.firstVisibleTarget?.key, 120);
    expect(
      right.state.value.firstVisibleTarget!.leadingPixels,
      closeTo(left.state.value.firstVisibleTarget!.leadingPixels, 0.5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets(
    'semantic member mappings synchronize heterogeneous keys bidirectionally',
    (WidgetTester tester) async {
      final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
      final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
      final ListSeekoIndexDelegate<int> leftDelegate =
          ListSeekoIndexDelegate<int>(
        itemCount: 50,
        revision: leftRevision,
        keyAt: (int index) => index,
        indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
      );
      final ListSeekoIndexDelegate<int> rightDelegate =
          ListSeekoIndexDelegate<int>(
        itemCount: 50,
        revision: rightRevision,
        keyAt: (int index) => 100 + index,
        indexOfKey: (int key) => key >= 100 && key < 150 ? key - 100 : null,
      );
      final SeekoController left = SeekoController(indexDelegate: leftDelegate);
      final SeekoController right =
          SeekoController(indexDelegate: rightDelegate);
      final ScrollSyncGroup group = ScrollSyncGroup.semantic();
      group.add(
        left,
        id: 'left',
        semanticMapping: CallbackScrollSyncSemanticMapping(
          memberToCanonical: (_, __, ScrollSemanticAnchor anchor) =>
              ScrollSyncSemanticMappingResult.mapped(anchor),
          canonicalToMember: (_, ScrollSemanticAnchor anchor) =>
              ScrollSyncSemanticMappingResult.mapped(anchor),
        ),
      );
      group.add(
        right,
        id: 'right',
        semanticMapping: CallbackScrollSyncSemanticMapping(
          memberToCanonical: (_, __, ScrollSemanticAnchor anchor) {
            return ScrollSyncSemanticMappingResult.mapped(
              _semanticAnchorWithKey(anchor, (anchor.key! as int) - 100),
            );
          },
          canonicalToMember: (_, ScrollSemanticAnchor anchor) {
            return ScrollSyncSemanticMappingResult.mapped(
              _semanticAnchorWithKey(anchor, (anchor.key! as int) + 100),
            );
          },
        ),
      );
      await tester.pumpWidget(
        _twoIndexedLists(
          left: left,
          right: right,
          leftDelegate: leftDelegate,
          rightDelegate: rightDelegate,
        ),
      );

      await pumpScrollCommand(
        tester,
        left.jumpToKey(20, placement: const ScrollPlacement.start()),
      );
      await tester.pump();
      await tester.pump();
      expect(right.state.value.firstVisibleTarget?.key, 120);

      await pumpScrollCommand(
        tester,
        right.jumpToKey(135, placement: const ScrollPlacement.start()),
      );
      await tester.pump();
      await tester.pump();
      expect(left.state.value.firstVisibleTarget?.key, 35);
      expect(group.activeLeaderId, 'right');

      await tester.pumpWidget(const SizedBox.shrink());
      group.dispose();
      left.dispose();
      right.dispose();
      leftRevision.dispose();
      rightRevision.dispose();
    },
  );

  testWidgets('section mapping preserves canonical progress inside a section', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: rightRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final SeekoSectionDomain<int> domain =
        SeekoSectionDomain<int>.fixed(<int>[0, 1, 2, 3, 4]);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    group.add(
      left,
      id: 'left',
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
      ),
    );
    group.add(
      right,
      id: 'right',
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
      ),
    );
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );

    await pumpScrollCommand(
      tester,
      left.jumpToTarget(ScrollTarget.offset(500)),
    );
    await tester.pump();
    await tester.pump();

    const double rightSectionStart = 632;
    const double rightNextSectionStart = 1272;
    expect(
      right.offset,
      closeTo(
        rightSectionStart + (rightNextSectionStart - rightSectionStart) * 0.25,
        0.5,
      ),
    );
    final ScrollSemanticAnchor canonical = group.canonicalSemanticAnchor!;
    final SeekoSectionCoordinate<int> coordinate =
        canonical.key! as SeekoSectionCoordinate<int>;
    expect(coordinate.section, 1);
    expect(coordinate.progress, closeTo(0.25, 1e-6));

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    domain.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('section progress uses the unobstructed viewport anchor', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: rightRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    VisibleRegion obstruction(ScrollViewportGeometry viewport) =>
        VisibleRegion.fromIntervals(<LogicalInterval>[
          LogicalInterval(40, viewport.viewportExtent),
        ]);
    final SeekoController left = SeekoController(
      indexDelegate: leftDelegate,
      obstructionResolver: obstruction,
    );
    final SeekoController right = SeekoController(
      indexDelegate: rightDelegate,
      obstructionResolver: obstruction,
    );
    final SeekoSectionDomain<int> domain =
        SeekoSectionDomain<int>.fixed(<int>[0, 1, 2, 3, 4]);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    for (final SeekoController controller in <SeekoController>[left, right]) {
      group.add(
        controller,
        semanticMapping: SeekoSectionSemanticMapping<int>(
          domain: domain,
          sectionOfTarget: (ScrollVisibleTarget target) =>
              (target.key! as int) ~/ 10,
          sectionTarget: (int section) => ScrollTarget.key(section * 10),
        ),
      );
    }
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );

    await pumpScrollCommand(
      tester,
      left.jumpToTarget(ScrollTarget.offset(500)),
    );
    await tester.pump();
    await tester.pump();

    final SeekoSectionCoordinate<int> coordinate =
        group.canonicalSemanticAnchor!.key! as SeekoSectionCoordinate<int>;
    expect(coordinate.section, 1);
    expect(coordinate.progress, closeTo(0.35, 1e-6));
    expect(right.offset, closeTo(816, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    domain.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('section mapping falls back by canonical section order', (
    WidgetTester tester,
  ) async {
    final List<int> rightKeys = <int>[
      ...List<int>.generate(10, (int index) => index),
      ...List<int>.generate(20, (int index) => index + 20),
    ];
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 40,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 40 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: rightKeys.length,
      revision: rightRevision,
      keyAt: (int index) => rightKeys[index],
      indexOfKey: rightKeys.indexOf,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final SeekoSectionDomain<int> domain =
        SeekoSectionDomain<int>.fixed(<int>[0, 1, 2, 3]);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    group.add(
      left,
      id: 'left',
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
      ),
    );
    final ScrollSyncMember rightMember = group.add(
      right,
      id: 'right',
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
        missingSectionPolicy: SeekoMissingSectionPolicy.previousThenNext,
      ),
    );
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );
    await pumpScrollCommand(
      tester,
      right.jumpToKey(30, placement: const ScrollPlacement.start()),
    );

    await pumpScrollCommand(
      tester,
      left.jumpToKey(10, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    await tester.pump();

    expect(right.state.value.firstVisibleTarget?.key, 0);
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.fallback,
    );
    expect(rightMember.synchronizationFailure, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    domain.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('section domain reorder reapplies the canonical fallback', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<int>> sections =
        ValueNotifier<List<int>>(<int>[0, 1, 2, 3]);
    final List<int> rightKeys = <int>[
      ...List<int>.generate(10, (int index) => index),
      ...List<int>.generate(20, (int index) => index + 20),
    ];
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 40,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 40 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: rightKeys.length,
      revision: rightRevision,
      keyAt: (int index) => rightKeys[index],
      indexOfKey: rightKeys.indexOf,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final SeekoSectionDomain<int> domain =
        SeekoSectionDomain<int>.listenable(sections);
    final SeekoSectionSemanticMapping<int> leftMapping =
        SeekoSectionSemanticMapping<int>(
      domain: domain,
      sectionOfTarget: (ScrollVisibleTarget target) =>
          (target.key! as int) ~/ 10,
      sectionTarget: (int section) => ScrollTarget.key(section * 10),
    );
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    group.add(left, id: 'left', semanticMapping: leftMapping);
    group.add(
      right,
      id: 'right',
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
        missingSectionPolicy: SeekoMissingSectionPolicy.previousThenNext,
      ),
    );
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );
    await pumpScrollCommand(
      tester,
      left.jumpToKey(10, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    expect(right.state.value.firstVisibleTarget?.key, 0);

    sections.value = <int>[3, 2, 1, 0];
    await tester.pump();
    await tester.pump();

    expect(right.state.value.firstVisibleTarget?.key, 20);
    final SeekoSectionCoordinate<int> coordinate =
        group.canonicalSemanticAnchor!.key! as SeekoSectionCoordinate<int>;
    expect(coordinate.section, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    domain.dispose();
    sections.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('deleted canonical section falls back from its prior index', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<int>> sections =
        ValueNotifier<List<int>>(<int>[0, 1, 2, 3]);
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 40,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 40 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 40,
      revision: rightRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 40 ? key : null,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final SeekoSectionDomain<int> domain =
        SeekoSectionDomain<int>.listenable(sections);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    group.add(
      left,
      id: 'left',
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
      ),
    );
    final ScrollSyncMember rightMember = group.add(
      right,
      id: 'right',
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
        missingSectionPolicy: SeekoMissingSectionPolicy.previousThenNext,
      ),
    );
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );
    await pumpScrollCommand(
      tester,
      left.jumpToKey(10, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    expect(right.state.value.firstVisibleTarget?.key, 10);

    sections.value = <int>[0, 2, 3];
    await tester.pump();
    await tester.pump();

    expect(right.state.value.firstVisibleTarget?.key, 0);
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.fallback,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    domain.dispose();
    sections.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('collapsed section aligns to its retained local anchor', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 30,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 30 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 30,
      revision: rightRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 30 ? key : null,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final SeekoSectionDomain<int> domain =
        SeekoSectionDomain<int>.fixed(<int>[0, 1, 2]);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    group.add(
      left,
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) => ScrollTarget.key(section * 10),
      ),
    );
    final ScrollSyncMember rightMember = group.add(
      right,
      semanticMapping: SeekoSectionSemanticMapping<int>(
        domain: domain,
        sectionOfTarget: (ScrollVisibleTarget target) =>
            (target.key! as int) ~/ 10,
        sectionTarget: (int section) =>
            ScrollTarget.key(section == 1 ? 20 : section * 10),
      ),
    );
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );

    await pumpScrollCommand(
      tester,
      left.jumpToKey(10, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    await tester.pump();

    expect(right.state.value.firstVisibleTarget?.key, 20);
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.synchronized,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    domain.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('section mapping preserves the final section at trailing edge', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: rightRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final SeekoSectionDomain<int> domain =
        SeekoSectionDomain<int>.fixed(<int>[0, 1, 2, 3, 4]);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic();
    for (final (String, SeekoController) member in <(String, SeekoController)>[
      ('left', left),
      ('right', right),
    ]) {
      group.add(
        member.$2,
        id: member.$1,
        semanticMapping: SeekoSectionSemanticMapping<int>(
          domain: domain,
          sectionOfTarget: (ScrollVisibleTarget target) =>
              (target.key! as int) ~/ 10,
          sectionTarget: (int section) => ScrollTarget.key(section * 10),
        ),
      );
    }
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );

    await pumpScrollCommand(
      tester,
      left.jumpToTarget(const ScrollTarget.edge(ScrollEdge.trailing)),
    );
    await tester.pump();
    await tester.pump();

    expect(right.offset, closeTo(right.position.maxScrollExtent, 0.5));
    final SeekoSectionCoordinate<int> coordinate =
        group.canonicalSemanticAnchor!.key! as SeekoSectionCoordinate<int>;
    expect(coordinate.section, 4);
    expect(coordinate.progress, closeTo(1, 1e-6));

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    domain.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('semantic hold keeps position while the anchor is missing', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: rightRevision,
      keyAt: (int index) => 100 + index,
      indexOfKey: (int key) => key >= 100 && key < 150 ? key - 100 : null,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic(
      missingAnchorPolicy: ScrollSyncMissingAnchorPolicy.hold,
    );
    group.add(left, id: 'left');
    final ScrollSyncMember rightMember = group.add(right, id: 'right');
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );
    final double initialRight = right.offset;

    final ScrollResult result = await pumpScrollCommand(
      tester,
      left.jumpToKey(20, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    await tester.pump();

    expect(result.isSuccess, isTrue);
    expect(right.offset, initialRight);
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.holding,
    );
    expect(rightMember.synchronizationFailure, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('semantic fallback reports progress-based synchronization', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: rightRevision,
      keyAt: (int index) => 100 + index,
      indexOfKey: (int key) => key >= 100 && key < 150 ? key - 100 : null,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic(
      missingAnchorPolicy: ScrollSyncMissingAnchorPolicy.fallbackProgress,
    );
    group.add(left, id: 'left');
    final ScrollSyncMember rightMember = group.add(right, id: 'right');
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      left.jumpToKey(20, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    await tester.pump();

    expect(result.isSuccess, isTrue);
    expect(
        right.state.value.progress, closeTo(left.state.value.progress!, 0.01));
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.fallback,
    );
    expect(rightMember.synchronizationFailure, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('semantic desync exposes a missing-anchor diagnostic', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: leftRevision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 50 ? key : null,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 50,
      revision: rightRevision,
      keyAt: (int index) => 100 + index,
      indexOfKey: (int key) => key >= 100 && key < 150 ? key - 100 : null,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic(
      missingAnchorPolicy: ScrollSyncMissingAnchorPolicy.desynchronized,
    );
    group.add(left, id: 'left');
    final ScrollSyncMember rightMember = group.add(right, id: 'right');
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );
    final double initialRight = right.offset;

    final ScrollResult result = await pumpScrollCommand(
      tester,
      left.jumpToKey(20, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    await tester.pump();

    expect(result.isSuccess, isTrue);
    expect(right.offset, initialRight);
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.desynchronized,
    );
    expect(rightMember.synchronizationFailure, contains('key=20'));

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('semantic sync follows reorder and reports deleted anchors', (
    WidgetTester tester,
  ) async {
    final List<int> leftKeys = List<int>.generate(60, (int index) => index);
    final List<int> rightKeys = List<int>.of(leftKeys);
    final ValueNotifier<int> leftRevision = ValueNotifier<int>(0);
    final ValueNotifier<int> rightRevision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> leftDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: leftKeys.length,
      revision: leftRevision,
      keyAt: (int index) => leftKeys[index],
      indexOfKey: leftKeys.indexOf,
    );
    final ListSeekoIndexDelegate<int> rightDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: rightKeys.length,
      revision: rightRevision,
      keyAt: (int index) => rightKeys[index],
      indexOfKey: rightKeys.indexOf,
    );
    final SeekoController left = SeekoController(indexDelegate: leftDelegate);
    final SeekoController right = SeekoController(indexDelegate: rightDelegate);
    final ScrollSyncGroup group = ScrollSyncGroup.semantic(
      missingAnchorPolicy: ScrollSyncMissingAnchorPolicy.desynchronized,
    );
    group.add(left, id: 'left');
    final ScrollSyncMember rightMember = group.add(right, id: 'right');
    await tester.pumpWidget(
      _twoIndexedLists(
        left: left,
        right: right,
        leftDelegate: leftDelegate,
        rightDelegate: rightDelegate,
      ),
    );

    await pumpScrollCommand(
      tester,
      left.jumpToKey(20, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    expect(right.state.value.firstVisibleTarget?.key, 20);

    rightKeys
      ..remove(20)
      ..insert(35, 20);
    rightRevision.value += 1;
    await tester.pump();
    await pumpScrollCommand(
      tester,
      left.jumpToKey(10, placement: const ScrollPlacement.start()),
    );
    await pumpScrollCommand(
      tester,
      left.jumpToKey(20, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    await tester.pump();

    expect(right.state.value.firstVisibleTarget?.key, 20);
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.synchronized,
    );

    rightKeys
      ..remove(20)
      ..add(1000);
    rightRevision.value += 1;
    await tester.pump();
    await pumpScrollCommand(
      tester,
      left.jumpToKey(10, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    final double heldPixels = right.offset;
    await pumpScrollCommand(
      tester,
      left.jumpToKey(20, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    await tester.pump();

    expect(right.offset, heldPixels);
    expect(
      rightMember.synchronizationStatus,
      ScrollSyncMemberSynchronizationStatus.desynchronized,
    );
    expect(rightMember.synchronizationFailure, contains('key=20'));

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    left.dispose();
    right.dispose();
    leftRevision.dispose();
    rightRevision.dispose();
  });

  testWidgets('fail-group policy stops propagation after member detach', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels(
      memberFailurePolicy: ScrollSyncMemberFailurePolicy.failGroup,
    );
    group.add(left, id: 'left');
    group.add(right, id: 'right');
    var showRight = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return Row(
              children: <Widget>[
                Expanded(
                  child: ListView.builder(
                    key: const Key('failure-left'),
                    controller: left,
                    itemExtent: 40,
                    itemCount: 120,
                    itemBuilder: (_, int index) => Text('L$index'),
                  ),
                ),
                if (showRight)
                  Expanded(
                    child: ListView.builder(
                      key: const Key('failure-right'),
                      controller: right,
                      itemExtent: 40,
                      itemCount: 120,
                      itemBuilder: (_, int index) => Text('R$index'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    left.jumpTo(300);
    await tester.pump();
    expect(right.offset, closeTo(300, 0.5));

    rebuild(() {
      showRight = false;
    });
    await tester.pump();

    expect(group.isFailed, isTrue);
    expect(group.failureReason, contains('right'));
    left.jumpTo(600);
    await tester.pump();
    expect(right.hasClients, isFalse);

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('natural mode converges with bounded member physics', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    const NaturalSyncPhysicsProfile profile = NaturalSyncPhysicsProfile(
      settleDuration: Duration(milliseconds: 80),
      curve: Curves.easeOutCubic,
      convergesToTarget: true,
      boundedDuration: true,
      supportsExternalInitialVelocity: false,
      snapBehavior: NaturalSyncSnapBehavior.none,
    );
    group.add(left, id: 'left', naturalPhysicsProfile: profile);
    group.add(right, id: 'right', naturalPhysicsProfile: profile);
    await tester.pumpWidget(
      _twoLists(left: left, right: right, leftCount: 100, rightCount: 220),
    );

    left.jumpTo(left.position.maxScrollExtent * 0.75);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final double midpoint = right.offset / right.position.maxScrollExtent;
    expect(midpoint, greaterThan(0));
    expect(midpoint, lessThan(0.75));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(
      right.offset / right.position.maxScrollExtent,
      closeTo(0.75, 1e-9),
    );

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('natural mode reports bounded response and settle diagnostics', (
    WidgetTester tester,
  ) async {
    final SeekoController leader = SeekoController();
    final SeekoController follower = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    group.add(
      leader,
      id: 'leader',
      naturalPhysicsProfile: _boundedNaturalProfile,
    );
    final ScrollSyncMember followerMember = group.add(
      follower,
      id: 'follower',
      naturalPhysicsProfile: _boundedNaturalProfile,
    );
    await tester.pumpWidget(
      _twoLists(
        left: leader,
        right: follower,
        leftCount: 100,
        rightCount: 220,
      ),
    );

    leader.jumpTo(leader.position.maxScrollExtent * 0.75);
    await tester.pump();
    final NaturalSyncMemberDiagnostics started =
        followerMember.naturalDiagnostics!;
    expect(started.transactionId, group.activeTransactionId);
    expect(started.targetLogicalPixels, greaterThan(0));
    expect(started.currentMappingError, greaterThan(0));
    expect(started.peakMappingError, started.currentMappingError);
    expect(started.phaseLag, isNull);
    expect(started.settleLag, isNull);
    expect(started.isSettled, isFalse);

    await tester.pump(const Duration(milliseconds: 16));
    final NaturalSyncMemberDiagnostics moving =
        followerMember.naturalDiagnostics!;
    expect(moving.phaseLag, isNotNull);
    expect(
        moving.phaseLag!, lessThanOrEqualTo(const Duration(milliseconds: 16)));
    expect(moving.currentMappingError, lessThan(started.currentMappingError));
    expect(moving.peakMappingError, started.peakMappingError);

    await tester.pump(const Duration(milliseconds: 64));
    await tester.pump();
    final NaturalSyncMemberDiagnostics settled =
        followerMember.naturalDiagnostics!;
    expect(settled.isSettled, isTrue);
    expect(settled.currentMappingError, lessThanOrEqualTo(0.5));
    expect(settled.settleLag, isNotNull);
    expect(
      settled.settleLag!,
      lessThanOrEqualTo(_boundedNaturalProfile.settleDuration),
    );

    group.dispose();
    leader.dispose();
    follower.dispose();
  });

  test('natural mode requires an explicit profile for participants', () {
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    final SeekoController participant = SeekoController();
    final SeekoController observer = SeekoController();
    addTearDown(() {
      group.dispose();
      participant.dispose();
      observer.dispose();
    });

    expect(
      () => group.add(participant),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => group.add(observer, role: ScrollSyncRole.observer),
      returnsNormally,
    );
  });

  test('natural mode rejects profiles without bounded convergence', () {
    final List<NaturalSyncPhysicsProfile> invalid = <NaturalSyncPhysicsProfile>[
      const NaturalSyncPhysicsProfile(
        settleDuration: Duration.zero,
        curve: Curves.linear,
        convergesToTarget: true,
        boundedDuration: true,
        supportsExternalInitialVelocity: false,
        snapBehavior: NaturalSyncSnapBehavior.none,
      ),
      const NaturalSyncPhysicsProfile(
        settleDuration: Duration(milliseconds: 80),
        curve: Curves.linear,
        convergesToTarget: false,
        boundedDuration: true,
        supportsExternalInitialVelocity: false,
        snapBehavior: NaturalSyncSnapBehavior.none,
      ),
      const NaturalSyncPhysicsProfile(
        settleDuration: Duration(milliseconds: 80),
        curve: Curves.linear,
        convergesToTarget: true,
        boundedDuration: false,
        supportsExternalInitialVelocity: false,
        snapBehavior: NaturalSyncSnapBehavior.none,
      ),
      const NaturalSyncPhysicsProfile(
        settleDuration: Duration(milliseconds: 80),
        curve: _NonConvergingCurve(),
        convergesToTarget: true,
        boundedDuration: true,
        supportsExternalInitialVelocity: false,
        snapBehavior: NaturalSyncSnapBehavior.none,
      ),
    ];

    for (final NaturalSyncPhysicsProfile profile in invalid) {
      final ScrollSyncGroup group = ScrollSyncGroup.progress(
        mode: ScrollSyncMode.natural,
      );
      final SeekoController controller = SeekoController();
      expect(
        () => group.add(controller, naturalPhysicsProfile: profile),
        throwsA(isA<ArgumentError>()),
      );
      group.dispose();
      controller.dispose();
    }
  });

  test('natural mode rejects incompatible member contracts', () {
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    final SeekoController first = SeekoController();
    final SeekoController velocityMismatch = SeekoController();
    final SeekoController snapMismatch = SeekoController();
    final SeekoController settleMismatch = SeekoController();
    addTearDown(() {
      group.dispose();
      first.dispose();
      velocityMismatch.dispose();
      snapMismatch.dispose();
      settleMismatch.dispose();
    });
    group.add(first, naturalPhysicsProfile: _boundedNaturalProfile);

    expect(
      () => group.add(
        velocityMismatch,
        naturalPhysicsProfile: const NaturalSyncPhysicsProfile(
          settleDuration: Duration(milliseconds: 80),
          curve: Curves.easeOutCubic,
          convergesToTarget: true,
          boundedDuration: true,
          supportsExternalInitialVelocity: true,
          snapBehavior: NaturalSyncSnapBehavior.none,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => group.add(
        snapMismatch,
        naturalPhysicsProfile: const NaturalSyncPhysicsProfile(
          settleDuration: Duration(milliseconds: 80),
          curve: Curves.easeOutCubic,
          convergesToTarget: true,
          boundedDuration: true,
          supportsExternalInitialVelocity: false,
          snapBehavior: NaturalSyncSnapBehavior.memberPhysics,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => group.add(
        settleMismatch,
        naturalPhysicsProfile: const NaturalSyncPhysicsProfile(
          settleDuration: Duration(milliseconds: 181),
          curve: Curves.easeOutCubic,
          convergesToTarget: true,
          boundedDuration: true,
          supportsExternalInitialVelocity: false,
          snapBehavior: NaturalSyncSnapBehavior.none,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('strict mode rejects natural member profiles', () {
    final ScrollSyncGroup group = ScrollSyncGroup.progress();
    final SeekoController controller = SeekoController();
    addTearDown(() {
      group.dispose();
      controller.dispose();
    });

    expect(
      () => group.add(
        controller,
        naturalPhysicsProfile: _boundedNaturalProfile,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  testWidgets('user drag immediately takes over a natural follower', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    group.add(left, id: 'left', naturalPhysicsProfile: _boundedNaturalProfile);
    group.add(
      right,
      id: 'right',
      naturalPhysicsProfile: _boundedNaturalProfile,
    );
    await tester.pumpWidget(
      _twoLists(left: left, right: right, leftCount: 100, rightCount: 220),
    );

    left.jumpTo(left.position.maxScrollExtent * 0.75);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final double beforeTakeover = right.offset;

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('sync-right'))),
    );
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(group.activeLeaderId, 'right');
    expect(right.offset, lessThan(beforeTakeover));
    expect(
      left.offset / left.position.maxScrollExtent,
      closeTo(right.offset / right.position.maxScrollExtent, 0.01),
    );

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('natural follower safely detaches and catches up on reattach', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    group.add(left, id: 'left', naturalPhysicsProfile: _boundedNaturalProfile);
    group.add(
      right,
      id: 'right',
      naturalPhysicsProfile: _boundedNaturalProfile,
    );
    var showRight = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return Row(
              children: <Widget>[
                Expanded(
                  child: ListView.builder(
                    key: const Key('natural-detach-left'),
                    controller: left,
                    itemExtent: 40,
                    itemCount: 100,
                    itemBuilder: (_, int index) => Text('L$index'),
                  ),
                ),
                if (showRight)
                  Expanded(
                    child: ListView.builder(
                      key: const Key('natural-detach-right'),
                      controller: right,
                      itemExtent: 40,
                      itemCount: 220,
                      itemBuilder: (_, int index) => Text('R$index'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    left.jumpTo(left.position.maxScrollExtent * 0.75);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    rebuild(() => showRight = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(right.hasClients, isFalse);
    expect(tester.takeException(), isNull);

    rebuild(() => showRight = true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();

    expect(right.hasClients, isTrue);
    expect(
      right.offset / right.position.maxScrollExtent,
      closeTo(0.75, 1e-9),
    );

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('natural progress uses logical axes for horizontal reverse RTL', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress(
      mode: ScrollSyncMode.natural,
    );
    group.add(left, id: 'left', naturalPhysicsProfile: _boundedNaturalProfile);
    group.add(
      right,
      id: 'right',
      naturalPhysicsProfile: _boundedNaturalProfile,
    );
    await tester.pumpWidget(
      _twoLists(
        left: left,
        right: right,
        leftCount: 100,
        rightCount: 220,
        scrollDirection: Axis.horizontal,
        reverse: true,
        textDirection: TextDirection.rtl,
      ),
    );

    left.jumpTo(left.position.maxScrollExtent * 0.6);
    await tester.pump();
    final double expectedProgress = left.state.value.progress!;
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      right.state.value.progress,
      isNot(closeTo(expectedProgress, 1e-9)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(left.state.value.progress, closeTo(expectedProgress, 1e-9));
    expect(right.state.value.progress, closeTo(expectedProgress, 1e-9));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  test('non-invertible custom mapping rejects bidirectional members', () {
    final ScrollSyncMapping mapping = ScrollSyncMapping.custom(
      memberToGroup: (SyncMetrics member, double? origin) => member.pixels,
      groupToMember: (
        double coordinate,
        SyncMetrics member,
        double? origin,
      ) =>
          coordinate,
      isInvertible: false,
    );
    final ScrollSyncGroup group = ScrollSyncGroup(mapping: mapping);
    final SeekoController rejected = SeekoController();
    final SeekoController leader = SeekoController();
    final SeekoController follower = SeekoController();

    expect(
      () => group.add(rejected),
      throwsA(isA<StateError>()),
    );
    expect(
      () => group.add(leader, role: ScrollSyncRole.leaderOnly),
      returnsNormally,
    );
    expect(
      () => group.add(follower, role: ScrollSyncRole.followerOnly),
      returnsNormally,
    );

    group.dispose();
    rejected.dispose();
    leader.dispose();
    follower.dispose();
  });

  testWidgets('roles prevent followers from leading and leaders from following',
      (
    WidgetTester tester,
  ) async {
    final SeekoController leader = SeekoController();
    final SeekoController follower = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    group.add(leader, id: 'leader', role: ScrollSyncRole.leaderOnly);
    group.add(follower, id: 'follower', role: ScrollSyncRole.followerOnly);
    await tester.pumpWidget(_twoLists(left: leader, right: follower));

    leader.jumpTo(400);
    await tester.pump();
    expect(follower.offset, closeTo(400, 0.5));

    follower.jumpTo(650);
    await tester.pump();
    expect(leader.offset, closeTo(400, 0.5));
    expect(follower.offset, closeTo(650, 0.5));

    group.dispose();
    leader.dispose();
    follower.dispose();
  });

  testWidgets('delta group preserves member transaction baselines', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController(initialScrollOffset: 100);
    final SeekoController right = SeekoController(initialScrollOffset: 500);
    final ScrollSyncGroup group = ScrollSyncGroup.delta();
    group.add(left, id: 'left');
    group.add(right, id: 'right');
    await tester.pumpWidget(_twoLists(left: left, right: right));

    left.jumpTo(240);
    await tester.pump();
    expect(right.offset, closeTo(640, 0.5));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('removal stops propagation without disposing controllers', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    group.add(left, id: 'left');
    final ScrollSyncMember rightMember = group.add(right, id: 'right');
    await tester.pumpWidget(_twoLists(left: left, right: right));

    rightMember.remove();
    left.jumpTo(500);
    await tester.pump();
    expect(right.offset, 0);
    expect(group.memberCount, 1);
    expect(left.hasClients, isTrue);
    expect(right.hasClients, isTrue);

    group.dispose();
    left.dispose();
    right.dispose();
  });

  test('one controller cannot join two active groups', () {
    final SeekoController controller = SeekoController();
    final ScrollSyncGroup first = ScrollSyncGroup.pixels();
    final ScrollSyncGroup second = ScrollSyncGroup.progress();
    first.add(controller, id: 'member');

    expect(
      () => second.add(controller, id: 'other'),
      throwsA(isA<StateError>()),
    );

    first.dispose();
    second.dispose();
    controller.dispose();
  });

  testWidgets('temporarily muted member keeps its position until reactivated', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    group.add(left, id: 'left');
    final ScrollSyncMember rightMember = group.add(right, id: 'right');
    await tester.pumpWidget(_twoLists(left: left, right: right));

    rightMember.participation = ScrollSyncParticipation.temporarilyMuted;
    left.jumpTo(300);
    await tester.pump();
    expect(right.offset, 0);

    rightMember.participation = ScrollSyncParticipation.active;
    await tester.pump();
    expect(right.offset, closeTo(300, 0.5));

    group.dispose();
    left.dispose();
    right.dispose();
  });

  testWidgets('strict propagation stays exact for 2 4 and 8 visible views', (
    WidgetTester tester,
  ) async {
    for (final int count in <int>[2, 4, 8]) {
      final List<SeekoController> controllers = List<SeekoController>.generate(
        count,
        (_) => SeekoController(),
      );
      final ScrollSyncGroup group = ScrollSyncGroup.progress();
      for (var index = 0; index < count; index += 1) {
        group.add(controllers[index], id: index);
      }
      await tester.pumpWidget(_manyVisibleLists(controllers));
      final int appliesBefore = group.followerApplyCount;

      controllers.first.jumpTo(
        controllers.first.position.maxScrollExtent * 0.625,
      );
      await tester.pump();

      expect(group.activeMemberCount, count);
      expect(group.followerApplyCount - appliesBefore, count - 1);
      for (final SeekoController controller in controllers.skip(1)) {
        expect(
          controller.offset / controller.position.maxScrollExtent,
          closeTo(0.625, 1e-9),
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      group.dispose();
      for (final SeekoController controller in controllers) {
        controller.dispose();
      }
    }
  });

  testWidgets('128 attached members propagate only to 8 active views', (
    WidgetTester tester,
  ) async {
    final List<SeekoController> controllers = List<SeekoController>.generate(
      128,
      (_) => SeekoController(),
    );
    final ScrollSyncGroup group = ScrollSyncGroup.pixels();
    final List<ScrollSyncMember> members = <ScrollSyncMember>[];
    for (var index = 0; index < controllers.length; index += 1) {
      final ScrollSyncMember member = group.add(controllers[index], id: index);
      if (index >= 8) {
        member.participation = ScrollSyncParticipation.offstage;
      }
      members.add(member);
    }
    await tester.pumpWidget(_attachedCapacityLists(controllers));
    await tester.pump();
    final int appliesBefore = group.followerApplyCount;

    controllers.first.jumpTo(240);
    await tester.pump();

    expect(group.memberCount, 128);
    expect(group.activeMemberCount, 8);
    expect(group.followerApplyCount - appliesBefore, 7);
    for (var index = 1; index < 8; index += 1) {
      expect(controllers[index].offset, closeTo(240, 0.5));
    }
    for (var index = 8; index < controllers.length; index += 1) {
      expect(controllers[index].offset, 0);
      expect(members[index].isAttached, isTrue);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    for (final SeekoController controller in controllers) {
      controller.dispose();
    }
  });
}

ScrollSemanticAnchor _semanticAnchorWithKey(
  ScrollSemanticAnchor anchor,
  Object key,
) {
  return ScrollSemanticAnchor(
    key: key,
    index: null,
    itemAnchor: anchor.itemAnchor,
    viewportAnchor: anchor.viewportAnchor,
    logicalOffset: anchor.logicalOffset,
  );
}

final class _CountingTickerProvider implements TickerProvider {
  int createdTickerCount = 0;

  @override
  Ticker createTicker(TickerCallback onTick) {
    createdTickerCount += 1;
    return Ticker(onTick);
  }
}

final class _NonConvergingCurve extends Curve {
  const _NonConvergingCurve();

  @override
  double transformInternal(double t) => 0;
}

const NaturalSyncPhysicsProfile _boundedNaturalProfile =
    NaturalSyncPhysicsProfile(
  settleDuration: Duration(milliseconds: 80),
  curve: Curves.easeOutCubic,
  convergesToTarget: true,
  boundedDuration: true,
  supportsExternalInitialVelocity: false,
  snapBehavior: NaturalSyncSnapBehavior.none,
);

Widget _twoLists({
  required SeekoController left,
  required SeekoController right,
  int leftCount = 120,
  int rightCount = 120,
  Axis scrollDirection = Axis.vertical,
  bool reverse = false,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              key: const Key('sync-left'),
              controller: left,
              scrollDirection: scrollDirection,
              reverse: reverse,
              itemExtent: 40,
              itemCount: leftCount,
              itemBuilder: (_, int index) => Text('L$index'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('sync-right'),
              controller: right,
              scrollDirection: scrollDirection,
              reverse: reverse,
              itemExtent: 40,
              itemCount: rightCount,
              itemBuilder: (_, int index) => Text('R$index'),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _manyVisibleLists(List<SeekoController> controllers) {
  return MaterialApp(
    home: Row(
      children: List<Widget>.generate(
        controllers.length,
        (int listIndex) => Expanded(
          child: ListView.builder(
            controller: controllers[listIndex],
            itemExtent: 24,
            itemCount: 100,
            itemBuilder: (_, int itemIndex) => Text('$listIndex:$itemIndex'),
          ),
        ),
      ),
    ),
  );
}

Widget _attachedCapacityLists(List<SeekoController> controllers) {
  return MaterialApp(
    home: Stack(
      children: List<Widget>.generate(controllers.length, (int index) {
        final Widget list = SizedBox(
          width: 80,
          height: 160,
          child: ListView.builder(
            controller: controllers[index],
            itemExtent: 20,
            itemCount: 50,
            itemBuilder: (_, int itemIndex) => Text('$index:$itemIndex'),
          ),
        );
        if (index >= 8) {
          return Offstage(child: list);
        }
        return Positioned(left: index * 80, top: 0, child: list);
      }),
    ),
  );
}

Widget _twoVariableLists({
  required SeekoController left,
  required SeekoController right,
}) {
  return MaterialApp(
    home: Row(
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            key: const Key('variable-left'),
            controller: left,
            itemCount: 72,
            itemBuilder: (_, int index) => SizedBox(
              height: 58.0 + (index % 4) * 11,
              child: Text('L$index'),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: right,
            itemCount: 41,
            itemBuilder: (_, int index) => SizedBox(
              height: 96.0 + (index % 5) * 17,
              child: Text('R$index'),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _twoIndexedLists({
  required SeekoController left,
  required SeekoController right,
  required SeekoIndexDelegate<int> leftDelegate,
  required SeekoIndexDelegate<int> rightDelegate,
}) {
  return MaterialApp(
    home: Row(
      children: <Widget>[
        Expanded(
          child: CustomScrollView(
            controller: left,
            slivers: <Widget>[
              SeekoIndexedSliver(
                controller: left,
                indexDelegate: leftDelegate,
                estimatedExtent: 40,
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) => SizedBox(
                    height: 40,
                    child: Text('L${leftDelegate.keyAt(index)}'),
                  ),
                  childCount: leftDelegate.itemCount,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            controller: right,
            slivers: <Widget>[
              SeekoIndexedSliver(
                controller: right,
                indexDelegate: rightDelegate,
                estimatedExtent: 64,
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) => SizedBox(
                    height: 56.0 + (index % 3) * 8,
                    child: Text('R${rightDelegate.keyAt(index)}'),
                  ),
                  childCount: rightDelegate.itemCount,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
