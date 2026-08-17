import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('large shrink-wrapped indexed slivers emit guidance once', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1001,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );

    final List<String> diagnostics = <String>[];
    final void Function(String?, {int? wrapWidth}) previousDebugPrint =
        debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        diagnostics.add(message);
      }
    };
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: SizedBox(
              height: 600,
              child: CustomScrollView(
                controller: controller,
                shrinkWrap: true,
                slivers: <Widget>[
                  SeekoIndexedSliver(
                    controller: controller,
                    indexDelegate: indexDelegate,
                    debugShrinkWrapItemLimit: 1000,
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) =>
                          const SizedBox(height: 48),
                      childCount: 1001,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(tester.takeException(), isNull);
    expect(diagnostics.join('\n'), contains('shrinkWrap'));
    expect(diagnostics.join('\n'), contains('1001'));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('initial indexed target is visible in the first frame', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
      initialTarget: ScrollTarget.key(700000),
      initialPlacement: const ScrollPlacement.start(),
    );
    final Future<SeekoInitialTargetResult> initialResult =
        controller.initialTargetResult!;

    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              estimatedExtent: 48,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => ColoredBox(
                  key: ValueKey<int>(index),
                  color: const Color(0xFF16C79A),
                  child: const SizedBox(height: 48),
                ),
                childCount: 1000000,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(const ValueKey<int>(700000)), findsOneWidget);
    expect(find.byKey(const ValueKey<int>(0)), findsNothing);
    expect(controller.offset, closeTo(700000 * 48, 0.5));
    final SeekoInitialTargetResult result = await initialResult;
    expect(result.outcome, ScrollOutcome.completed);
    expect(result.target, ScrollTarget.key(700000));
    expect(result.dataRevision, 0);
    expect(result.finalLogicalPixels, closeTo(700000 * 48, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('initial indexed center uses measured dynamic extent pre-paint', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
      initialTarget: ScrollTarget.index(700000),
      initialPlacement: const ScrollPlacement.center(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 200,
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => ColoredBox(
                      key: ValueKey<int>(index),
                      color: const Color(0xFF16C79A),
                      child: SizedBox(height: index == 700000 ? 120 : 48),
                    ),
                    childCount: 1000000,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final Finder target = find.byKey(const ValueKey<int>(700000));
    expect(target, findsOneWidget);
    expect(tester.getTopLeft(target).dy, closeTo(40, 0.5));
    expect(controller.offset, closeTo(700000 * 48 - 40, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('out-of-range initial index fails before painting index zero', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 10,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 10 ? key : null,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
      initialTarget: ScrollTarget.index(10),
    );
    final Future<SeekoInitialTargetResult> initialResult =
        controller.initialTargetResult!;

    await tester.pumpWidget(
      _initialFailureHarness(
        controller: controller,
        indexDelegate: indexDelegate,
      ),
    );

    final SeekoInitialTargetResult result = await initialResult;
    expect(result.outcome, ScrollOutcome.targetOutOfRange);
    expect(result.target, ScrollTarget.index(10));
    expect(result.finalLogicalPixels, isNull);
    expect(tester.takeException(), isNull);
    expect(find.text('Item 0'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('missing initial key reports deletion before first paint', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 10,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key >= 0 && key < 10 ? key : null,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
      initialTarget: ScrollTarget.key(99),
    );
    final Future<SeekoInitialTargetResult> initialResult =
        controller.initialTargetResult!;

    await tester.pumpWidget(
      _initialFailureHarness(
        controller: controller,
        indexDelegate: indexDelegate,
      ),
    );

    final SeekoInitialTargetResult result = await initialResult;
    expect(result.outcome, ScrollOutcome.targetDeleted);
    expect(result.target, ScrollTarget.key(99));
    expect(result.finalLogicalPixels, isNull);
    expect(tester.takeException(), isNull);
    expect(find.text('Item 0'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  test('initial target reports detached when disposed before layout', () async {
    final SeekoController controller = SeekoController(
      initialTarget: ScrollTarget.index(4),
    );
    final Future<SeekoInitialTargetResult> initialResult =
        controller.initialTargetResult!;

    controller.dispose();

    final SeekoInitialTargetResult result = await initialResult;
    expect(result.outcome, ScrollOutcome.detached);
    expect(result.target, ScrollTarget.index(4));
    expect(result.dataRevision, isNull);
    expect(result.finalLogicalPixels, isNull);
  });

  testWidgets('far indexed jump builds only the destination window', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    var childBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              estimatedExtent: 48,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  childBuilds += 1;
                  return SizedBox(height: 48, child: Text('Item $index'));
                },
                childCount: 1000000,
              ),
            ),
          ],
        ),
      ),
    );
    final int buildsBeforeJump = childBuilds;

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToTarget(
        ScrollTarget.index(900000),
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 60,
    );
    await tester.pump();

    expect(result.isSuccess, isTrue);
    expect(controller.offset, closeTo(900000 * 48, 0.5));
    expect(find.text('Item 900000'), findsOneWidget);
    expect(childBuilds - buildsBeforeJump, lessThan(80));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('far indexed animation does not build intermediate windows', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    var childBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              estimatedExtent: 48,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  childBuilds += 1;
                  return SizedBox(height: 48, child: Text('Item $index'));
                },
                childCount: 1000000,
              ),
            ),
          ],
        ),
      ),
    );
    final int buildsBeforeAnimation = childBuilds;

    final Future<ScrollResult> future = controller.animateToTarget(
      ScrollTarget.index(900000),
      placement: const ScrollPlacement.start(),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      ),
    );
    for (var frame = 0; frame < 45; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final ScrollResult result = await pumpScrollCommand(
      tester,
      future,
      maxFrames: 30,
    );

    expect(result.isSuccess, isTrue);
    expect(find.text('Item 900000'), findsOneWidget);
    expect(childBuilds - buildsBeforeAnimation, lessThan(120));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('far dynamic animation corrects precisely without replaying', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    var childBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              estimatedExtent: 48,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  childBuilds += 1;
                  return ColoredBox(
                    key: ValueKey<int>(index),
                    color: const Color(0xFF16C79A),
                    child: SizedBox(height: index == 900000 ? 120 : 48),
                  );
                },
                childCount: 1000000,
              ),
            ),
          ],
        ),
      ),
    );
    final int buildsBeforeAnimation = childBuilds;

    final Future<ScrollResult> future = controller.animateToTarget(
      ScrollTarget.index(900000),
      placement: const ScrollPlacement.center(),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      ),
    );
    for (var frame = 0; frame < 60; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final ScrollResult result = await pumpScrollCommand(
      tester,
      future,
      maxFrames: 15,
    );

    final Finder target = find.byKey(const ValueKey<int>(900000));
    expect(result.isSuccess, isTrue);
    expect(result.finalError, lessThanOrEqualTo(0.5));
    expect(tester.getTopLeft(target).dy, closeTo(240, 0.5));
    expect(childBuilds - buildsBeforeAnimation, lessThan(160));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('user drag interrupts far rebase on the next frame', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    var childBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              estimatedExtent: 48,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  childBuilds += 1;
                  return SizedBox(height: 48, child: Text('Item $index'));
                },
                childCount: 1000000,
              ),
            ),
          ],
        ),
      ),
    );
    final int buildsBeforeAnimation = childBuilds;
    final Future<ScrollResult> future = controller.animateToTarget(
      ScrollTarget.index(900000),
      placement: const ScrollPlacement.start(),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final double pixelsAtInterruption = controller.offset;

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.interruptedByUser);
    expect(controller.offset, greaterThan(pixelsAtInterruption));
    expect(childBuilds - buildsBeforeAnimation, lessThan(180));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('reduced motion turns far animation into one settled jump', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    var childBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                      childBuilds += 1;
                      return SizedBox(height: 48, child: Text('Item $index'));
                    },
                    childCount: 1000000,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final int buildsBeforeAnimation = childBuilds;

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.animateToTarget(
        ScrollTarget.index(900000),
        placement: const ScrollPlacement.start(),
        motion: const ScrollMotion.duration(
          duration: Duration(seconds: 2),
          curve: Curves.easeInOutCubic,
        ),
      ),
      maxFrames: 15,
    );

    expect(result.isSuccess, isTrue);
    expect(find.text('Item 900000'), findsOneWidget);
    expect(childBuilds - buildsBeforeAnimation, lessThan(80));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('far indexed animation masks the window switch frame', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 1000000,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );
    const Key repaintBoundaryKey = Key('indexed-rebase-boundary');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: RepaintBoundary(
          key: repaintBoundaryKey,
          child: ColoredBox(
            color: const Color(0xFF00FF00),
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => const ColoredBox(
                      color: Color(0xFFFF0000),
                      child: SizedBox(height: 48),
                    ),
                    childCount: 1000000,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final Future<ScrollResult> future = controller.animateToTarget(
      ScrollTarget.index(900000),
      placement: const ScrollPlacement.start(),
      motion: const ScrollMotion.duration(
        duration: Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final Color sampled = (await tester.runAsync<Color>(() async {
      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byKey(repaintBoundaryKey),
      );
      final ui.Image image = await boundary.toImage(pixelRatio: 1);
      final ByteData bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      const int sampleX = 4;
      const int sampleY = 4;
      final int byteOffset = (sampleY * image.width + sampleX) * 4;
      final Color result = Color.fromARGB(
        bytes.getUint8(byteOffset + 3),
        bytes.getUint8(byteOffset),
        bytes.getUint8(byteOffset + 1),
        bytes.getUint8(byteOffset + 2),
      );
      image.dispose();
      return result;
    }))!;

    expect(sampled, const Color(0xFFF8FAFC));

    await tester.pump(const Duration(milliseconds: 300));
    final ScrollResult result = await pumpScrollCommand(
      tester,
      future,
      maxFrames: 15,
    );
    expect(result.isSuccess, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('indexed snapshot reports effective visible item fractions', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 100,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
      obstructionResolver: (ScrollViewportGeometry viewport) =>
          VisibleRegion.fromIntervals(
        const <LogicalInterval>[LogicalInterval(24, 96)],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 120,
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 48,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) =>
                        SizedBox(height: 48, child: Text('Item $index')),
                    childCount: 100,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final List<ScrollVisibleTarget> visible =
        controller.state.value.visibleTargets;
    expect(
      controller.capabilities.supports(ScrollCapability.visibleItems),
      isTrue,
    );
    expect(
      visible.map((ScrollVisibleTarget target) => target.index),
      <int?>[0, 1],
    );
    expect(visible[0].visibleFraction, closeTo(0.5, 1e-9));
    expect(visible[0].isFullyVisible, isFalse);
    expect(visible[1].visibleFraction, 1);
    expect(visible[1].isFullyVisible, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('indexed sliver releases listeners across 1000 reattachments', (
    WidgetTester tester,
  ) async {
    final _CountingValueNotifier<int> revision = _CountingValueNotifier<int>(0);
    final ListSeekoIndexDelegate<int> indexDelegate =
        ListSeekoIndexDelegate<int>(
      itemCount: 20,
      revision: revision,
      keyAt: (int index) => index,
      indexOfKey: (int key) => key,
    );
    final SeekoController controller = SeekoController(
      indexDelegate: indexDelegate,
    );

    for (var iteration = 0; iteration < 1000; iteration += 1) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 120,
            child: CustomScrollView(
              controller: controller,
              slivers: <Widget>[
                SeekoIndexedSliver(
                  controller: controller,
                  indexDelegate: indexDelegate,
                  estimatedExtent: 40,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) =>
                        const SizedBox(height: 40),
                    childCount: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(revision.listenerCount, 1, reason: 'attach $iteration');
      expect(controller.positions, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(revision.listenerCount, 0, reason: 'detach $iteration');
      expect(controller.positions, isEmpty);
    }

    controller.dispose();
    revision.dispose();
  });
}

final class _CountingValueNotifier<T> extends ValueNotifier<T> {
  _CountingValueNotifier(super.value);

  var listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    listenerCount += 1;
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    listenerCount -= 1;
  }
}

Widget _initialFailureHarness({
  required SeekoController controller,
  required SeekoIndexDelegate<Object> indexDelegate,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 120,
        child: CustomScrollView(
          controller: controller,
          slivers: <Widget>[
            SeekoIndexedSliver(
              controller: controller,
              indexDelegate: indexDelegate,
              estimatedExtent: 40,
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) =>
                    SizedBox(height: 40, child: Text('Item $index')),
                childCount: 10,
              ),
            ),
          ],
        ),
      ),
    );
