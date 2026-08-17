import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';
import 'package:seeko/src/flutter/seeko_position_driver.dart';

void main() {
  testWidgets('position driver owns resolve and jump execution',
      (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    var commits = 0;
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        commits += 1;
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => null,
      hasRegistryFor: (_) => false,
      frameInterval: const Duration(milliseconds: 16),
      reducedMotion: false,
    );

    final ScrollResolution resolution = await driver.resolve(
      const ScrollTarget.edge(ScrollEdge.trailing),
    );
    final ScrollDriverResult result = await driver.jump(resolution);

    expect(resolution.isResolved, isTrue);
    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalLogicalPixels, controller.position.maxScrollExtent);
    expect(commits, 1);
    cancellation.dispose();
    controller.dispose();
  });

  testWidgets('position driver maps unsupported semantic targets explicitly',
      (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => null,
      hasRegistryFor: (_) => false,
      frameInterval: const Duration(milliseconds: 16),
      reducedMotion: false,
    );

    expect(
      await driver.resolve(ScrollTarget.index(80)),
      const ScrollResolution.unsupported(),
    );
    cancellation.dispose();
    controller.dispose();
  });

  testWidgets('position driver rechecks cancellation after mounted lookup',
      (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    final GlobalKey target = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: <Widget>[
            SizedBox(key: target, height: 1000),
          ],
        ),
      ),
    );
    final Completer<BuildContext?> lookup = Completer<BuildContext?>();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => lookup.future,
      hasRegistryFor: (_) => true,
      frameInterval: const Duration(milliseconds: 16),
      reducedMotion: false,
    );

    final Future<ScrollResolution> future =
        driver.resolve(ScrollTarget.key('target'));
    cancellation.cancel(ScrollStopReason.superseded);
    lookup.complete(target.currentContext);

    expect(await future, const ScrollResolution.targetDeleted());
    cancellation.dispose();
    controller.dispose();
  });

  testWidgets(
      'animation completes when Flutter reaches the target but its '
      'activity future stalls', (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<void> stalledActivity = Completer<void>();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => null,
      hasRegistryFor: (_) => false,
      frameInterval: const Duration(milliseconds: 8),
      reducedMotion: false,
      positionAnimator: (double pixels, Duration duration, Curve curve) {
        controller.jumpTo(pixels);
        return stalledActivity.future;
      },
    );
    final ScrollResolution resolution = await driver.resolve(
      ScrollTarget.offset(250),
    );
    final ScrollMotionPlan plan = ScrollMotionPlan(
      distance: 250,
      duration: const Duration(milliseconds: 10),
      curve: Curves.linear,
      frameInterval: const Duration(milliseconds: 8),
      requiresWindowRebase: false,
    );

    final Future<ScrollDriverResult> future = driver.animate(resolution, plan);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump(const Duration(milliseconds: 8));
    final ScrollDriverResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(
      result.diagnostics,
      containsPair('animationCompletionFallback', true),
    );
    cancellation.dispose();
    controller.dispose();
  });

  testWidgets(
      'watchdog lets the final scheduled animation frame complete before '
      'using the fallback', (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<void> finalFrame = Completer<void>();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => null,
      hasRegistryFor: (_) => false,
      frameInterval: const Duration(milliseconds: 8),
      reducedMotion: false,
      positionAnimator: (double pixels, Duration duration, Curve curve) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          controller.jumpTo(pixels);
          finalFrame.complete();
        });
        return finalFrame.future;
      },
    );
    final ScrollResolution resolution = await driver.resolve(
      ScrollTarget.offset(250),
    );
    final ScrollMotionPlan plan = ScrollMotionPlan(
      distance: 250,
      duration: const Duration(milliseconds: 10),
      curve: Curves.linear,
      frameInterval: const Duration(milliseconds: 8),
      requiresWindowRebase: false,
    );

    final Future<ScrollDriverResult> future = driver.animate(resolution, plan);
    await tester.pump(const Duration(milliseconds: 30));
    final ScrollDriverResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalError, 0);
    expect(result.diagnostics, isNull);
    cancellation.dispose();
    controller.dispose();
  });

  testWidgets(
      'animation returns control when the activity stalls short of the '
      'target after its planned duration', (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<void> stalledActivity = Completer<void>();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => null,
      hasRegistryFor: (_) => false,
      frameInterval: const Duration(milliseconds: 8),
      reducedMotion: false,
      positionAnimator: (double pixels, Duration duration, Curve curve) {
        controller.jumpTo(200);
        return stalledActivity.future;
      },
    );
    final ScrollResolution resolution = await driver.resolve(
      ScrollTarget.offset(250),
    );
    final ScrollMotionPlan plan = ScrollMotionPlan(
      distance: 250,
      duration: const Duration(milliseconds: 10),
      curve: Curves.linear,
      frameInterval: const Duration(milliseconds: 8),
      requiresWindowRebase: false,
    );

    final Future<ScrollDriverResult> future = driver.animate(resolution, plan);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump(const Duration(milliseconds: 8));
    final ScrollDriverResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.finalError, 0);
    expect(
      result.diagnostics,
      containsPair('animationCompletionFallback', true),
    );
    cancellation.dispose();
    controller.dispose();
  });

  testWidgets('stabilization schedules a settle frame from post-frame phase',
      (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => null,
      hasRegistryFor: (_) => false,
      frameInterval: const Duration(milliseconds: 16),
      reducedMotion: false,
    );
    final ScrollTarget target = ScrollTarget.offset(250);
    final ScrollResolution resolution = await driver.resolve(target);
    final ScrollDriverResult moved = await driver.jump(resolution);
    final Completer<ScrollDriverResult> settled =
        Completer<ScrollDriverResult>();

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      settled.complete(
        await driver.stabilize(
          target,
          resolution,
          moved,
          executionPolicy: ScrollExecutionPolicy(settleSamples: 2),
        ),
      );
    });
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect((await settled.future).outcome, ScrollOutcome.completed);

    cancellation.dispose();
    controller.dispose();
  });

  testWidgets('stabilization samples stable geometry while frames are disabled',
      (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => Text('$index'),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: ScrollCapabilities.pixel,
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.nearest(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => null,
      hasRegistryFor: (_) => false,
      frameInterval: const Duration(milliseconds: 8),
      reducedMotion: false,
    );
    final ScrollTarget target = ScrollTarget.offset(250);
    final ScrollResolution resolution = await driver.resolve(target);
    final ScrollDriverResult moved = await driver.jump(resolution);
    // Flutter's binding only exposes lifecycle simulation through this
    // protected hook in widget tests.
    // ignore: invalid_use_of_protected_member
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() {
      // ignore: invalid_use_of_protected_member
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    final ScrollDriverResult? result =
        await tester.runAsync<ScrollDriverResult>(() async {
      return driver
          .stabilize(
            target,
            resolution,
            moved,
            executionPolicy: ScrollExecutionPolicy(settleSamples: 2),
          )
          .timeout(const Duration(milliseconds: 150));
    });

    expect(result!.outcome, ScrollOutcome.completed);
    cancellation.dispose();
    controller.dispose();
  });

  testWidgets(
      'stabilization does not re-resolve a mounted target from stale layout '
      'while frames are disabled', (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    final GlobalKey targetKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, int index) => SizedBox(
            key: index == 10 ? targetKey : null,
            child: Text('$index'),
          ),
        ),
      ),
    );
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final SeekoPositionDriver driver = SeekoPositionDriver(
      position: controller.position,
      capabilities: const ScrollCapabilities(
        ScrollCapability.pixelBit | ScrollCapability.mountedTargetBit,
      ),
      resolutionMode: ScrollResolutionMode.exact,
      placement: const ScrollPlacement.start(),
      boundaryPolicy: ScrollBoundaryPolicy.clampNumeric,
      cancellationToken: cancellation.token,
      commit: (VoidCallback callback) {
        callback();
        return true;
      },
      isCurrentPosition: () => true,
      mountedContextFor: (_) => targetKey.currentContext,
      hasRegistryFor: (_) => true,
      frameInterval: const Duration(milliseconds: 8),
      reducedMotion: false,
    );
    final ScrollTarget target = ScrollTarget.key('target');
    final ScrollResolution resolution = await driver.resolve(target);
    // ignore: invalid_use_of_protected_member
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() {
      // ignore: invalid_use_of_protected_member
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final ScrollDriverResult moved = await driver.jump(resolution);

    final ScrollDriverResult? result =
        await tester.runAsync<ScrollDriverResult>(() async {
      return driver
          .stabilize(
            target,
            resolution,
            moved,
            executionPolicy: ScrollExecutionPolicy(settleSamples: 2),
          )
          .timeout(const Duration(milliseconds: 150));
    });

    expect(result!.outcome, ScrollOutcome.completed);
    expect(result.finalError, 0);
    expect(result.correctionCount, 0);
    cancellation.dispose();
    controller.dispose();
  });
}
