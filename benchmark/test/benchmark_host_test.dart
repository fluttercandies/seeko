import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/benchmark_host.dart';

void main() {
  test('host probe keeps reproducibility fields and drops device identifiers',
      () {
    final String profile = jsonEncode(<String, Object?>{
      'SPHardwareDataType': <Object?>[
        <String, Object?>{
          'machine_model': 'MacBookPro18,4',
          'chip_type': 'Apple M1 Max',
          'physical_memory': '32 GB',
          'serial_number': 'must-not-leak',
        },
      ],
      'SPDisplaysDataType': <Object?>[
        <String, Object?>{
          'spdisplays_ndrvs': <Object?>[
            <String, Object?>{
              'spdisplays_main': 'spdisplays_yes',
              '_spdisplays_resolution': '1512 x 982 @ 120.00Hz',
              '_spdisplays_display-serial-number': 'must-not-leak',
            },
          ],
        },
      ],
      'SPSoftwareDataType': <Object?>[
        <String, Object?>{'os_version': 'macOS 26.6 (25G72)'},
      ],
    });
    final String flutter = jsonEncode(<String, Object?>{
      'frameworkRevision': '559ffa3f75e7402d65a8def9c28389a9b2e6fe42',
      'engineRevision': '4c525dac5ebe5971c5708ef73558ed8edcf4a362',
    });

    final BenchmarkHostSnapshot snapshot = BenchmarkHostSnapshot.parse(
      systemProfileJson: profile,
      flutterVersionJson: flutter,
      batteryStatus:
          "Now drawing from 'AC Power'\n -InternalBattery-0\t80%; AC attached; not charging present: true",
      thermalStatus:
          'Note: No thermal warning level has been recorded\nNote: No performance warning level has been recorded',
    );

    expect(snapshot.device, 'MacBookPro18,4 / Apple M1 Max / 32 GB');
    expect(snapshot.operatingSystem, 'macOS 26.6 (25G72)');
    expect(snapshot.refreshRateHz, 120);
    expect(snapshot.powerState, 'AC / 80% / not charging');
    expect(snapshot.thermalState, 'nominal');
    expect(snapshot.flutterRevision, startsWith('559ffa3'));
    expect(snapshot.engineRevision, startsWith('4c525da'));
    expect(jsonEncode(snapshot.toJson()), isNot(contains('must-not-leak')));
  });

  test('host probe rejects a display below the qualification refresh rate', () {
    final String profile = jsonEncode(<String, Object?>{
      'SPHardwareDataType': <Object?>[
        <String, Object?>{
          'machine_model': 'MacBookPro18,4',
          'chip_type': 'Apple M1 Max',
          'physical_memory': '32 GB',
        },
      ],
      'SPDisplaysDataType': <Object?>[
        <String, Object?>{
          'spdisplays_ndrvs': <Object?>[
            <String, Object?>{
              'spdisplays_main': 'spdisplays_yes',
              '_spdisplays_resolution': '1512 x 982 @ 60.00Hz',
            },
          ],
        },
      ],
      'SPSoftwareDataType': <Object?>[
        <String, Object?>{'os_version': 'macOS 26.6 (25G72)'},
      ],
    });

    expect(
      () => BenchmarkHostSnapshot.parse(
        systemProfileJson: profile,
        flutterVersionJson: jsonEncode(<String, Object?>{
          'frameworkRevision': '1234567',
          'engineRevision': '7654321',
        }),
        batteryStatus: 'AC Power 80%',
        thermalStatus: 'No thermal warning level has been recorded',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
