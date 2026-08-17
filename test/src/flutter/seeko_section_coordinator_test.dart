import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  test('section coordinate validates progress and domain revision', () {
    expect(
      () => SeekoSectionCoordinate<String>(
        section: 'A',
        progress: double.nan,
        domainRevision: 0,
        domainIndex: 0,
      ),
      throwsRangeError,
    );
    expect(
      () => SeekoSectionCoordinate<String>(
        section: 'A',
        progress: 1.1,
        domainRevision: 0,
        domainIndex: 0,
      ),
      throwsRangeError,
    );
    expect(
      () => SeekoSectionCoordinate<String>(
        section: 'A',
        progress: 0,
        domainRevision: -1,
        domainIndex: 0,
      ),
      throwsRangeError,
    );
  });

  test('section domain copies input and rejects duplicate identifiers', () {
    final List<String> sections = <String>['A', 'B'];
    final SeekoSectionDomain<String> domain =
        SeekoSectionDomain<String>.fixed(sections);
    sections.add('C');
    expect(domain.sections, <String>['A', 'B']);
    expect(
      () => SeekoSectionDomain<String>.fixed(<String>['A', 'A']),
      throwsArgumentError,
    );
    domain.dispose();
  });

  testWidgets('visible content updates selection and reveals navigation item', (
    WidgetTester tester,
  ) async {
    final SeekoController navigation = SeekoController();
    final SeekoController content = SeekoController();
    final SeekoSectionCoordinator<String> coordinator =
        SeekoSectionCoordinator<String>.tagged(
      contentController: content,
      navigationController: navigation,
      initialSection: 'A',
    );
    await tester.pumpWidget(
      _sectionFixture(navigation: navigation, content: content),
    );

    content.jumpTo(520);
    await tester.pumpAndSettle();

    expect(coordinator.selectedSection.value, 'C');
    expect(navigation.offset, greaterThan(0));

    coordinator.dispose();
    navigation.dispose();
    content.dispose();
  });

  testWidgets('select performs one typed section command', (
    WidgetTester tester,
  ) async {
    final SeekoController navigation = SeekoController();
    final SeekoController content = SeekoController();
    final SeekoSectionCoordinator<String> coordinator =
        SeekoSectionCoordinator<String>.tagged(
      contentController: content,
      navigationController: navigation,
      initialSection: 'A',
    );
    await tester.pumpWidget(
      _sectionFixture(navigation: navigation, content: content),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      coordinator.select('D', animated: false),
    );
    await tester.pumpAndSettle();

    expect(result.isSuccess, isTrue);
    expect(
        result.requestedTarget, ScrollTarget.key(SeekoSectionKey.header('D')));
    expect(coordinator.selectedSection.value, 'D');
    expect(content.offset, closeTo(720, 0.5));

    coordinator.dispose();
    navigation.dispose();
    content.dispose();
  });

  testWidgets('programmatic section selection stays pinned to its destination',
      (
    WidgetTester tester,
  ) async {
    final SeekoController navigation = SeekoController();
    final SeekoController content = SeekoController();
    final SeekoSectionCoordinator<String> coordinator =
        SeekoSectionCoordinator<String>.tagged(
      contentController: content,
      navigationController: navigation,
      initialSection: 'A',
    );
    await tester.pumpWidget(
      _sectionFixture(navigation: navigation, content: content),
    );

    final Future<ScrollResult> command = coordinator.select('F');
    ScrollResult? result;
    var completed = false;
    unawaited(
      command.then((ScrollResult value) {
        result = value;
        completed = true;
      }),
    );
    await tester.pump();
    for (var frame = 0; frame < 90 && !completed; frame += 1) {
      expect(coordinator.selectedSection.value, 'F', reason: 'frame $frame');
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(completed, isTrue);
    expect(result!.isSuccess, isTrue);
    expect(coordinator.selectedSection.value, 'F');

    coordinator.dispose();
    navigation.dispose();
    content.dispose();
  });

  testWidgets('trailing boundary selects the final visible section', (
    WidgetTester tester,
  ) async {
    final SeekoController navigation = SeekoController();
    final SeekoController content = SeekoController();
    final SeekoSectionCoordinator<String> coordinator =
        SeekoSectionCoordinator<String>.tagged(
      contentController: content,
      navigationController: navigation,
      initialSection: 'A',
    );
    await tester.pumpWidget(
      _sectionFixture(navigation: navigation, content: content),
    );

    await pumpScrollCommand(
      tester,
      coordinator.select('F', animated: false),
    );
    await tester.pumpAndSettle();

    expect(content.position.atEdge, isTrue);
    expect(coordinator.selectedSection.value, 'F');

    coordinator.dispose();
    navigation.dispose();
    content.dispose();
  });

  testWidgets('missing section keeps typed target-not-loaded semantics', (
    WidgetTester tester,
  ) async {
    final SeekoController content = SeekoController();
    final SeekoSectionCoordinator<String> coordinator =
        SeekoSectionCoordinator<String>.tagged(
      contentController: content,
      initialSection: 'A',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: SingleChildScrollView(
            controller: content,
            child: SeekoTag(
              controller: content,
              targetKey: SeekoSectionKey.header('A'),
              child: const SizedBox(height: 800),
            ),
          ),
        ),
      ),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      coordinator.select('missing', animated: false),
    );

    expect(result.outcome, ScrollOutcome.targetNotLoaded);

    coordinator.dispose();
    content.dispose();
  });

  testWidgets('disposing coordinator preserves caller controller ownership', (
    WidgetTester tester,
  ) async {
    final SeekoController content = SeekoController();
    final SeekoSectionCoordinator<String> coordinator =
        SeekoSectionCoordinator<String>.tagged(
      contentController: content,
      initialSection: 'A',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(controller: content, children: const <Widget>[]),
      ),
    );

    coordinator.dispose();
    content.jumpTo(0);
    expect(content.hasClients, isTrue);

    content.dispose();
  });
}

Widget _sectionFixture({
  required SeekoController navigation,
  required SeekoController content,
}) {
  const List<String> sections = <String>['A', 'B', 'C', 'D', 'E', 'F'];
  return MaterialApp(
    home: Row(
      children: <Widget>[
        SizedBox(
          width: 100,
          height: 120,
          child: SingleChildScrollView(
            controller: navigation,
            child: Column(
              children: <Widget>[
                for (final String section in sections)
                  SeekoTag(
                    controller: navigation,
                    targetKey: section,
                    child: SizedBox(height: 50, child: Text(section)),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 300,
          height: 250,
          child: SingleChildScrollView(
            controller: content,
            child: Column(
              children: <Widget>[
                for (final String section in sections) ...<Widget>[
                  SeekoTag(
                    controller: content,
                    targetKey: SeekoSectionKey.header(section),
                    child:
                        SizedBox(height: 40, child: Text('Section $section')),
                  ),
                  for (var index = 0; index < 4; index++)
                    SeekoTag(
                      controller: content,
                      targetKey: SeekoSectionKey.item(section, index),
                      child: SizedBox(
                        height: 50,
                        child: Text('$section item $index'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
