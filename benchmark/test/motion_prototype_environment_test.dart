import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/motion_prototype_environment.dart';

void main() {
  test('motion launch configuration decodes qualification metadata', () {
    final String metadata = base64Url.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'device': 'MacBookPro18,4 / Apple M1 Max / 32 GB',
          'operatingSystem': 'macOS 26.6 (25G72)',
          'thermalState': 'nominal',
          'powerState': 'AC / 80% / not charging',
          'refreshRateHz': 120,
          'flutterRevision': '559ffa3f75e7402d65a8def9c28389a9b2e6fe42',
          'engineRevision': '4c525dac5ebe5971c5708ef73558ed8edcf4a362',
          'buildMode': 'profile',
          'commit': 'unversioned-worktree',
          'seed': 24301,
          'scenario': 'motion-prototype-comparison',
        }),
      ),
    );

    final MotionPrototypeLaunchConfiguration launch =
        MotionPrototypeLaunchConfiguration.parse(
      metadataBase64: metadata,
      outputPath: '/tmp/seeko-motion.json',
      repeats: '1',
    );

    expect(launch.metadata.refreshRateHz, 120);
    expect(launch.metadata.scenario, 'motion-prototype-comparison');
    expect(launch.outputPath, '/tmp/seeko-motion.json');
    expect(launch.repeats, 1);
  });

  test('motion launch configuration rejects non-qualification displays', () {
    final String metadata = base64Url.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'device': 'device',
          'operatingSystem': 'os',
          'thermalState': 'nominal',
          'powerState': 'AC / 80%',
          'refreshRateHz': 60,
          'flutterRevision': '1234567',
          'engineRevision': '7654321',
          'buildMode': 'profile',
          'commit': 'test',
          'seed': 24301,
          'scenario': 'motion-prototype-comparison',
        }),
      ),
    );

    expect(
      () => MotionPrototypeLaunchConfiguration.parse(
        metadataBase64: metadata,
        outputPath: '/tmp/seeko-motion.json',
        repeats: '1',
      ),
      throwsFormatException,
    );
  });
}
