import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  final List<({Axis axis, bool reverse, TextDirection textDirection})> cases =
      <({Axis axis, bool reverse, TextDirection textDirection})>[
    (axis: Axis.vertical, reverse: false, textDirection: TextDirection.ltr),
    (axis: Axis.vertical, reverse: true, textDirection: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: false, textDirection: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: true, textDirection: TextDirection.ltr),
    (axis: Axis.horizontal, reverse: false, textDirection: TextDirection.rtl),
    (axis: Axis.horizontal, reverse: true, textDirection: TextDirection.rtl),
  ];

  for (final config in cases) {
    testWidgets(
      'initial target is at logical leading edge for ${config.axis.name} '
      'reverse=${config.reverse} ${config.textDirection.name}',
      (WidgetTester tester) async {
        final ValueNotifier<int> revision = ValueNotifier<int>(0);
        final ListSeekoIndexDelegate<int> indexDelegate =
            ListSeekoIndexDelegate<int>(
          itemCount: 10000,
          revision: revision,
          keyAt: (int index) => index,
          indexOfKey: (int key) => key,
        );
        final SeekoController controller = SeekoController(
          indexDelegate: indexDelegate,
          initialTarget: ScrollTarget.key(9000),
          initialPlacement: const ScrollPlacement.start(),
        );
        const Key viewportKey = ValueKey<String>('viewport');

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: config.textDirection,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  height: 240,
                  child: CustomScrollView(
                    key: viewportKey,
                    controller: controller,
                    scrollDirection: config.axis,
                    reverse: config.reverse,
                    slivers: <Widget>[
                      SeekoIndexedSliver(
                        controller: controller,
                        indexDelegate: indexDelegate,
                        estimatedExtent: 48,
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) => SizedBox(
                            key: ValueKey<int>(index),
                            width: config.axis == Axis.horizontal ? 48 : null,
                            height: config.axis == Axis.vertical ? 48 : null,
                            child: Text('Item $index'),
                          ),
                          childCount: 10000,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final Finder target = find.byKey(const ValueKey<int>(9000));
        expect(target, findsOneWidget);
        expect(find.byKey(const ValueKey<int>(0)), findsNothing);
        final Rect targetRect = tester.getRect(target);
        final Rect viewportRect = tester.getRect(find.byKey(viewportKey));
        final bool physicalLeadingAtStart = config.axis == Axis.vertical
            ? !config.reverse
            : config.reverse == (config.textDirection == TextDirection.rtl);
        final double targetLeading = config.axis == Axis.vertical
            ? (physicalLeadingAtStart ? targetRect.top : targetRect.bottom)
            : (physicalLeadingAtStart ? targetRect.left : targetRect.right);
        final double viewportLeading = config.axis == Axis.vertical
            ? (physicalLeadingAtStart ? viewportRect.top : viewportRect.bottom)
            : (physicalLeadingAtStart ? viewportRect.left : viewportRect.right);
        expect(targetLeading, closeTo(viewportLeading, 0.5));

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        revision.dispose();
      },
    );

    testWidgets(
      'far animation reaches target for ${config.axis.name} '
      'reverse=${config.reverse} ${config.textDirection.name}',
      (WidgetTester tester) async {
        final ValueNotifier<int> revision = ValueNotifier<int>(0);
        final ListSeekoIndexDelegate<int> indexDelegate =
            ListSeekoIndexDelegate<int>(
          itemCount: 10000,
          revision: revision,
          keyAt: (int index) => index,
          indexOfKey: (int key) => key,
        );
        final SeekoController controller = SeekoController(
          indexDelegate: indexDelegate,
        );
        var childBuilds = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: config.textDirection,
              child: CustomScrollView(
                controller: controller,
                scrollDirection: config.axis,
                reverse: config.reverse,
                slivers: <Widget>[
                  SeekoIndexedSliver(
                    controller: controller,
                    indexDelegate: indexDelegate,
                    estimatedExtent: 48,
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) {
                        childBuilds += 1;
                        return SizedBox(
                          key: ValueKey<int>(index),
                          width: config.axis == Axis.horizontal ? 48 : null,
                          height: config.axis == Axis.vertical ? 48 : null,
                          child: Text('Item $index'),
                        );
                      },
                      childCount: 10000,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final int buildsBeforeAnimation = childBuilds;
        final Future<ScrollResult> future = controller.animateToTarget(
          ScrollTarget.index(9000),
          placement: const ScrollPlacement.start(),
          motion: const ScrollMotion.duration(
            duration: Duration(milliseconds: 240),
            curve: Curves.easeInOutCubic,
          ),
        );
        for (var frame = 0; frame < 20; frame += 1) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final ScrollResult result = await pumpScrollCommand(
          tester,
          future,
          maxFrames: 15,
        );

        expect(result.isSuccess, isTrue);
        expect(result.finalError, lessThanOrEqualTo(0.5));
        expect(find.byKey(const ValueKey<int>(9000)), findsOneWidget);
        expect(childBuilds - buildsBeforeAnimation, lessThan(150));

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        revision.dispose();
      },
    );
  }
}
