import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('focus reveal waits for keyboard obstruction before scrolling', (
    WidgetTester tester,
  ) async {
    final FocusNode focusNode = FocusNode();
    final ValueNotifier<double> keyboardInset = ValueNotifier<double>(0);
    final SeekoController controller = SeekoController(
      obstructionResolver: (ScrollViewportGeometry viewport) {
        return VisibleRegion.fromIntervals(<LogicalInterval>[
          LogicalInterval(
            40,
            viewport.viewportExtent - keyboardInset.value,
          ),
        ]);
      },
    );
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        keyboardInset.value = 80;
      }
    });
    const Key viewportKey = ValueKey<String>('focus-viewport');
    const Key fieldKey = ValueKey<String>('focus-field');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              height: 240,
              child: SingleChildScrollView(
                key: viewportKey,
                controller: controller,
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 800),
                    SizedBox(
                      key: fieldKey,
                      height: 60,
                      child: TextFormField(focusNode: focusNode),
                    ),
                    const SizedBox(height: 800),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.ensureFocusVisible(
        focusNode,
        requestFocus: true,
      ),
      maxFrames: 20,
    );

    final Rect viewport = tester.getRect(find.byKey(viewportKey));
    final Rect field = tester.getRect(find.byKey(fieldKey));
    expect(result.outcome, ScrollOutcome.completed);
    expect(focusNode.hasPrimaryFocus, isTrue);
    expect(field.top, greaterThanOrEqualTo(viewport.top + 40 - 0.5));
    expect(field.bottom, lessThanOrEqualTo(viewport.top + 160 + 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focusNode.dispose();
    keyboardInset.dispose();
  });

  testWidgets('focus reveal materializes an unmounted indexed field first', (
    WidgetTester tester,
  ) async {
    final FocusNode focusNode = FocusNode();
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final SeekoIndexDelegate<int> indexDelegate = ListSeekoIndexDelegate<int>(
      itemCount: 1000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 60,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SizedBox(
                      height: 60,
                      child: index == 500
                          ? TextFormField(focusNode: focusNode)
                          : Text('Item $index'),
                    ),
                    childCount: 1000,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(focusNode.context, isNull);

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.ensureFocusVisible(
        focusNode,
        requestFocus: true,
        fallbackTarget: ScrollTarget.index(500),
      ),
      maxFrames: 30,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(focusNode.hasPrimaryFocus, isTrue);
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focusNode.dispose();
    revision.dispose();
  });

  testWidgets('form helper focuses and reveals the first invalid target', (
    WidgetTester tester,
  ) async {
    final FocusNode first = FocusNode();
    final FocusNode second = FocusNode();
    final SeekoController controller = SeekoController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: <Widget>[
                  SizedBox(height: 60, child: TextFormField(focusNode: first)),
                  const SizedBox(height: 600),
                  SizedBox(
                    height: 60,
                    child: TextFormField(focusNode: second),
                  ),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final ScrollResult? result = await pumpScrollCommand(
      tester,
      controller.ensureFirstFormErrorVisible(<SeekoFormFocusTarget>[
        SeekoFormFocusTarget(focusNode: first, hasError: () => false),
        SeekoFormFocusTarget(focusNode: second, hasError: () => true),
      ]),
      maxFrames: 20,
    );

    expect(result?.outcome, ScrollOutcome.completed);
    expect(first.hasFocus, isFalse);
    expect(second.hasPrimaryFocus, isTrue);
    expect(controller.offset, greaterThan(400));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    first.dispose();
    second.dispose();
  });
}
