import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/benchmark_environment.dart';

void main() {
  test('launch configuration decodes complete reproducibility metadata', () {
    final String metadata = base64Url.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'device': 'MacBookPro18,4 / Apple M1 Max / 32 GB',
          'operatingSystem': 'macOS 26.6 (25G72)',
          'thermalState': 'nominal',
          'powerState': 'AC / battery 80%',
          'refreshRateHz': 120,
          'flutterRevision': '559ffa3f75e7402d65a8def9c28389a9b2e6fe42',
          'engineRevision': '4c525dac5ebe5971c5708ef73558ed8edcf4a362',
          'buildMode': 'profile',
          'commit': 'unversioned-worktree',
          'seed': 24301,
          'scenario': 'native-list-view-builder-fixed-extent',
        }),
      ),
    );

    final BenchmarkLaunchConfiguration launch =
        BenchmarkLaunchConfiguration.parse(
      metadataBase64: metadata,
      outputPath: '/tmp/seeko-baseline.json',
      itemCount: '1000000',
      itemExtent: '56',
      warmUpSeconds: '5',
      minimumRunSeconds: '30',
      minimumPresentedFrames: '3600',
      runCount: '5',
    );

    expect(launch.metadata.refreshRateHz, 120);
    expect(launch.metadata.buildMode, 'profile');
    expect(launch.configuration.itemCount, 1000000);
    expect(launch.configuration.itemExtent, 56);
    expect(launch.configuration.minimumPresentedFrames, 3600);
    expect(launch.configuration.runCount, 5);
    expect(launch.outputPath, '/tmp/seeko-baseline.json');
  });

  test('launch configuration rejects an incomplete metadata envelope', () {
    final String metadata = base64Url.encode(
      utf8.encode(jsonEncode(<String, Object?>{'refreshRateHz': 120})),
    );

    expect(
      () => BenchmarkLaunchConfiguration.parse(
        metadataBase64: metadata,
        outputPath: '/tmp/seeko-baseline.json',
        itemCount: '1000000',
        itemExtent: '56',
        warmUpSeconds: '5',
        minimumRunSeconds: '30',
        minimumPresentedFrames: '3600',
        runCount: '5',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
