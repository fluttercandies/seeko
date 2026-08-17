import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('prefetch configuration validates bounded sampling values', () {
    expect(
      () => ScrollPrefetchConfiguration(
        horizon: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => ScrollPrefetchConfiguration(
        minimumVelocity: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => ScrollPrefetchConfiguration(
        maxLookaheadViewports: 0,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('prefetch hint reports logical velocity direction and ETA', (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController();
    final ScrollPrefetchObserver observer = ScrollPrefetchObserver(
      controller,
      configuration: ScrollPrefetchConfiguration(
        horizon: const Duration(milliseconds: 120),
        sampleInterval: const Duration(milliseconds: 16),
        minimumVelocity: 1,
        maxLookaheadViewports: 3,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: ListView.builder(
            controller: controller,
            itemExtent: 50,
            itemCount: 200,
            itemBuilder: (_, int index) => SeekoTag(
              controller: controller,
              targetKey: index,
              index: index,
              child: Text('Item $index'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    controller.jumpTo(100);
    await tester.pump(const Duration(milliseconds: 16));
    controller.jumpTo(200);
    await tester.pump(const Duration(milliseconds: 16));

    final ScrollPrefetchHint hint = observer.value!;
    expect(hint.direction, ScrollPrefetchDirection.trailing);
    expect(hint.logicalVelocity, greaterThan(0));
    expect(hint.projectedLogicalPixels, greaterThan(hint.logicalPixels));
    expect(hint.projectedViewport.start, hint.projectedLogicalPixels);
    expect(hint.sweptRegion.start, hint.logicalPixels);
    expect(hint.estimatedArrivalTo(500), isNotNull);
    expect(hint.estimatedArrivalTo(100), isNull);
    expect(hint.trailingVisibleTarget?.index, isNotNull);

    final ScrollPrefetchHint beforeDispose = hint;
    observer.dispose();
    controller.jumpTo(300);
    await tester.pump(const Duration(milliseconds: 32));
    expect(observer.value, beforeDispose);

    controller.dispose();
  });
}
