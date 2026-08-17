import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import 'support/scroll_command_tester.dart';

void main() {
  test('public library keeps the frozen direct export surface', () {
    final String source = File('lib/seeko.dart').readAsStringSync();
    final List<String> exports = RegExp(
      r"^export '([^']+)';$",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();

    expect(exports, <String>[
      'src/core/anchor_policy.dart',
      'src/core/capability.dart',
      'src/core/command_model.dart',
      'src/core/driver.dart',
      'src/core/index_delegate.dart',
      'src/core/logical_geometry.dart',
      'src/core/motion.dart',
      'src/core/open_data.dart',
      'src/core/restoration.dart',
      'src/core/scroll_placement.dart',
      'src/core/scroll_target.dart',
      'src/core/sync_mapping.dart',
      'src/core/target_loader.dart',
      'src/flutter/seeko_controller.dart',
      'src/flutter/seeko_diagnostics.dart',
      'src/flutter/seeko_focus.dart',
      'src/flutter/seeko_open_scroll_adapter.dart',
      'src/flutter/seeko_page_adapter.dart',
      'src/flutter/seeko_prefetch.dart',
      'src/flutter/seeko_restoration.dart',
      'src/flutter/seeko_section_coordinator.dart',
      'src/flutter/seeko_snap.dart',
      'src/flutter/seeko_snapshot.dart',
      'src/flutter/seeko_table.dart',
      'src/flutter/seeko_tag.dart',
      'src/flutter/seeko_two_dimensional.dart',
      'src/flutter/seeko_two_dimensional_sync.dart',
    ]);
  });

  testWidgets('L1 remains a direct ScrollController replacement', (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemExtent: 48,
          itemBuilder: (BuildContext context, int index) => Text('Item $index'),
        ),
      ),
    );

    controller.jumpTo(240);
    await tester.pump();
    expect(controller.offset, 240);

    final Future<ScrollResult> command = controller.animateToTarget(
      ScrollTarget.offset(480),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect((await command).isSuccess, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('L2 adds only a tag around the target child', (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: <Widget>[
            const SizedBox(height: 600),
            SeekoTag(
              controller: controller,
              targetKey: 'details',
              child: const SizedBox(height: 80, child: Text('Details')),
            ),
            const SizedBox(height: 600),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.key('details'),
        placement: const ScrollPlacement.start(),
      ),
    );
    expect(result.isSuccess, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('L3 replaces only the native sliver primitive', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) =>
                    SizedBox(height: 48, child: Text('Item $index')),
                childCount: 1000000,
              ),
            ),
          ],
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(900000),
      maxFrames: 30,
    );
    expect(result.isSuccess, isTrue);
    expect(find.text('Item 900000'), findsOneWidget);

    final ScrollResult keyJump = await pumpScrollCommand(
      tester,
      controller.jumpToKey(800000),
      maxFrames: 30,
    );
    expect(
      keyJump.isSuccess,
      isTrue,
      reason: 'outcome=${keyJump.outcome} error=${keyJump.finalError} '
          'pixels=${keyJump.finalLogicalPixels} '
          'diagnostics=${keyJump.diagnostics}',
    );
    expect(
      (await pumpScrollCommand(
        tester,
        controller.animateToIndex(
          700000,
          motion: const ScrollMotion.instant(),
        ),
        maxFrames: 30,
      ))
          .isSuccess,
      isTrue,
    );
    expect(
      (await pumpScrollCommand(
        tester,
        controller.animateToKey(
          600000,
          motion: const ScrollMotion.instant(),
        ),
        maxFrames: 30,
      ))
          .isSuccess,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('sync remains two controllers plus one group', (
    WidgetTester tester,
  ) async {
    final SeekoController left = SeekoController();
    final SeekoController right = SeekoController();
    final ScrollSyncGroup group = ScrollSyncGroup.progress()
      ..add(left)
      ..add(right);
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(child: _contractList(left, 80)),
            Expanded(child: _contractList(right, 160)),
          ],
        ),
      ),
    );

    left.jumpTo(480);
    await tester.pump();
    expect(right.offset, greaterThan(480));

    await tester.pumpWidget(const SizedBox.shrink());
    group.dispose();
    left.dispose();
    right.dispose();
  });
}

Widget _contractList(SeekoController controller, int itemCount) {
  return ListView.builder(
    controller: controller,
    itemCount: itemCount,
    itemExtent: 48,
    itemBuilder: (BuildContext context, int index) => Text('Item $index'),
  );
}
