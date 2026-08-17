import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  test('diagnostics validates capacity and disposed mutations', () {
    expect(() => ScrollDiagnostics(capacity: 0), throwsRangeError);
    final ScrollDiagnostics diagnostics = ScrollDiagnostics();
    diagnostics.dispose();
    expect(diagnostics.clear, throwsStateError);
    expect(
      () => diagnostics.attachController(SeekoController()),
      throwsStateError,
    );
  });

  testWidgets('recorder bounds controller, raw, command, and group evidence', (
    WidgetTester tester,
  ) async {
    final SeekoController primary = SeekoController(
      debugLabel: 'primary',
    );
    final SeekoController follower = SeekoController(
      debugLabel: 'follower',
    );
    final ScrollSyncGroup group = ScrollSyncGroup.progress()
      ..add(primary, id: 'primary')
      ..add(follower, id: 'follower');
    final ScrollDiagnostics diagnostics = ScrollDiagnostics(capacity: 16);
    var notifications = 0;
    diagnostics.addListener(() => notifications += 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(child: _list(primary, 'primary')),
            Expanded(child: _list(follower, 'follower')),
          ],
        ),
      ),
    );
    diagnostics.attachController(
      primary,
      label: 'primary-list',
      includeRawEvents: true,
    );
    diagnostics.attachController(follower);
    diagnostics.attachSyncGroup(group, label: 'linked-lists');
    expect(
      () => diagnostics.attachController(primary),
      throwsStateError,
    );
    expect(() => diagnostics.attachSyncGroup(group), throwsStateError);

    primary.jumpTo(120);
    await tester.pump();
    final ScrollResult result = await pumpScrollCommand(
      tester,
      primary.jumpToTarget(ScrollTarget.offset(240)),
    );
    expect(result.outcome, ScrollOutcome.completed);
    await tester.pump();

    expect(diagnostics.events.length, lessThanOrEqualTo(16));
    expect(diagnostics.latest, isNotNull);
    expect(
      diagnostics.events.map((ScrollDiagnosticEvent event) => event.kind),
      containsAll(<ScrollDiagnosticEventKind>[
        ScrollDiagnosticEventKind.snapshot,
        ScrollDiagnosticEventKind.rawPosition,
        ScrollDiagnosticEventKind.commandResult,
        ScrollDiagnosticEventKind.syncGroup,
      ]),
    );
    expect(
      diagnostics.events
          .where((ScrollDiagnosticEvent event) => event.commandResult != null)
          .single
          .commandResult,
      result,
    );
    final List<Map<String, Object?>> exported = diagnostics.export();
    expect(exported, hasLength(diagnostics.events.length));
    expect(exported.last['sequence'], diagnostics.latest!.sequence);
    expect(exported.last['timestamp'], isA<String>());
    expect(notifications, greaterThan(0));

    diagnostics.detachController(primary);
    diagnostics.detachController(primary);
    diagnostics.detachSyncGroup(group);
    diagnostics.detachSyncGroup(group);
    diagnostics.clear();
    await tester.pump();
    expect(diagnostics.events, isEmpty);
    diagnostics.clear();

    await tester.pumpWidget(const SizedBox.shrink());
    diagnostics.dispose();
    group.dispose();
    primary.dispose();
    follower.dispose();
  });

  testWidgets('overlay exposes bounded live diagnostics without input capture',
      (
    WidgetTester tester,
  ) async {
    final SeekoController controller = SeekoController();
    final ScrollDiagnostics diagnostics = ScrollDiagnostics()
      ..attachController(controller, label: 'overlay-list');

    await tester.pumpWidget(
      MaterialApp(
        home: SeekoDiagnosticsOverlay(
          diagnostics: diagnostics,
          child: ListView(
            controller: controller,
            children: <Widget>[
              SeekoTag(
                controller: controller,
                targetKey: 'visible-target',
                index: 0,
                child: const SizedBox(height: 120),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Seeko diagnostics'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is IgnorePointer && widget.ignoring,
      ),
      findsOneWidget,
    );

    controller.jumpTo(80);
    await tester.pump();
    expect(find.textContaining('overlay-list'), findsOneWidget);
    expect(find.textContaining('viewport'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: SeekoDiagnosticsOverlay(
          diagnostics: diagnostics,
          enabled: false,
          child: const Text('content-only'),
        ),
      ),
    );
    expect(find.text('content-only'), findsOneWidget);
    expect(find.text('Seeko diagnostics'), findsNothing);

    diagnostics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

Widget _list(SeekoController controller, String prefix) {
  return ListView.builder(
    controller: controller,
    itemCount: 100,
    itemExtent: 48,
    itemBuilder: (BuildContext context, int index) => Text('$prefix-$index'),
  );
}
