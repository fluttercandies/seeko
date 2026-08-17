import 'dart:convert';
import 'dart:io';

import 'package:seeko_benchmark/src/benchmark_host.dart';
import 'package:seeko_benchmark/src/scroll_sync_coordinator_benchmark.dart';

const double _p95LimitMicros = 1000;
const double _p99LimitMicros = 1500;

Future<void> main() async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'The release coordinator qualification currently runs on macOS.',
    );
  }
  final BenchmarkHostSnapshot host = BenchmarkHostSnapshot.parse(
    systemProfileJson: await _checkedOutput(
      'system_profiler',
      <String>[
        'SPHardwareDataType',
        'SPDisplaysDataType',
        'SPSoftwareDataType',
        '-json',
      ],
    ),
    flutterVersionJson: await _checkedOutput(
      'flutter',
      const <String>['--version', '--machine'],
    ),
    batteryStatus: await _checkedOutput(
      'pmset',
      const <String>['-g', 'batt'],
    ),
    thermalStatus: await _checkedOutput(
      'pmset',
      const <String>['-g', 'therm'],
    ),
  );
  final int warmUpIterations = _positiveEnvironmentInteger(
    'SEEKO_SYNC_WARMUP_ITERATIONS',
    fallback: 10000,
  );
  final int measuredIterations = _positiveEnvironmentInteger(
    'SEEKO_SYNC_MEASURED_ITERATIONS',
    fallback: 100000,
  );
  final ScrollSyncCoordinatorBenchmarkResult result =
      runScrollSyncCoordinatorBenchmark(
    warmUpIterations: warmUpIterations,
    measuredIterations: measuredIterations,
  );
  final ScrollSyncCoordinatorBenchmarkSample sample32 =
      result.samples.singleWhere(
    (ScrollSyncCoordinatorBenchmarkSample sample) => sample.memberCount == 32,
  );
  final RegExpMatch? batteryMatch = RegExp(
    r'AC / (\d+)%',
  ).firstMatch(host.powerState);
  final bool environmentQualified = host.thermalState == 'nominal' &&
      batteryMatch != null &&
      int.parse(batteryMatch.group(1)!) >= 50;
  final bool passed = environmentQualified &&
      sample32.p95Micros <= _p95LimitMicros &&
      sample32.p99Micros <= _p99LimitMicros;
  final DateTime timestamp = DateTime.now().toUtc();
  final Map<String, Object?> payload = <String, Object?>{
    'schemaVersion': 1,
    'timestamp': timestamp.toIso8601String(),
    'platform': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'dartVersion': Platform.version,
    ...host.toJson(),
    'buildMode': result.toJson()['runtime'],
    'qualification': <String, Object?>{
      'memberCount': 32,
      'p95LimitMicros': _p95LimitMicros,
      'p99LimitMicros': _p99LimitMicros,
      'environmentQualified': environmentQualified,
      'passed': passed,
    },
    'benchmark': result.toJson(),
  };
  final Directory benchmarkDirectory =
      File.fromUri(Platform.script).parent.parent;
  final String? configuredResultsDirectory =
      Platform.environment['SEEKO_SYNC_RESULTS_DIRECTORY'];
  final Directory resultsDirectory = configuredResultsDirectory == null
      ? Directory(
          '${benchmarkDirectory.path}${Platform.pathSeparator}results',
        )
      : Directory(configuredResultsDirectory);
  await resultsDirectory.create(recursive: true);
  final String stamp = timestamp.toIso8601String().replaceAll(':', '-');
  final File output = File(
    '${resultsDirectory.path}${Platform.pathSeparator}'
    'scroll-sync-coordinator-$stamp.json',
  );
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    flush: true,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
  stdout.writeln('Result: ${output.path}');
  if (!passed) {
    throw StateError(
      '32-member coordinator exceeded the qualification limits: '
      'P95=${sample32.p95Micros.toStringAsFixed(3)} us, '
      'P99=${sample32.p99Micros.toStringAsFixed(3)} us.',
    );
  }
}

Future<String> _checkedOutput(
  String executable,
  List<String> arguments,
) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout.toString();
}

int _positiveEnvironmentInteger(String name, {required int fallback}) {
  final String? raw = Platform.environment[name];
  if (raw == null) {
    return fallback;
  }
  final int? value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw FormatException('$name must be a positive integer; got "$raw".');
  }
  return value;
}
