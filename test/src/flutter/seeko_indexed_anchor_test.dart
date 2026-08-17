import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('atomic insertion retains sparse offscreen measurements', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(1000, (int index) => index);
    final _AtomicIntIndexDelegate indexDelegate =
        _AtomicIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: items[index] == 50 ? 120 : 48,
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      final int index =
                          items.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        50,
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 30,
    );
    await tester.pump();

    rebuild(() {
      items.insertAll(0, List<int>.generate(10, (int index) => -index - 1));
      indexDelegate.publish(
        SeekoChangeSet(
          beforeRevision: 0,
          afterRevision: 1,
          changes: <SeekoChange>[
            SeekoChange.insert(index: 0, count: 10),
          ],
        ),
      );
    });
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        900,
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 30,
    );

    expect(result.isSuccess, isTrue);
    expect(controller.offset, closeTo(910 * 48 + 72, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('head insertion preserves the first visible stable key', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(100, (int index) => index);
    final _MutableIntIndexDelegate indexDelegate =
        _MutableIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: 48,
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      final int value = (key as ValueKey<int>).value;
                      final int index = items.indexOf(value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key(50),
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 30,
    );
    await tester.pump();
    final double leadingBefore = tester.getTopLeft(find.text('Item 50')).dy;
    final double pixelsBefore = controller.offset;

    rebuild(() {
      items.insertAll(0, List<int>.generate(10, (int index) => -index - 1));
      indexDelegate.publishRevision();
    });
    await tester.pump();

    expect(find.text('Item 50'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Item 50')).dy,
        closeTo(leadingBefore, 0.5));
    expect(controller.offset, closeTo(pixelsBefore + 10 * 48, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('no anchor policy preserves numeric pixels after insertion', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(100, (int index) => index);
    final _MutableIntIndexDelegate indexDelegate =
        _MutableIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  anchorPolicy: const AnchorPolicy.none(),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: 48,
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      final int index =
                          items.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToKey(50, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    final double pixelsBefore = controller.offset;

    rebuild(() {
      items.insertAll(0, List<int>.generate(10, (int index) => -index - 1));
      indexDelegate.publishRevision();
    });
    await tester.pump();

    expect(controller.offset, closeTo(pixelsBefore, 0.5));
    expect(controller.state.value.firstVisibleTarget?.key, 40);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('explicit offscreen anchor preserves its offset until deleted', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(120, (int index) => index);
    final _MutableIntIndexDelegate indexDelegate =
        _MutableIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  anchorPolicy: AnchorPolicy.explicitKey(80),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: 48,
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      final int index =
                          items.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToKey(50, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    final double pixelsBefore = controller.offset;

    rebuild(() {
      items.insertAll(0, List<int>.generate(10, (int index) => -index - 1));
      indexDelegate.publishRevision();
    });
    await tester.pump();

    expect(controller.offset, closeTo(pixelsBefore + 10 * 48, 0.5));

    final double beforeDeletion = controller.offset;
    rebuild(() {
      items.remove(80);
      indexDelegate.publishRevision();
    });
    await tester.pump();

    expect(controller.offset, closeTo(beforeDeletion, 0.5));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('nearest policy selects the next stable item after deletion', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(100, (int index) => index);
    final _MutableIntIndexDelegate indexDelegate =
        _MutableIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  anchorPolicy: const AnchorPolicy.nearest(),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: 48,
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      final int index =
                          items.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToKey(50, placement: const ScrollPlacement.start()),
    );
    await tester.pump();

    rebuild(() {
      items.remove(50);
      indexDelegate.publishRevision();
    });
    await tester.pump();

    expect(controller.state.value.firstVisibleTarget?.key, 51);
    expect(tester.getTopLeft(find.text('Item 51')).dy, closeTo(0, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('atomic remove move and update retain measured extents', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(200, (int index) => index);
    final Map<int, double> extents = <int, double>{50: 120};
    final _AtomicIntIndexDelegate indexDelegate =
        _AtomicIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: extents[items[index]] ?? 48,
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      final int index =
                          items.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToKey(50, placement: const ScrollPlacement.start()),
    );
    await tester.pump();

    rebuild(() {
      items.removeRange(0, 10);
      indexDelegate.publish(
        SeekoChangeSet(
          beforeRevision: 0,
          afterRevision: 1,
          changes: <SeekoChange>[
            SeekoChange.remove(index: 0, count: 10),
          ],
        ),
      );
    });
    await tester.pump();

    final int movedFrom = items.indexOf(50);
    rebuild(() {
      final int moved = items.removeAt(movedFrom);
      items.insert(100, moved);
      indexDelegate.publish(
        SeekoChangeSet(
          beforeRevision: 1,
          afterRevision: 2,
          changes: <SeekoChange>[
            SeekoChange.move(from: movedFrom, to: 100, count: 1),
          ],
        ),
      );
    });
    await tester.pump();

    await pumpScrollCommand(
      tester,
      controller.jumpToKey(50, placement: const ScrollPlacement.start()),
    );
    await tester.pump();
    rebuild(() {
      extents[50] = 200;
      indexDelegate.publish(
        SeekoChangeSet(
          beforeRevision: 2,
          afterRevision: 3,
          changes: <SeekoChange>[
            SeekoChange.update(index: 100, count: 1),
          ],
        ),
      );
    });
    await tester.pump();

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(150, placement: const ScrollPlacement.start()),
    );

    expect(result.isSuccess, isTrue);
    expect(controller.offset, closeTo(140 * 48 + 152, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('extent growth before the anchor is corrected pre-paint', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(100, (int index) => index);
    final List<double> extents = List<double>.filled(100, 48);
    final _MutableIntIndexDelegate indexDelegate =
        _MutableIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: extents[index],
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) =>
                        items.indexOf((key as ValueKey<int>).value),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key(50),
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 30,
    );
    await tester.pump();
    final double pixelsBefore = controller.offset;

    rebuild(() {
      extents[49] = 96;
    });
    await tester.pump();

    expect(tester.getTopLeft(find.text('Item 50')).dy, closeTo(0, 0.5));
    expect(controller.offset, closeTo(pixelsBefore + 48, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });

  testWidgets('trailing policy follows only while the user remains near end', (
    WidgetTester tester,
  ) async {
    final List<int> items = List<int>.generate(30, (int index) => index);
    final _MutableIntIndexDelegate indexDelegate =
        _MutableIntIndexDelegate(items);
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  anchorPolicy: AnchorPolicy.trailingEdge(),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      key: ValueKey<int>(items[index]),
                      height: 48,
                      child: Text('Item ${items[index]}'),
                    ),
                    childCount: items.length,
                    findChildIndexCallback: (Key key) {
                      final int index =
                          items.indexOf((key as ValueKey<int>).value);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await pumpScrollCommand(
      tester,
      controller.jumpToTarget(const ScrollTarget.edge(ScrollEdge.trailing)),
      maxFrames: 30,
    );
    await tester.pump();

    rebuild(() {
      items.addAll(List<int>.generate(5, (int index) => 30 + index));
      indexDelegate.publishRevision();
    });
    await tester.pump();
    expect(controller.state.value.atTrailingEdge, isTrue);
    expect(find.text('Item 34'), findsOneWidget);

    controller.jumpTo(controller.offset - 240);
    await tester.pump();
    final ScrollVisibleTarget anchor =
        controller.state.value.firstVisibleTarget!;
    final double anchorLeading = anchor.leadingPixels;
    final int anchorKey = anchor.key! as int;

    rebuild(() {
      items.addAll(List<int>.generate(5, (int index) => 35 + index));
      indexDelegate.publishRevision();
    });
    await tester.pump();

    expect(controller.state.value.atTrailingEdge, isFalse);
    final ScrollVisibleTarget preserved = controller.state.value.visibleTargets
        .firstWhere((ScrollVisibleTarget target) => target.key == anchorKey);
    expect(preserved.leadingPixels, closeTo(anchorLeading, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    indexDelegate.dispose();
  });
}

final class _AtomicIntIndexDelegate implements SeekoIndexDelegate<Object> {
  _AtomicIntIndexDelegate(this.items);

  final List<int> items;
  final SeekoChangeNotifier _changes = SeekoChangeNotifier();

  @override
  Listenable get changes => _changes;

  @override
  int get itemCount => items.length;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, items.length)]);

  @override
  int get revision => _changes.revision;

  @override
  SeekoKeyLookup<Object> captureIndex(int index) =>
      index < 0 || index >= items.length
          ? const SeekoKeyLookup<Object>.absent()
          : SeekoKeyLookup<Object>.found(index, key: items[index]);

  @override
  Object keyAt(int index) => items[index];

  @override
  SeekoKeyLookup<Object> lookupKey(Object key) {
    if (key is! int) {
      return const SeekoKeyLookup<Object>.absent();
    }
    final int index = items.indexOf(key);
    return index < 0
        ? const SeekoKeyLookup<Object>.absent()
        : SeekoKeyLookup<Object>.found(index);
  }

  void publish(SeekoChangeSet changeSet) => _changes.publish(changeSet);

  void dispose() => _changes.dispose();
}

final class _MutableIntIndexDelegate implements SeekoIndexDelegate<Object> {
  _MutableIntIndexDelegate(this.items);

  final List<int> items;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  @override
  Listenable get changes => _revision;

  @override
  int get itemCount => items.length;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, items.length)]);

  @override
  int get revision => _revision.value;

  @override
  SeekoKeyLookup<Object> captureIndex(int index) =>
      index < 0 || index >= items.length
          ? const SeekoKeyLookup<Object>.absent()
          : SeekoKeyLookup<Object>.found(index, key: items[index]);

  @override
  Object keyAt(int index) => items[index];

  @override
  SeekoKeyLookup<Object> lookupKey(Object key) {
    if (key is! int) {
      return const SeekoKeyLookup<Object>.absent();
    }
    final int index = items.indexOf(key);
    return index < 0
        ? const SeekoKeyLookup<Object>.absent()
        : SeekoKeyLookup<Object>.found(index);
  }

  void publishRevision() {
    _revision.value += 1;
  }

  void dispose() {
    _revision.dispose();
  }
}
