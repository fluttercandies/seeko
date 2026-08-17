import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_example/app.dart';

void main() {
  const List<String> routes = <String>[
    SeekoRoutes.targetNavigation,
    SeekoRoutes.progressSync,
    SeekoRoutes.verticalCategories,
    SeekoRoutes.horizontalSections,
    SeekoRoutes.multiViewSync,
    SeekoRoutes.naturalMotion,
    SeekoRoutes.complexSlivers,
    SeekoRoutes.obstructionForms,
    SeekoRoutes.twoDimensional,
    SeekoRoutes.openTimeline,
    SeekoRoutes.pageCarousel,
    SeekoRoutes.treeTable,
  ];

  Future<void> pumpRoute(
    WidgetTester tester,
    String route, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SeekoExampleApp(initialRoute: route));
    await tester.pumpAndSettle();
  }

  for (final String route in routes) {
    testWidgets('$route uses the shared scenario header', (
      WidgetTester tester,
    ) async {
      await pumpRoute(tester, route, size: const Size(1280, 820));

      expect(find.byKey(const Key('scenario-header')), findsOneWidget);
      expect(find.byKey(const Key('catalog-sidebar')), findsOneWidget);
    });
  }

  testWidgets('compact catalog uses a calm top bar and keeps the workspace', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      SeekoRoutes.naturalMotion,
      size: const Size(800, 600),
    );

    expect(find.byKey(const Key('catalog-top-bar')), findsOneWidget);
    expect(find.byKey(const Key('scenario-header')), findsOneWidget);
    expect(find.byKey(const Key('natural-motion-list')), findsOneWidget);
  });
}
