import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';
import 'package:seeko_example/app.dart';

void main() {
  Future<void> pumpRoute(WidgetTester tester, String route) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SeekoExampleApp(initialRoute: route));
    await tester.pumpAndSettle();
  }

  testWidgets('two-dimensional route runs a typed cell jump', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.twoDimensional);

    await tester.tap(find.byKey(const Key('two-dimensional-jump')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('two-dimensional-result'))).data,
      'completed',
    );
    final Rect viewport = tester.getRect(
      find.byKey(const Key('two-dimensional-vertical')),
    );
    final Rect target = tester.getRect(find.byKey(const Key('cell-18-9')));
    expect(target.overlaps(viewport), isTrue);
  });

  testWidgets(
    'open timeline appends and navigates through the public adapter',
    (WidgetTester tester) async {
      await pumpRoute(tester, SeekoRoutes.openTimeline);

      await tester.tap(find.byKey(const Key('open-timeline-load-after')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('open-timeline-result'))).data,
        anyOf('completed', 'clamped'),
      );
      expect(find.byKey(const ValueKey<String>('event-35')), findsOneWidget);
    },
  );

  testWidgets('carousel composes a page jump with an item reveal', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.pageCarousel);

    await tester.tap(find.byKey(const Key('page-carousel-jump')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('page-carousel-result'))).data,
      'completed',
    );
    expect(find.byKey(const ValueKey<String>('page-2-item-5')), findsOneWidget);
  });

  testWidgets(
    'tree table seeks by stable cell key and handles keyboard input',
    (WidgetTester tester) async {
      await pumpRoute(tester, SeekoRoutes.treeTable);

      await tester.tap(find.byKey(const Key('tree-table-seek')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('tree-table-result'))).data,
        'completed',
      );
      expect(
        find.byKey(
          const ValueKey<SeekoTableCellKey<String, String>>(
            SeekoTableCellKey<String, String>('node-5-5', 'owner'),
          ),
        ),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Cell R0 C1'), findsOneWidget);
    },
  );
}
