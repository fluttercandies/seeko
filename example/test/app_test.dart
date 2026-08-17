import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_example/app.dart';

void main() {
  Future<void> pumpExample(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SeekoExampleApp());
    await tester.pumpAndSettle();
  }

  Future<void> revealCommandControl(WidgetTester tester, Key key) async {
    final Finder scrollable = find
        .descendant(
          of: find.byKey(const Key('command-rail')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(key),
      240,
      scrollable: scrollable,
    );
  }

  testWidgets(
    'opens the stable target navigation route in a responsive shell',
    (WidgetTester tester) async {
      await pumpExample(tester);

      expect(find.byKey(const Key('catalog-navigation')), findsOneWidget);
      expect(find.text('Target Navigation'), findsWidgets);
      expect(find.text('Native scroll workspace'), findsOneWidget);
      expect(find.byKey(const Key('target-navigation-list')), findsOneWidget);
      expect(find.byType(ListView), findsWidgets);
      expect(
        ModalRoute.of(
          tester.element(find.text('Native scroll workspace')),
        )!.settings.name,
        SeekoRoutes.targetNavigation,
      );
    },
  );

  testWidgets('renders the Synced S Rails brand mark in the app shell', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester);

    final Finder mark = find.byKey(const Key('seeko-brand-mark'));
    expect(mark, findsOneWidget);
    expect(
      find.descendant(of: mark, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
  });

  testWidgets('runs L1 pixel jump and exposes a typed command result', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester);

    await tester.enterText(find.byKey(const Key('pixel-target-field')), '640');
    await tester.tap(find.byKey(const Key('jump-pixels-button')));
    await tester.pumpAndSettle();

    expect(find.text('completed'), findsOneWidget);
    expect(find.textContaining('ScrollTarget.offset(640.0)'), findsOneWidget);
    expect(find.textContaining('640.0 px'), findsWidgets);
  });

  testWidgets('runs an exact mounted L2 key command', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester);

    await tester.enterText(find.byKey(const Key('item-target-field')), '6');
    await tester.tap(find.byKey(const Key('jump-item-button')));
    await tester.pumpAndSettle();

    expect(find.text('completed'), findsOneWidget);
    expect(find.text('exact'), findsOneWidget);
    expect(find.textContaining('item-6'), findsWidgets);
  });

  testWidgets('reset restores the leading edge and clears the last result', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester);

    await tester.enterText(find.byKey(const Key('pixel-target-field')), '720');
    await tester.tap(find.byKey(const Key('jump-pixels-button')));
    await tester.pumpAndSettle();
    expect(find.text('completed'), findsOneWidget);

    await revealCommandControl(tester, const Key('reset-scenario-button'));
    await tester.tap(find.byKey(const Key('reset-scenario-button')));
    await tester.pumpAndSettle();

    expect(find.text('No command yet'), findsOneWidget);
    expect(find.textContaining('0.0 px'), findsWidgets);
  });

  testWidgets('reverse and RTL controls rebuild the native scrollable', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester);

    await revealCommandControl(tester, const Key('reverse-toggle'));
    await tester.tap(find.byKey(const Key('reverse-toggle')));
    await tester.pumpAndSettle();
    ListView list = tester.widget<ListView>(
      find.byKey(const Key('target-navigation-list')),
    );
    expect(list.reverse, isTrue);

    await revealCommandControl(tester, const Key('rtl-toggle'));
    await tester.tap(find.byKey(const Key('rtl-toggle')));
    await tester.pumpAndSettle();
    list = tester.widget<ListView>(
      find.byKey(const Key('target-navigation-list')),
    );
    expect(
      Directionality.of(tester.element(find.byWidget(list))),
      TextDirection.rtl,
    );
  });

  testWidgets('command controls expose tooltips and semantic labels', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester);

    expect(find.byTooltip('Jump to pixel offset'), findsOneWidget);
    expect(find.byTooltip('Animate to pixel offset'), findsOneWidget);
    expect(find.byTooltip('Jump to mounted item'), findsOneWidget);
    expect(find.byTooltip('Animate to mounted item'), findsOneWidget);

    final SemanticsHandle semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('jump-item-button'))).label,
      contains('Jump to mounted item'),
    );
    semantics.dispose();
  });

  testWidgets('narrow layout keeps the working surface operable', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester, size: const Size(430, 900));

    expect(find.byKey(const Key('open-scenario-controls')), findsOneWidget);
    expect(find.byKey(const Key('target-navigation-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact controls panel preserves the workspace at 800x600', (
    WidgetTester tester,
  ) async {
    await pumpExample(tester, size: const Size(800, 600));

    await tester.tap(find.byKey(const Key('open-scenario-controls')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('command-rail')), findsOneWidget);
    expect(find.byKey(const Key('close-scenario-controls')), findsOneWidget);
    expect(find.byKey(const Key('target-navigation-list')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('command-rail'))).height,
      greaterThan(0),
    );

    await tester.tap(find.byKey(const Key('close-scenario-controls')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('command-rail')), findsNothing);
    expect(find.byKey(const Key('target-navigation-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
