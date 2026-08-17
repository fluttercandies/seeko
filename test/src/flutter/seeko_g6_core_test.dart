import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('open data keeps a stable anchor across prepend', () {
    final SeekoOpenDataController<String> data =
        SeekoOpenDataController<String>();
    data.applyPage(
      SeekoOpenPage<String>(
        items: <SeekoOpenItem<String>>[
          const SeekoOpenItem<String>(
            logicalIndex: 0,
            key: 'zero',
            extent: 20,
          ),
          const SeekoOpenItem<String>(
            logicalIndex: 1,
            key: 'one',
            extent: 20,
          ),
        ],
        hasMoreBefore: true,
        hasMoreAfter: true,
        revision: 1,
      ),
    );
    final SeekoOpenAnchor<String> anchor = data.captureAnchor('one')!;
    final SeekoOpenMutationResult<String> mutation = data.applyPage(
      SeekoOpenPage<String>(
        items: <SeekoOpenItem<String>>[
          const SeekoOpenItem<String>(
            logicalIndex: -2,
            key: 'minus-two',
            extent: 20,
          ),
          const SeekoOpenItem<String>(
            logicalIndex: -1,
            key: 'minus-one',
            extent: 20,
          ),
        ],
        hasMoreBefore: false,
        hasMoreAfter: true,
        revision: 2,
      ),
      preserve: anchor,
    );

    expect(mutation.pixelCorrection, 40);
    expect(data.resolveKey('one').status, SeekoOpenResolutionStatus.resolved);
    expect(data.offsetOf(1), 20);
    expect(data.normalizedProgress, isNull);
  });

  test('open data loads each direction once and rebases in O(log n) lookup',
      () async {
    var calls = 0;
    final SeekoOpenDataController<String> data =
        SeekoOpenDataController<String>(
      source: CallbackSeekoOpenDataSource<String>(
        (SeekoOpenLoadRequest request) {
          calls += 1;
          return SeekoOpenPage<String>(
            items: <SeekoOpenItem<String>>[
              SeekoOpenItem<String>(
                logicalIndex:
                    request.direction == SeekoOpenDirection.before ? -1 : 2,
                key: request.direction == SeekoOpenDirection.before
                    ? 'minus'
                    : 'two',
                extent: 24,
              ),
            ],
            hasMoreBefore: request.direction == SeekoOpenDirection.after,
            hasMoreAfter: request.direction == SeekoOpenDirection.before,
            revision: request.revision + 1,
          );
        },
      ),
    );
    data.applyPage(
      SeekoOpenPage<String>(
        items: <SeekoOpenItem<String>>[
          const SeekoOpenItem<String>(
            logicalIndex: 0,
            key: 'zero',
            extent: 24,
          ),
          const SeekoOpenItem<String>(
            logicalIndex: 1,
            key: 'one',
            extent: 24,
          ),
        ],
        hasMoreBefore: true,
        hasMoreAfter: true,
        revision: 1,
      ),
    );
    await Future.wait<void>(<Future<void>>[
      data.load(SeekoOpenDirection.before).then<void>((_) {}),
      data.load(SeekoOpenDirection.before).then<void>((_) {}),
    ]);
    expect(calls, 1);
    expect(data.rebaseOrigin('one'), 24);
    expect(data.offsetOf(1), 0);
  });

  test('table layout accepts single-use column iterables and resizes columns',
      () {
    Iterable<SeekoTableColumn<String>> columns() sync* {
      yield const SeekoTableColumn<String>(key: 'name', width: 100);
      yield const SeekoTableColumn<String>(key: 'value', width: 80);
    }

    final List<String> rows = <String>['a', 'b', 'c'];
    final SeekoTableLayout<String, String> layout =
        SeekoTableLayout<String, String>(
      rowCount: rows.length,
      columns: columns(),
      rowKeyAt: rows.elementAt,
      rowIndexOf: rows.indexOf,
    );
    expect(layout.totalWidth, 180);
    expect(
        layout.coordinateOfKey(
          const SeekoTableCellKey<String, String>('b', 'value'),
        ),
        SeekoCellCoordinate(1, 1));
    expect(layout.resizeColumn('name', 140), 40);
    expect(layout.totalWidth, 220);
    layout.dispose();
  });

  test('tree expansion preserves an anchor and removes hidden descendants', () {
    final Map<String, SeekoTreeNodeDescriptor<String>> nodes =
        <String, SeekoTreeNodeDescriptor<String>>{
      'root': const SeekoTreeNodeDescriptor<String>(
        key: 'root',
        children: <String>['child'],
      ),
      'child': const SeekoTreeNodeDescriptor<String>(
        key: 'child',
        children: <String>[],
        extent: 60,
      ),
    };
    final SeekoTreeTableController<String> tree =
        SeekoTreeTableController<String>(
      roots: const <String>['root'],
      resolveNode: (String key) => nodes[key]!,
      initiallyExpanded: const <String>['root'],
    );
    final SeekoTreeAnchor<String> anchor = tree.captureAnchor('child')!;
    final SeekoTreeMutationResult<String> mutation = tree.setExpanded(
      'root',
      false,
      preserve: anchor,
    );
    expect(mutation.anchor!.key, 'root');
    expect(tree.visibleRowCount, 1);
    expect(tree.indexOf('child'), isNull);
  });

  test('table metadata validates boundaries and navigation clamps', () {
    expect(
      () => const SeekoTableColumn<String>(
        key: 'fixed',
        width: 80,
        resizable: false,
      ).withWidth(90),
      returnsNormally,
    );
    expect(
      () => const SeekoTableColumn<String>(
        key: 'bounded',
        width: 80,
        minWidth: 60,
        maxWidth: 100,
      ).withWidth(120),
      throwsArgumentError,
    );
    expect(
      () => SeekoTableLayout<int, String>(
        rowCount: 1,
        columns: const <SeekoTableColumn<String>>[
          SeekoTableColumn<String>(key: 'duplicate', width: 80),
          SeekoTableColumn<String>(key: 'duplicate', width: 90),
        ],
        rowKeyAt: (int row) => row,
        rowIndexOf: (int row) => row,
      ),
      throwsArgumentError,
    );

    final SeekoTableNavigationController navigation =
        SeekoTableNavigationController(rowCount: 5, columnCount: 4);
    expect(
      navigation.move(SeekoTableNavigationIntent.up),
      SeekoCellCoordinate.zero,
    );
    expect(
      navigation.move(SeekoTableNavigationIntent.tableEnd),
      SeekoCellCoordinate(4, 3),
    );
    expect(
      navigation.move(SeekoTableNavigationIntent.pageUp, visibleRows: 3),
      SeekoCellCoordinate(1, 3),
    );
    expect(
      navigation.select(SeekoCellCoordinate(100, 100)),
      SeekoCellCoordinate(4, 3),
    );
    navigation.dispose();
  });

  test('tree metadata rejects visible cycles and duplicate stable keys', () {
    expect(
      () => SeekoTreeTableController<String>(
        roots: const <String>['a'],
        initiallyExpanded: const <String>['a', 'b'],
        resolveNode: (String key) => SeekoTreeNodeDescriptor<String>(
          key: key,
          children: <String>[key == 'a' ? 'b' : 'a'],
        ),
      ),
      throwsStateError,
    );
    expect(
      () => SeekoTreeTableController<String>(
        roots: const <String>['a', 'a'],
        resolveNode: (String key) => SeekoTreeNodeDescriptor<String>(
          key: key,
          children: const <String>[],
        ),
      ),
      throwsStateError,
    );
  });

  test('table bindings release only the layout they installed', () {
    final SeekoTwoDimensionalController controller =
        SeekoTwoDimensionalController();
    final SeekoTableLayout<int, String> layout = SeekoTableLayout<int, String>(
      rowCount: 2,
      columns: const <SeekoTableColumn<String>>[
        SeekoTableColumn<String>(key: 'name', width: 100),
      ],
      rowKeyAt: (int row) => row,
      rowIndexOf: (int row) => row,
    );
    final SeekoTableBinding<int, String> binding =
        SeekoTableBinding<int, String>(controller: controller, layout: layout);
    expect(controller.layout, same(layout));
    binding.dispose();
    expect(controller.layout, isNull);

    final SeekoTreeTableController<int> tree = SeekoTreeTableController<int>(
      roots: const <int>[0],
      resolveNode: (int key) => SeekoTreeNodeDescriptor<int>(
        key: key,
        children: const <int>[],
      ),
    );
    final SeekoTreeTableBinding<int, String> treeBinding =
        SeekoTreeTableBinding<int, String>(
      controller: controller,
      tree: tree,
      columns: const <SeekoTableColumn<String>>[
        SeekoTableColumn<String>(key: 'name', width: 100),
      ],
    );
    expect(controller.layout, same(treeBinding.layout));
    treeBinding.dispose();
    expect(controller.layout, isNull);
    tree.dispose();
    layout.dispose();
    controller.dispose();
  });

  test('detached two-dimensional group commands report detached', () async {
    final SeekoTwoDimensionalSyncGroup group = SeekoTwoDimensionalSyncGroup();
    final SeekoTwoDimensionalGroupResult result =
        await group.jumpToCell(SeekoCellTarget.cell(0, 0));
    expect(result.results, isEmpty);
    expect(result.outcome, ScrollOutcome.detached);
    expect(result.isSuccess, isFalse);
    group.dispose();
  });

  test('two-dimensional detached command and page adapter have typed outcomes',
      () async {
    final SeekoTwoDimensionalController twoDimensional =
        SeekoTwoDimensionalController(
      layout: SeekoFiniteTwoDimensionalLayout.fixed(
        rowCount: 10,
        columnCount: 10,
      ),
      viewportSize: const Size(100, 100),
    );
    final SeekoTwoDimensionalResult twoDimensionalResult =
        await twoDimensional.jumpToCell(SeekoCellTarget.cell(4, 4));
    expect(twoDimensionalResult.outcome, ScrollOutcome.detached);
    twoDimensional.dispose();

    final SeekoPageControllerAdapter pages = SeekoPageControllerAdapter(
      pageController: PageController(),
      itemControllerForPage: (_) => null,
      pageCount: 3,
      ownsPageController: true,
    );
    final SeekoPageItemResult pageResult = await pages.jumpToTarget(
      SeekoPageItemTarget.page(2),
    );
    expect(pageResult.outcome, ScrollOutcome.detached);
    pages.dispose();
  });

  testWidgets(
    'two-dimensional controller reveals a distant cell on both axes',
    (WidgetTester tester) async {
      final ScrollController vertical = ScrollController();
      final ScrollController horizontal = ScrollController();
      final SeekoTwoDimensionalController controller =
          SeekoTwoDimensionalController(
        vertical: vertical,
        horizontal: horizontal,
        layout: SeekoFiniteTwoDimensionalLayout.fixed(
          rowCount: 20,
          columnCount: 20,
          rowExtent: 40,
          columnExtent: 80,
        ),
        viewportSize: const Size(100, 100),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              height: 100,
              child: SingleChildScrollView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1600,
                  height: 100,
                  child: SingleChildScrollView(
                    controller: vertical,
                    child: const SizedBox(width: 1600, height: 800),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final SeekoTwoDimensionalResult result = await controller.jumpToCell(
        SeekoCellTarget.cell(10, 5),
        placement: const SeekoTwoDimensionalPlacement.start(),
      );
      expect(result.outcome, ScrollOutcome.completed);
      expect(vertical.offset, closeTo(400, 0.1));
      expect(horizontal.offset, closeTo(400, 0.1));
      expect(
        controller.state.value.visibleCells.any(
          (SeekoVisibleCell cell) =>
              cell.coordinate == SeekoCellCoordinate(10, 5),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('page adapter resolves an item after the destination page mounts',
      (WidgetTester tester) async {
    final PageController pageController = PageController();
    final List<SeekoController> itemControllers = <SeekoController>[
      SeekoController(),
      SeekoController(),
      SeekoController(),
    ];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PageView.builder(
          controller: pageController,
          itemCount: itemControllers.length,
          itemBuilder: (BuildContext context, int page) {
            return ListView.builder(
              controller: itemControllers[page],
              itemCount: 100,
              itemExtent: 40,
              itemBuilder: (_, int index) => Text('$page:$index'),
            );
          },
        ),
      ),
    );
    final SeekoPageControllerAdapter adapter = SeekoPageControllerAdapter(
      pageController: pageController,
      itemControllerForPage: (int page) => itemControllers[page],
      pageCount: itemControllers.length,
    );
    final Future<SeekoPageItemResult> command = adapter.jumpToTarget(
      SeekoPageItemTarget(
        page: 2,
        item: ScrollTarget.offset(320),
      ),
    );
    SeekoPageItemResult? result;
    final Future<void> completion = command.then<void>(
      (SeekoPageItemResult value) {
        result = value;
      },
    );
    for (var frame = 0; frame < 30 && result == null; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await completion;

    expect(result!.outcome, ScrollOutcome.completed);
    expect(result!.achievedPage, 2);
    expect(pageController.page, closeTo(2, 0.01));
    expect(itemControllers[2].offset, closeTo(320, 0.1));

    adapter.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    pageController.dispose();
    for (final SeekoController controller in itemControllers) {
      controller.dispose();
    }
  });

  testWidgets('page restoration preserves carousel page fraction',
      (WidgetTester tester) async {
    final PageController pageController = PageController(
      viewportFraction: 0.8,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PageView.builder(
          controller: pageController,
          itemCount: 4,
          itemBuilder: (_, int page) => Text('page $page'),
        ),
      ),
    );
    final SeekoPageControllerAdapter adapter = SeekoPageControllerAdapter(
      pageController: pageController,
      itemControllerForPage: (_) => null,
      pageCount: 4,
    );
    final SeekoPageItemResult result = await adapter.restore(
      const SeekoPageRestorationState(page: 1, pageFraction: 0.25),
    );
    await tester.pump();

    expect(result.isSuccess, isTrue);
    expect(pageController.page, closeTo(1.25, 0.01));

    adapter.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    pageController.dispose();
  });

  testWidgets('two-dimensional progress sync maps both axes without feedback',
      (WidgetTester tester) async {
    final ScrollController firstVertical = ScrollController();
    final ScrollController firstHorizontal = ScrollController();
    final ScrollController secondVertical = ScrollController();
    final ScrollController secondHorizontal = ScrollController();
    final SeekoTwoDimensionalController first = SeekoTwoDimensionalController(
      vertical: firstVertical,
      horizontal: firstHorizontal,
      layout: SeekoFiniteTwoDimensionalLayout.fixed(
        rowCount: 20,
        columnCount: 20,
        rowExtent: 40,
        columnExtent: 80,
      ),
      viewportSize: const Size(100, 100),
    );
    final SeekoTwoDimensionalController second = SeekoTwoDimensionalController(
      vertical: secondVertical,
      horizontal: secondHorizontal,
      layout: SeekoFiniteTwoDimensionalLayout.fixed(
        rowCount: 40,
        columnCount: 40,
        rowExtent: 40,
        columnExtent: 80,
      ),
      viewportSize: const Size(100, 100),
    );

    Widget surface({
      required ScrollController vertical,
      required ScrollController horizontal,
      required double width,
      required double height,
    }) {
      return SizedBox(
        width: 100,
        height: 100,
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: 100,
            child: SingleChildScrollView(
              controller: vertical,
              child: SizedBox(width: width, height: height),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              surface(
                vertical: firstVertical,
                horizontal: firstHorizontal,
                width: 1600,
                height: 800,
              ),
              surface(
                vertical: secondVertical,
                horizontal: secondHorizontal,
                width: 3200,
                height: 1600,
              ),
            ],
          ),
        ),
      ),
    );
    final SeekoTwoDimensionalSyncGroup group = SeekoTwoDimensionalSyncGroup();
    group.add(
      first,
      member: const SeekoTwoDimensionalSyncMember(
        role: SeekoTwoDimensionalSyncRole.leader,
      ),
    );
    group.add(
      second,
      member: const SeekoTwoDimensionalSyncMember(
        role: SeekoTwoDimensionalSyncRole.follower,
      ),
    );

    await first.jumpTo(horizontalPixels: 750, verticalPixels: 350);

    expect(secondHorizontal.offset, closeTo(1550, 0.5));
    expect(secondVertical.offset, closeTo(750, 0.5));

    group.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    second.dispose();
    firstVertical.dispose();
    firstHorizontal.dispose();
    secondVertical.dispose();
    secondHorizontal.dispose();
  });
}
