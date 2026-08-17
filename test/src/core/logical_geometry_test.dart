import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('logical coordinates normalize every axis direction', () {
    const double min = 20;
    const double max = 220;
    for (final AxisDirection direction in AxisDirection.values) {
      final LogicalAxisGeometry geometry = LogicalAxisGeometry(
        axisDirection: direction,
        minScrollExtent: min,
        maxScrollExtent: max,
      );
      expect(geometry.logicalToPhysical(geometry.physicalToLogical(70)), 70);
      expect(geometry.axis, axisDirectionToAxis(direction));
      expect(geometry.physicalToLogical(min), 0);
      expect(geometry.extent, 200);
    }
  });

  test('visible intervals merge overlap and calculate coverage', () {
    final VisibleRegion region = VisibleRegion.fromIntervals(
      const <LogicalInterval>[
        LogicalInterval(0, 20),
        LogicalInterval(10, 40),
        LogicalInterval(60, 100),
      ],
    );
    expect(region.intervals, const <LogicalInterval>[
      LogicalInterval(0, 40),
      LogicalInterval(60, 100),
    ]);
    expect(region.visibleFraction(const LogicalInterval(20, 80)),
        closeTo(2 / 3, 1e-9));
    expect(region.largestInterval, const LogicalInterval(0, 40));
  });

  test('exact placement uses target and effective viewport anchors', () {
    final ScrollPlacementResolution resolution = resolveScrollPlacement(
      placement: ScrollPlacement.exact(
        targetAnchor: 0.5,
        viewportAnchor: 0.5,
        offset: 10,
      ),
      target: const LogicalInterval(400, 500),
      visibleRegion: VisibleRegion.fromIntervals(
        const <LogicalInterval>[LogicalInterval(20, 280)],
      ),
      currentPixels: 0,
    );

    expect(resolution.pixels, 310);
    expect(resolution.alreadySatisfied, isFalse);
  });

  test('nearest preserves full visibility while visible preserves any exposure',
      () {
    final VisibleRegion viewport = VisibleRegion.fromIntervals(
      const <LogicalInterval>[LogicalInterval(0, 300)],
    );

    expect(
      resolveScrollPlacement(
        placement: const ScrollPlacement.nearest(),
        target: const LogicalInterval(280, 380),
        visibleRegion: viewport,
        currentPixels: 0,
      ).pixels,
      80,
    );
    final ScrollPlacementResolution visible = resolveScrollPlacement(
      placement: const ScrollPlacement.visible(),
      target: const LogicalInterval(280, 380),
      visibleRegion: viewport,
      currentPixels: 0,
    );
    expect(visible.pixels, 0);
    expect(visible.alreadySatisfied, isTrue);
  });

  test('placement selects the largest unobstructed interval by default', () {
    final ScrollPlacementResolution resolution = resolveScrollPlacement(
      placement: const ScrollPlacement.center(),
      target: const LogicalInterval(400, 500),
      visibleRegion: VisibleRegion.fromIntervals(
        const <LogicalInterval>[
          LogicalInterval(0, 80),
          LogicalInterval(120, 300),
        ],
      ),
      currentPixels: 0,
    );

    expect(resolution.pixels, 240);
  });

  test('exact placement can select a specific unobstructed interval', () {
    final ScrollPlacementResolution resolution = resolveScrollPlacement(
      placement: ScrollPlacement.exact(
        targetAnchor: 0.5,
        viewportAnchor: 0.5,
        viewportInterval: const ScrollViewportInterval.at(0),
      ),
      target: const LogicalInterval(400, 500),
      visibleRegion: VisibleRegion.fromIntervals(
        const <LogicalInterval>[
          LogicalInterval(0, 80),
          LogicalInterval(120, 300),
        ],
      ),
      currentPixels: 0,
    );

    expect(resolution.pixels, 410);
  });

  test('a selected viewport interval validates against resolved geometry', () {
    expect(
      () => resolveScrollPlacement(
        placement: ScrollPlacement.exact(
          targetAnchor: 0,
          viewportAnchor: 0,
          viewportInterval: const ScrollViewportInterval.at(2),
        ),
        target: const LogicalInterval(0, 10),
        visibleRegion: VisibleRegion.fromIntervals(
          const <LogicalInterval>[LogicalInterval(0, 100)],
        ),
        currentPixels: 0,
      ),
      throwsRangeError,
    );
  });
}
