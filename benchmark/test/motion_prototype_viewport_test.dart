import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/motion_prototype_models.dart';
import 'package:seeko_benchmark/src/motion_prototype_trajectory.dart';
import 'package:seeko_benchmark/src/motion_prototype_viewport.dart';

void main() {
  testWidgets('crossfade mounts two bounded windows during transition', (
    WidgetTester tester,
  ) async {
    final MotionPrototypeTrace trace = _trace(
      MotionPrototypeCandidate.dualViewportCrossfade,
      100,
    );
    final MotionPrototypeFrame frame = trace.frames[trace.frames.length ~/ 2];

    await tester.pumpWidget(_host(trace, frame));

    expect(find.byKey(const Key('prototype-window-source')), findsOneWidget);
    expect(
      find.byKey(const Key('prototype-window-destination')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('prototype-cruise-layer')), findsNothing);
  });

  testWidgets('far rebase keeps one item window and a non-opacity cruise layer',
      (
    WidgetTester tester,
  ) async {
    final MotionPrototypeTrace trace = _trace(
      MotionPrototypeCandidate.virtualWindowRebase,
      1000,
    );
    final MotionPrototypeFrame frame = trace.frames[trace.frames.length ~/ 2];

    await tester.pumpWidget(_host(trace, frame));

    expect(find.byType(MotionPrototypeItem), findsWidgets);
    expect(find.byKey(const Key('prototype-cruise-layer')), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(
      find.byKey(const Key('prototype-window-destination')),
      findsOneWidget,
    );
  });

  testWidgets('rebase child widgets are reused until the window epoch changes',
      (
    WidgetTester tester,
  ) async {
    final MotionPrototypeTrace trace = _trace(
      MotionPrototypeCandidate.virtualWindowRebase,
      1000,
    );
    var builds = 0;
    final List<MotionPrototypeFrame> firstEpoch = trace.frames
        .where((MotionPrototypeFrame value) => value.windowEpoch == 0)
        .toList(growable: false);
    final MotionPrototypeFrame destination = trace.frames.firstWhere(
      (MotionPrototypeFrame value) => value.windowEpoch == 1,
    );

    await tester.pumpWidget(
      _host(trace, firstEpoch.first, onChildBuilt: () => builds += 1),
    );
    final int initialBuilds = builds;
    await tester.pumpWidget(
      _host(trace, firstEpoch.last, onChildBuilt: () => builds += 1),
    );
    expect(builds, initialBuilds);

    await tester.pumpWidget(
      _host(trace, destination, onChildBuilt: () => builds += 1),
    );
    expect(builds, greaterThan(initialBuilds));
    expect(builds, lessThanOrEqualTo(initialBuilds * 3));
  });

  testWidgets('a new measurement generation rebuilds the bounded window', (
    WidgetTester tester,
  ) async {
    final MotionPrototypeTrace trace = _trace(
      MotionPrototypeCandidate.virtualWindowRebase,
      1000,
    );
    var builds = 0;

    await tester.pumpWidget(
      _host(
        trace,
        trace.frames.first,
        windowGeneration: 1,
        onChildBuilt: () => builds += 1,
      ),
    );
    final int firstGenerationBuilds = builds;
    await tester.pumpWidget(
      _host(
        trace,
        trace.frames.first,
        windowGeneration: 2,
        onChildBuilt: () => builds += 1,
      ),
    );

    expect(builds, greaterThan(firstGenerationBuilds));
  });
}

Widget _host(
  MotionPrototypeTrace trace,
  MotionPrototypeFrame frame, {
  int windowGeneration = 0,
  VoidCallback? onChildBuilt,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 640,
          height: 800,
          child: MotionPrototypeViewport(
            candidate: trace.candidate,
            testCase: trace.testCase,
            targetPixels: trace.targetPixels,
            frame: frame,
            windowGeneration: windowGeneration,
            onChildBuilt: onChildBuilt,
          ),
        ),
      ),
    ),
  );
}

MotionPrototypeTrace _trace(
  MotionPrototypeCandidate candidate,
  double distance,
) {
  return MotionPrototypeTrajectory.forCandidate(candidate).trace(
    MotionPrototypeCase(
      distanceViewports: distance,
      extentProfile: MotionExtentProfile.deterministicDynamic,
      direction: MotionDirection.forward,
      refreshRateHz: 120,
      interruptAt: 0.5,
    ),
    viewportExtent: 800,
  );
}
