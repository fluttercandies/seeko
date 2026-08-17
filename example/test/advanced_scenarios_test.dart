import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_example/app.dart';

void main() {
  Future<void> pumpRoute(
    WidgetTester tester,
    String route, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SeekoExampleApp(initialRoute: route));
    await tester.pumpAndSettle();
  }

  testWidgets('multi-view route synchronizes four native lists', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.multiViewSync);

    await tester.tap(find.byKey(const Key('multi-view-count-4')));
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(Key('multi-view-list-$index')), findsOneWidget);
    }

    await tester.drag(
      find.byKey(const Key('multi-view-list-0')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();

    final List<String?> progress = <String?>[
      for (var index = 0; index < 4; index++)
        tester.widget<Text>(find.byKey(Key('multi-view-progress-$index'))).data,
    ];
    expect(progress.toSet(), hasLength(1));
    expect(progress.first, isNot('0.0%'));
  });

  testWidgets('natural motion route completes an adaptive far seek', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.naturalMotion);

    await tester.tap(find.byKey(const Key('natural-motion-far')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('natural-motion-result'))).data,
      'completed',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('natural-motion-details'))).data,
      contains('ms'),
    );
    expect(find.byKey(const Key('natural-motion-target-32')), findsOneWidget);
  });

  testWidgets('complex sliver route targets content across native slivers', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.complexSlivers);

    await tester.tap(find.byKey(const Key('complex-sliver-seek-activity')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('complex-sliver-result'))).data,
      'completed',
    );
    final Rect target = tester.getRect(
      find.byKey(const Key('complex-sliver-target-activity')),
    );
    expect(target.bottom, greaterThan(0));
    expect(target.top, lessThan(900));
  });

  testWidgets('form reveal respects the declared top obstruction', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.obstructionForms);

    await tester.tap(find.byKey(const Key('form-reveal-address')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('form-reveal-result'))).data,
      'completed',
    );
    final double overlayBottom = tester
        .getBottomLeft(find.byKey(const Key('form-obstruction-overlay')))
        .dy;
    final double targetTop = tester
        .getTopLeft(find.byKey(const Key('form-address-target')))
        .dy;
    expect(targetTop, greaterThanOrEqualTo(overlayBottom));
  });
}
