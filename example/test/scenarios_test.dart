import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_example/app.dart';

void main() {
  const List<String> sectionLabels = <String>[
    'Popular',
    'Breakfast',
    'Noodles',
    'Rice Bowls',
    'Drinks',
    'Desserts',
  ];

  int headersNearViewportStart(WidgetTester tester, Finder scrollable) {
    final Rect viewport = tester.getRect(scrollable);
    var count = 0;
    for (final String label in sectionLabels) {
      final Finder header = find.descendant(
        of: scrollable,
        matching: find.text(label),
      );
      if (header.evaluate().isEmpty) {
        continue;
      }
      final Rect rect = tester.getRect(header.first);
      if (rect.bottom > viewport.top && rect.top < viewport.top + 320) {
        count += 1;
      }
    }
    return count;
  }

  int selectedSectionIndex(WidgetTester tester) {
    final Finder selected = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Text && (widget.data?.startsWith('Selected: ') ?? false),
    );
    final String value = tester.widget<Text>(selected).data!;
    return sectionLabels.indexOf(value.substring('Selected: '.length));
  }

  Future<void> pumpRoute(
    WidgetTester tester,
    String route, {
    Size size = const Size(1280, 820),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SeekoExampleApp(initialRoute: route));
    await tester.pumpAndSettle();
  }

  testWidgets('progress sync keeps differently sized native lists aligned', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.progressSync);

    expect(find.byKey(const Key('progress-sync-page')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('progress-sync-left')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final Text left = tester.widget<Text>(
      find.byKey(const Key('progress-left-value')),
    );
    final Text right = tester.widget<Text>(
      find.byKey(const Key('progress-right-value')),
    );
    expect(left.data, right.data);
    expect(left.data, isNot('0.0%'));
  });

  testWidgets('progress sync settles after a long drag without drift', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.progressSync);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('progress-sync-left'))),
    );
    for (var index = 0; index < 120; index += 1) {
      await gesture.moveBy(const Offset(0, -18));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();

    final List<String?> rightValues = <String?>[];
    for (var index = 0; index < 120; index += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      rightValues.add(
        tester.widget<Text>(find.byKey(const Key('progress-right-value'))).data,
      );
    }
    final Text left = tester.widget<Text>(
      find.byKey(const Key('progress-left-value')),
    );
    final Text right = tester.widget<Text>(
      find.byKey(const Key('progress-right-value')),
    );
    expect(rightValues.skip(20).toSet(), hasLength(1));
    expect(right.data, left.data);
  });

  testWidgets('vertical category rail drives content and follows user scroll', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.verticalCategories);

    expect(
      find.byKey(const Key('vertical-category-sync-page')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('vertical-category-desserts')));
    await tester.pumpAndSettle();
    expect(find.text('Selected: Desserts'), findsOneWidget);
    expect(
      headersNearViewportStart(
        tester,
        find.byKey(const Key('vertical-category-content')),
      ),
      lessThanOrEqualTo(2),
    );

    await tester.drag(
      find.byKey(const Key('vertical-category-content')),
      const Offset(0, 650),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selected: Desserts'), findsNothing);
  });

  testWidgets('horizontal tabs drive content and auto-scroll active tab', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.horizontalSections);

    expect(
      find.byKey(const Key('horizontal-section-tabs-page')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('horizontal-section-desserts')));
    await tester.pumpAndSettle();

    expect(find.text('Selected: Desserts'), findsOneWidget);
    expect(
      headersNearViewportStart(
        tester,
        find.byKey(const Key('horizontal-section-content')),
      ),
      lessThanOrEqualTo(2),
    );
    expect(
      tester.getCenter(find.byKey(const Key('horizontal-section-desserts'))).dx,
      inInclusiveRange(0, 1280),
    );

    await tester.drag(
      find.byKey(const Key('horizontal-section-content')),
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selected: Desserts'), findsNothing);
  });

  testWidgets('pinned section targets support backward navigation', (
    WidgetTester tester,
  ) async {
    for (final (String route, Key destination, Key contentKey)
        in <(String, Key, Key)>[
          (
            SeekoRoutes.verticalCategories,
            const Key('vertical-category-popular'),
            const Key('vertical-category-content'),
          ),
          (
            SeekoRoutes.horizontalSections,
            const Key('horizontal-section-popular'),
            const Key('horizontal-section-content'),
          ),
        ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpRoute(tester, route);

      final Key trailingDestination = route == SeekoRoutes.verticalCategories
          ? const Key('vertical-category-desserts')
          : const Key('horizontal-section-desserts');
      await tester.tap(find.byKey(trailingDestination));
      await tester.pumpAndSettle();
      expect(find.text('Selected: Desserts'), findsOneWidget, reason: route);

      await tester.tap(find.byKey(destination));
      await tester.pumpAndSettle();

      expect(find.text('Selected: Popular'), findsOneWidget, reason: route);
      expect(find.text('layoutUnstable'), findsNothing, reason: route);
      final Rect viewport = tester.getRect(find.byKey(contentKey));
      final Rect header = tester.getRect(
        find
            .descendant(
              of: find.byKey(contentKey),
              matching: find.text('Popular'),
            )
            .first,
      );
      expect(
        header.top,
        inInclusiveRange(viewport.top, viewport.top + 56),
        reason: route,
      );
    }
  });

  testWidgets('scenario routes retain their public route names', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, SeekoRoutes.verticalCategories);

    expect(
      ModalRoute.of(
        tester.element(find.byKey(const Key('vertical-category-sync-page'))),
      )!.settings.name,
      SeekoRoutes.verticalCategories,
    );
  });

  testWidgets('section selection stays monotonic during forward scrolling', (
    WidgetTester tester,
  ) async {
    for (final (String route, Key contentKey) in <(String, Key)>[
      (SeekoRoutes.verticalCategories, const Key('vertical-category-content')),
      (SeekoRoutes.horizontalSections, const Key('horizontal-section-content')),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpRoute(tester, route);
      final Finder content = find.byKey(contentKey);
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(content),
      );
      final List<int> transitions = <int>[selectedSectionIndex(tester)];

      for (var step = 0; step < 56; step += 1) {
        await gesture.moveBy(const Offset(0, -48));
        await tester.pump(const Duration(milliseconds: 16));
        final int current = selectedSectionIndex(tester);
        if (current != transitions.last) {
          transitions.add(current);
        }
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(transitions.length, greaterThan(2), reason: route);
      for (var index = 1; index < transitions.length; index += 1) {
        expect(
          transitions[index],
          greaterThanOrEqualTo(transitions[index - 1]),
          reason: '$route changed backward: $transitions',
        );
      }
    }
  });
}
