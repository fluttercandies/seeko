import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:seeko_benchmark/src/g6_core_benchmark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isMacOS) {
    throw UnsupportedError('The G6 qualification runner currently uses macOS.');
  }
  final G6CoreBenchmarkResult result = runG6CoreBenchmark(
    warmUpIterations: _positiveEnvironmentInteger(
      'SEEKO_G6_WARMUP_ITERATIONS',
      fallback: 10000,
    ),
    measuredIterations: _positiveEnvironmentInteger(
      'SEEKO_G6_MEASURED_ITERATIONS',
      fallback: 100000,
    ),
    openItemCount: _positiveEnvironmentInteger(
      'SEEKO_G6_OPEN_ITEM_COUNT',
      fallback: 100000,
    ),
  );
  final DateTime timestamp = DateTime.now().toUtc();
  final Map<String, Object?> payload = <String, Object?>{
    'timestamp': timestamp.toIso8601String(),
    'platform': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'dartVersion': Platform.version,
    'benchmark': result.toJson(),
  };
  final Directory outputDirectory = Directory(
    Platform.environment['SEEKO_G6_RESULTS_DIRECTORY'] ??
        '${Directory.current.path}${Platform.pathSeparator}results',
  );
  await outputDirectory.create(recursive: true);
  final String stamp = timestamp.toIso8601String().replaceAll(':', '-');
  final File output = File(
    '${outputDirectory.path}${Platform.pathSeparator}g6-core-$stamp.json',
  );
  final String encoded = const JsonEncoder.withIndent('  ').convert(payload);
  await output.writeAsString('$encoded\n', flush: true);
  stdout.writeln(encoded);
  stdout.writeln('Result: ${output.path}');
  await ServicesBinding.instance.exitApplication(ui.AppExitType.required);
  exit(0);
}

int _positiveEnvironmentInteger(String name, {required int fallback}) {
  final String? raw = Platform.environment[name];
  if (raw == null) return fallback;
  final int? value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw ArgumentError.value(raw, name, 'must be a positive integer');
  }
  return value;
}
