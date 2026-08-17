import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  final SyncMetrics source = SyncMetrics(
    pixels: 200,
    minScrollExtent: 0,
    maxScrollExtent: 800,
    viewportExtent: 400,
  );

  test('pixel mapping preserves logical pixels and reports follower clamp', () {
    final SyncMetrics follower = SyncMetrics(
      pixels: 0,
      minScrollExtent: 0,
      maxScrollExtent: 150,
      viewportExtent: 300,
    );

    final SyncMappingResult result = const ScrollSyncMapping.pixels().map(
      source: source,
      follower: follower,
    );

    expect(result.pixels, 150);
    expect(result.clamped, isTrue);
  });

  test('progress mapping aligns different finite content extents', () {
    final SyncMetrics follower = SyncMetrics(
      pixels: 0,
      minScrollExtent: 0,
      maxScrollExtent: 2400,
      viewportExtent: 600,
    );

    final SyncMappingResult result = const ScrollSyncMapping.progress().map(
      source: source,
      follower: follower,
    );

    expect(result.pixels, 600);
    expect(result.clamped, isFalse);
  });

  test('delta mapping uses transaction-local member baselines', () {
    final SyncMetrics follower = SyncMetrics(
      pixels: 650,
      minScrollExtent: 0,
      maxScrollExtent: 1600,
      viewportExtent: 400,
    );

    final SyncMappingResult result = const ScrollSyncMapping.delta().map(
      source: source,
      follower: follower,
      sourceOrigin: 120,
      followerOrigin: 650,
    );

    expect(result.pixels, 730);
    expect(result.clamped, isFalse);
  });

  test('viewport-fraction mapping preserves viewport-relative distance', () {
    final SyncMetrics follower = SyncMetrics(
      pixels: 0,
      minScrollExtent: 0,
      maxScrollExtent: 1200,
      viewportExtent: 200,
    );

    final SyncMappingResult result =
        const ScrollSyncMapping.viewportFraction().map(
      source: source,
      follower: follower,
    );

    expect(result.pixels, 100);
  });

  test('mapping rejects non-finite metrics at construction time', () {
    expect(
      () => SyncMetrics(
        pixels: double.nan,
        minScrollExtent: 0,
        maxScrollExtent: 1,
        viewportExtent: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SyncMetrics(
        pixels: 0,
        minScrollExtent: 2,
        maxScrollExtent: 1,
        viewportExtent: 1,
      ),
      throwsArgumentError,
    );
  });

  test('finite progress with zero range maps deterministically to leading', () {
    final SyncMetrics zeroRange = SyncMetrics(
      pixels: 0,
      minScrollExtent: 0,
      maxScrollExtent: 0,
      viewportExtent: 300,
    );
    final SyncMetrics follower = SyncMetrics(
      pixels: 100,
      minScrollExtent: 0,
      maxScrollExtent: 500,
      viewportExtent: 300,
    );

    final SyncMappingResult result = const ScrollSyncMapping.progress().map(
      source: zeroRange,
      follower: follower,
    );

    expect(result.pixels, 0);
    expect(result.clamped, isFalse);
  });

  test('built-in mappings round-trip through one canonical coordinate', () {
    final SyncMetrics follower = SyncMetrics(
      pixels: 650,
      minScrollExtent: 0,
      maxScrollExtent: 1600,
      viewportExtent: 400,
    );
    const ScrollSyncMapping mapping = ScrollSyncMapping.delta();

    final double coordinate = mapping.memberToGroup(
      member: source,
      origin: 120,
    );
    final double followerPixels = mapping.groupToMember(
      coordinate: coordinate,
      member: follower,
      origin: 650,
    );

    expect(coordinate, 80);
    expect(followerPixels, 730);
  });

  test('custom mapping declares invertibility and composes canonically', () {
    final ScrollSyncMapping mapping = ScrollSyncMapping.custom(
      memberToGroup: (SyncMetrics member, double? origin) =>
          member.progress * 100,
      groupToMember: (
        double coordinate,
        SyncMetrics member,
        double? origin,
      ) =>
          member.minScrollExtent + coordinate / 100 * member.scrollRange,
      isInvertible: false,
    );
    final SyncMetrics follower = SyncMetrics(
      pixels: 0,
      minScrollExtent: 0,
      maxScrollExtent: 2400,
      viewportExtent: 600,
    );

    final SyncMappingResult result = mapping.map(
      source: source,
      follower: follower,
    );

    expect(mapping.kind, ScrollSyncMappingKind.custom);
    expect(mapping.isInvertible, isFalse);
    expect(result.pixels, 600);
  });
}
