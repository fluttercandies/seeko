import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  test('a binding is exclusively claimed and reusable after dispose', () {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController first = SeekoController.adapt(
      existing,
      binding: binding,
    );

    expect(
      () => SeekoController.adapt(existing, binding: binding),
      throwsStateError,
    );

    first.dispose();
    final SeekoController replacement = SeekoController.adapt(
      existing,
      binding: binding,
    );
    replacement.dispose();
    existing.dispose();
  });

  testWidgets('adapter explicitly binds and rebinds an existing position',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
    );
    await tester.pumpWidget(_list(existing, itemCount: 100));

    expect(adapter.isAttached, isFalse);
    binding.rebind(existing.position);
    expect(adapter.isAttached, isTrue);
    expect(adapter.position, same(existing.position));

    final ScrollResult first = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(ScrollTarget.offset(300)),
    );
    expect(first.outcome, ScrollOutcome.completed);
    expect(existing.offset, 300);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    binding.unbind();
    expect(adapter.isAttached, isFalse);
    await tester.pumpWidget(_list(existing, itemCount: 200));
    binding.rebind(existing.position);
    final ScrollResult second = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(ScrollTarget.offset(500)),
    );
    expect(second.outcome, ScrollOutcome.completed);
    expect(existing.offset, 500);

    adapter.dispose();
    expect(existing.hasClients, isTrue);
    existing.jumpTo(100);
    expect(existing.offset, 100);
    existing.dispose();
  });

  testWidgets('non-exclusive adapter exposes degraded best-effort results',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
    );
    await tester.pumpWidget(_list(existing, itemCount: 100));
    binding.rebind(existing.position);

    expect(
      adapter.capabilities.supports(ScrollCapability.singleWriter),
      isFalse,
    );
    expect(
      adapter.capabilities.supports(ScrollCapability.programmaticResult),
      isFalse,
    );
    expect(
      adapter.capabilities.supports(ScrollCapability.strictSync),
      isFalse,
    );
    expect(
      adapter.capabilities.supports(ScrollCapability.mountedTarget),
      isTrue,
    );
    final ScrollResult result = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(ScrollTarget.offset(300)),
    );
    final ScrollResult clamped = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(ScrollTarget.offset(-100)),
    );
    final ScrollResult failure = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(ScrollTarget.index(50)),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.resolutionMode, ScrollResolutionMode.fallback);
    expect(result.isDegraded, isTrue);
    expect(clamped.outcome, ScrollOutcome.clamped);
    expect(clamped.resolutionMode, ScrollResolutionMode.fallback);
    expect(failure.outcome, ScrollOutcome.unsupported);
    expect(failure.resolutionMode, ScrollResolutionMode.fallback);
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('resolution policy can reject adapted fallback success',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
    );
    await tester.pumpWidget(_list(existing, itemCount: 100));
    binding.rebind(existing.position);

    final ScrollResult requireExact = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(
        ScrollTarget.offset(300),
        options: const ScrollCommandOptions(
          resolutionPolicy: ScrollResolutionPolicy(requireExact: true),
        ),
      ),
    );
    final ScrollResult rejectFallback = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(
        ScrollTarget.offset(500),
        options: const ScrollCommandOptions(
          resolutionPolicy: ScrollResolutionPolicy(allowFallback: false),
        ),
      ),
    );

    expect(requireExact.outcome, ScrollOutcome.unsupported);
    expect(
      requireExact.diagnostics,
      containsPair('resolutionPolicyRejected', 'fallback'),
    );
    expect(rejectFallback.outcome, ScrollOutcome.unsupported);
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('non-exclusive terminal cancellation result stays degraded',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    await tester.pumpWidget(_list(existing, itemCount: 200));
    binding.rebind(existing.position);

    final Future<ScrollResult> future = adapter.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
      options: ScrollCommandOptions(
        cancellationToken: cancellation.token,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    cancellation.cancel();
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.cancelled);
    expect(result.resolutionMode, ScrollResolutionMode.fallback);
    expect(result.isDegraded, isTrue);
    cancellation.dispose();
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('exclusive adapter declares only guarantees it can uphold',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
    );
    await tester.pumpWidget(_list(existing, itemCount: 100));
    binding.rebind(existing.position);

    expect(
      adapter.capabilities.supports(ScrollCapability.singleWriter),
      isTrue,
    );
    expect(
      adapter.capabilities.supports(ScrollCapability.programmaticResult),
      isFalse,
    );
    expect(
      adapter.capabilities.supports(ScrollCapability.strictSync),
      isFalse,
    );
    expect(
      adapter.capabilities.supports(ScrollCapability.mountedTarget),
      isTrue,
    );

    adapter.dispose();
    existing.dispose();
  });

  testWidgets('binding selects one position from a multi-position controller',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(child: _bareList(existing, itemCount: 100)),
            Expanded(child: _bareList(existing, itemCount: 100)),
          ],
        ),
      ),
    );
    final List<ScrollPosition> positions = existing.positions.toList();
    expect(positions, hasLength(2));
    binding.rebind(positions.last);

    await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(ScrollTarget.offset(300)),
    );

    expect(positions.first.pixels, 0);
    expect(positions.last.pixels, 300);
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('external writes remain visible and are not intercepted',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
    );
    await tester.pumpWidget(_list(existing, itemCount: 100));
    binding.rebind(existing.position);
    await tester.pump();

    existing.jumpTo(400);
    await tester.pump();

    expect(existing.offset, 400);
    expect(adapter.state.value.pixels, 400);
    expect(adapter.state.value.phase, ScrollPhase.idle);
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('adapted observation reports generic external scrolling',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
    );
    await tester.pumpWidget(_list(existing, itemCount: 200));
    binding.rebind(existing.position);

    final Future<void> animation = existing.animateTo(
      2000,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(adapter.state.value.phase, ScrollPhase.scrolling);
    expect(adapter.state.value.velocity, 0);

    await tester.pumpAndSettle();
    await animation;
    expect(adapter.state.value.phase, ScrollPhase.idle);
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('adapter removes its position listener on dispose',
      (WidgetTester tester) async {
    final _TrackingScrollController existing = _TrackingScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
    );
    await tester.pumpWidget(_list(existing, itemCount: 100));
    final _TrackingScrollPosition position = existing.trackingPosition;
    final int listenersBeforeBinding = position.listenerBalance;
    final int scrollingListenersBeforeBinding =
        position.trackingScrollingNotifier.listenerBalance;

    binding.rebind(position);
    expect(position.listenerBalance, listenersBeforeBinding + 1);
    expect(
      position.trackingScrollingNotifier.listenerBalance,
      scrollingListenersBeforeBinding + 1,
    );
    await tester.pump();
    position.jumpTo(250);
    await tester.pump();
    expect(adapter.state.value.pixels, 250);

    adapter.dispose();
    expect(position.listenerBalance, listenersBeforeBinding);
    expect(
      position.trackingScrollingNotifier.listenerBalance,
      scrollingListenersBeforeBinding,
    );
    existing.dispose();
  });

  testWidgets('binding rejects positions not owned by the existing controller',
      (WidgetTester tester) async {
    final ScrollController first = ScrollController();
    final ScrollController second = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      first,
      binding: binding,
      exclusiveProgrammaticWrites: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(child: ListView(controller: first)),
            Expanded(child: ListView(controller: second)),
          ],
        ),
      ),
    );

    expect(() => binding.rebind(second.position), throwsStateError);
    adapter.dispose();
    first.dispose();
    second.dispose();
  });

  testWidgets('adapted mounted reveal uses the explicitly bound viewport',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 300,
            child: SingleChildScrollView(
              controller: existing,
              child: Column(
                children: List<Widget>.generate(
                  20,
                  (int index) => SeekoTag(
                    controller: adapter,
                    targetKey: index,
                    child: const SizedBox(height: 100),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    binding.rebind(existing.position);

    final ScrollResult result = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(
        ScrollTarget.key(8),
        placement: const ScrollPlacement.center(),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(existing.offset, closeTo(700, 0.5));
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('rebind during resolution prevents a jump on the replacement',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    late ScrollPosition replacementPosition;
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
      obstructionResolver: (ScrollViewportGeometry viewport) {
        binding.rebind(replacementPosition);
        return VisibleRegion.fromIntervals(<LogicalInterval>[
          LogicalInterval(0, viewport.viewportExtent),
        ]);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                controller: existing,
                child: Column(
                  children: List<Widget>.generate(
                    20,
                    (int index) => SeekoTag(
                      controller: adapter,
                      targetKey: index,
                      child: const SizedBox(height: 100),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: _bareList(existing, itemCount: 100)),
          ],
        ),
      ),
    );
    final List<ScrollPosition> positions = existing.positions.toList();
    final ScrollPosition oldPosition = positions.first;
    replacementPosition = positions.last;
    binding.rebind(oldPosition);

    final ScrollResult result = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(
        ScrollTarget.key(8),
        placement: const ScrollPlacement.center(),
      ),
    );

    expect(result.outcome, ScrollOutcome.detached);
    expect(replacementPosition.pixels, 0);
    adapter.dispose();
    existing.dispose();
  });

  testWidgets(
      'rebind during resolution prevents an animation on the replacement',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    late ScrollPosition replacementPosition;
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
      obstructionResolver: (ScrollViewportGeometry viewport) {
        binding.rebind(replacementPosition);
        return VisibleRegion.fromIntervals(<LogicalInterval>[
          LogicalInterval(0, viewport.viewportExtent),
        ]);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                controller: existing,
                child: Column(
                  children: List<Widget>.generate(
                    20,
                    (int index) => SeekoTag(
                      controller: adapter,
                      targetKey: index,
                      child: const SizedBox(height: 100),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: _bareList(existing, itemCount: 100)),
          ],
        ),
      ),
    );
    final List<ScrollPosition> positions = existing.positions.toList();
    final ScrollPosition oldPosition = positions.first;
    replacementPosition = positions.last;
    binding.rebind(oldPosition);

    final Future<ScrollResult> future = adapter.animateToTarget(
      ScrollTarget.key(8),
      placement: const ScrollPlacement.center(),
      motion: const ScrollMotion.instant(),
    );
    final ScrollResult result = await future;
    final double oldPixels = oldPosition.pixels;
    final double replacementPixels = replacementPosition.pixels;

    expect(result.outcome, ScrollOutcome.detached);
    expect(oldPixels, 0);
    expect(replacementPixels, 0);
    expect(replacementPosition.pixels, 0);
    adapter.dispose();
    existing.dispose();
  });

  testWidgets('rebind detaches the old command before selecting a new position',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                key: const ValueKey<String>('old'),
                controller: existing,
                itemExtent: 50,
                itemCount: 200,
                itemBuilder: (_, int index) => Text('old $index'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: const ValueKey<String>('new'),
                controller: existing,
                itemExtent: 50,
                itemCount: 200,
                itemBuilder: (_, int index) => Text('new $index'),
              ),
            ),
          ],
        ),
      ),
    );
    final List<ScrollPosition> positions = existing.positions.toList();
    final ScrollPosition oldPosition = positions.first;
    final ScrollPosition newPosition = positions.last;
    binding.rebind(oldPosition);

    final Future<ScrollResult> oldCommand = adapter.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    binding.rebind(newPosition);

    expect((await oldCommand).outcome, ScrollOutcome.detached);
    expect(adapter.position, same(newPosition));
    final ScrollResult newCommand = await pumpScrollCommand(
      tester,
      adapter.jumpToTarget(ScrollTarget.offset(500)),
    );
    expect(newCommand.outcome, ScrollOutcome.completed);
    expect(newPosition.pixels, closeTo(500, 0.5));
    await tester.pump(const Duration(seconds: 2));
    expect(newPosition.pixels, closeTo(500, 0.5));

    adapter.dispose();
    existing.dispose();
  });

  testWidgets(
      'rebind atomically detaches queued commands from the old position',
      (WidgetTester tester) async {
    final ScrollController existing = ScrollController();
    final SeekoPositionBinding binding = SeekoPositionBinding();
    final SeekoController adapter = SeekoController.adapt(
      existing,
      binding: binding,
      exclusiveProgrammaticWrites: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(child: _bareList(existing, itemCount: 200)),
            Expanded(child: _bareList(existing, itemCount: 200)),
          ],
        ),
      ),
    );
    final List<ScrollPosition> positions = existing.positions.toList();
    final ScrollPosition oldPosition = positions.first;
    final ScrollPosition replacement = positions.last;
    binding.rebind(oldPosition);

    final Future<ScrollResult> active = adapter.animateToTarget(
      ScrollTarget.offset(3000),
      motion: const ScrollMotion.duration(
        duration: Duration(seconds: 2),
        curve: Curves.linear,
      ),
    );
    final Future<ScrollResult> queued = adapter.jumpToTarget(
      ScrollTarget.offset(500),
      options: const ScrollCommandOptions(
        conflictPolicy: ScrollConflictPolicy.enqueue,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    binding.rebind(replacement);

    expect((await active).outcome, ScrollOutcome.detached);
    expect((await queued).outcome, ScrollOutcome.detached);
    expect(replacement.pixels, 0);
    adapter.dispose();
    existing.dispose();
  });
}

Widget _list(ScrollController controller, {required int itemCount}) {
  return MaterialApp(
    home: _bareList(controller, itemCount: itemCount),
  );
}

Widget _bareList(ScrollController controller, {required int itemCount}) {
  return ListView.builder(
    controller: controller,
    itemExtent: 50,
    itemCount: itemCount,
    itemBuilder: (_, int index) => Text('$index'),
  );
}

final class _TrackingScrollController extends ScrollController {
  late _TrackingScrollPosition trackingPosition;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return trackingPosition = _TrackingScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

final class _TrackingScrollPosition extends ScrollPositionWithSingleContext {
  _TrackingScrollPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    required super.oldPosition,
    required super.debugLabel,
  });

  int listenerBalance = 0;

  final _TrackingValueNotifier trackingScrollingNotifier =
      _TrackingValueNotifier(false);

  @override
  ValueNotifier<bool> get isScrollingNotifier => trackingScrollingNotifier;

  @override
  void addListener(VoidCallback listener) {
    listenerBalance += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerBalance -= 1;
    super.removeListener(listener);
  }
}

final class _TrackingValueNotifier extends ValueNotifier<bool> {
  _TrackingValueNotifier(super.value);

  int listenerBalance = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerBalance += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerBalance -= 1;
    super.removeListener(listener);
  }
}
