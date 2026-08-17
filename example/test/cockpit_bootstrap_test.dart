import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:seeko_example/app.dart';

import '../cockpit/cockpit_bootstrap.dart';

void main() {
  test('Cockpit configuration starts from the production initial route', () {
    final FlutterCockpitApp app =
        buildCockpitDevelopmentApp() as FlutterCockpitApp;

    expect(app.config.initialRouteName, SeekoRoutes.targetNavigation);
  });

  testWidgets('Cockpit development wrapper builds without framework errors', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(buildCockpitDevelopmentApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MaterialApp), findsOneWidget);
    semantics.dispose();
  });
}
