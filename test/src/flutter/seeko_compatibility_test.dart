import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('typed jump preserves Flutter scroll notification order',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final List<ScrollNotification> notifications = <ScrollNotification>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            notifications.add(notification);
            return false;
          },
          child: ListView.builder(
            controller: controller,
            itemExtent: 50,
            itemCount: 100,
            itemBuilder: (_, int index) => Text('$index'),
          ),
        ),
      ),
    );
    notifications.clear();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.offset(120)),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(
      notifications.map((ScrollNotification value) => value.runtimeType),
      <Type>[
        ScrollStartNotification,
        ScrollUpdateNotification,
        ScrollEndNotification,
      ],
    );
    expect(
      notifications.map((ScrollNotification value) => value.depth),
      everyElement(0),
    );
    expect(controller.offset, closeTo(120, 0.5));
    controller.dispose();
  });

  testWidgets('native GridView supports the shared pixel command pipeline',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: GridView.builder(
          controller: controller,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 100,
          ),
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.progress(0.5)),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent * 0.5, 0.5),
    );
    controller.dispose();
  });

  testWidgets('native GridView reveals a mounted SeekoTag target',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: GridView.builder(
          controller: controller,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 100,
          ),
          itemCount: 100,
          itemBuilder: (_, int index) => SeekoTag(
            controller: controller,
            targetKey: 'item-$index',
            index: index,
            child: Text('$index'),
          ),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('item-8'),
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(400, 0.5));
    controller.dispose();
  });

  testWidgets(
      'native CustomScrollView supports the shared pixel command pipeline',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SliverList.builder(
              itemCount: 100,
              itemBuilder: (_, int index) =>
                  SizedBox(height: 50, child: Text('$index')),
            ),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        const ScrollTarget.edge(ScrollEdge.trailing),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(
        controller.offset, closeTo(controller.position.maxScrollExtent, 0.5));
    controller.dispose();
  });

  testWidgets('native CustomScrollView reveals a mounted SeekoTag target',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SliverList.builder(
              itemCount: 100,
              itemBuilder: (_, int index) => SeekoTag(
                controller: controller,
                targetKey: 'item-$index',
                index: index,
                child: SizedBox(height: 50, child: Text('$index')),
              ),
            ),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('item-8'),
        placement: const ScrollPlacement.start(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(400, 0.5));
    controller.dispose();
  });

  testWidgets('nested typed jump preserves Flutter notification depth',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final List<ScrollNotification> notifications = <ScrollNotification>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification.metrics.maxScrollExtent > 1000) {
              notifications.add(notification);
            }
            return false;
          },
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: 50,
                    itemCount: 100,
                    itemBuilder: (_, int index) => Text('$index'),
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    notifications.clear();

    await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.offset(120)),
    );

    expect(notifications, isNotEmpty);
    expect(
      notifications.map((ScrollNotification value) => value.depth),
      everyElement(1),
    );
    controller.dispose();
  });

  testWidgets('RefreshIndicator still receives native user overscroll',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RefreshIndicator(
          onRefresh: () async {
            refreshCount += 1;
          },
          child: ListView.builder(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            itemExtent: 100,
            itemCount: 20,
            itemBuilder: (_, int index) => Text('$index'),
          ),
        ),
      ),
    );
    controller.jumpTo(200);
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(const ScrollTarget.edge(ScrollEdge.leading)),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(refreshCount, 0);

    await tester.fling(find.text('0'), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(refreshCount, 1);
    controller.dispose();
  });

  testWidgets('Scrollbar interaction interrupts a typed animation',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: RawScrollbar(
          controller: controller,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 4000),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Future<ScrollResult> result = controller.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tapAt(const Offset(797, 550));
    await tester.pumpAndSettle();

    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    expect(controller.state.value.origin, ScrollEventOrigin.user);
    controller.dispose();
  });

  testWidgets('PrimaryScrollController keeps caller ownership',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: PrimaryScrollController(
          controller: controller,
          child: ListView.builder(
            primary: true,
            itemExtent: 50,
            itemCount: 100,
            itemBuilder: (_, int index) => Text('$index'),
          ),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.offset(120)),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(120, 0.5));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isAttached, isFalse);
    controller.dispose();
  });

  testWidgets('disableAnimations converts typed animation to an instant move',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final List<ScrollNotification> notifications = <ScrollNotification>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                notifications.add(notification);
                return false;
              },
              child: ListView.builder(
                controller: controller,
                itemExtent: 50,
                itemCount: 100,
                itemBuilder: (_, int index) => Text('$index'),
              ),
            ),
          ),
        ),
      ),
    );
    notifications.clear();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.animateToTarget(
        ScrollTarget.offset(1000),
        motion: const ScrollMotion.duration(
          duration: Duration(seconds: 1),
          curve: Curves.linear,
        ),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(1000, 0.5));
    expect(
      notifications.map((ScrollNotification value) => value.runtimeType),
      <Type>[
        ScrollStartNotification,
        ScrollUpdateNotification,
        ScrollEndNotification,
      ],
    );
    controller.dispose();
  });

  testWidgets('TabBarView keepAlive retains one attached position',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: const TabBar(
              tabs: <Widget>[Tab(text: 'Feed'), Tab(text: 'Other')],
            ),
            body: TabBarView(
              children: <Widget>[
                _KeepAliveList(controller: controller),
                const SizedBox.expand(),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(ScrollTarget.offset(300)),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(300, 0.5));
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(300, 0.5));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isAttached, isFalse);
    controller.dispose();
  });

  testWidgets('native PageStorage pixels survive detach and reattach',
      (WidgetTester tester) async {
    final PageStorageBucket bucket = PageStorageBucket();
    final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, bool value, __) => value
                ? ListView.builder(
                    key: const PageStorageKey<String>('feed'),
                    controller: controller,
                    itemExtent: 50,
                    itemCount: 100,
                    itemBuilder: (_, int index) => Text('$index'),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    controller.jumpTo(300);
    await tester.pump();

    visible.value = false;
    await tester.pump();
    expect(controller.isAttached, isFalse);
    visible.value = true;
    await tester.pump();

    expect(controller.isAttached, isTrue);
    expect(controller.offset, closeTo(300, 0.5));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    visible.dispose();
  });
}

final class _KeepAliveList extends StatefulWidget {
  const _KeepAliveList({required this.controller});

  final SeekoController controller;

  @override
  State<_KeepAliveList> createState() => _KeepAliveListState();
}

final class _KeepAliveListState extends State<_KeepAliveList>
    with AutomaticKeepAliveClientMixin<_KeepAliveList> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView.builder(
      controller: widget.controller,
      itemExtent: 50,
      itemCount: 100,
      itemBuilder: (_, int index) => Text('$index'),
    );
  }
}
