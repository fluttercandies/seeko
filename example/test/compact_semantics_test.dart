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
    SeekoRoutes.twoDimensionalSync,
    SeekoRoutes.openTimeline,
    SeekoRoutes.pageCarousel,
    SeekoRoutes.pageSync,
    SeekoRoutes.treeTable,
    SeekoRoutes.grid,
    SeekoRoutes.advancedDrivers,
    SeekoRoutes.diagnosticsLab,
  ];

  for (final String route in routes) {
    testWidgets('$route is layout and semantics clean at 800x600', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(SeekoExampleApp(initialRoute: route));
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      semantics.dispose();
    });
  }
}
