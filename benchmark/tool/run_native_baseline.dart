import 'dart:convert';
import 'dart:io';

import 'package:seeko_benchmark/src/benchmark_host.dart';

const int _seed = 24301;
const String _scenario = 'native-list-view-builder-fixed-extent';

Future<void> main() async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('The release qualification baseline runs on macOS.');
  }
  final Directory benchmarkDirectory =
      File.fromUri(Platform.script).parent.parent;
  final Directory macosDirectory = Directory(
    '${benchmarkDirectory.path}${Platform.pathSeparator}macos',
  );
  if (!macosDirectory.existsSync()) {
    throw StateError(
      'The benchmark macOS runner is missing. Generate the standard Flutter '
      'platform shell before collecting a baseline.',
    );
  }

  final String systemProfile = await _checkedOutput(
    'system_profiler',
    <String>[
      'SPHardwareDataType',
      'SPDisplaysDataType',
      'SPSoftwareDataType',
      '-json',
    ],
  );
  final String flutterVersion = await _checkedOutput(
    'flutter',
    <String>['--version', '--machine'],
  );
  final String batteryStatus = await _checkedOutput(
    'pmset',
    <String>['-g', 'batt'],
  );
  final String thermalStatus = await _checkedOutput(
    'pmset',
    <String>['-g', 'therm'],
  );
  final BenchmarkHostSnapshot host = BenchmarkHostSnapshot.parse(
    systemProfileJson: systemProfile,
    flutterVersionJson: flutterVersion,
    batteryStatus: batteryStatus,
    thermalStatus: thermalStatus,
  );
  _validateQualificationState(host);
  final String commit = await _resolveCommit(benchmarkDirectory.parent.path);
  final Map<String, Object?> metadata = <String, Object?>{
    ...host.toJson(),
    'buildMode': 'profile',
    'commit': commit,
    'seed': _seed,
    'scenario': _scenario,
  };
  final String metadataBase64 = base64Url.encode(
    utf8.encode(jsonEncode(metadata)),
  );
  final File temporaryOutput = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'seeko-native-baseline-$pid.json',
  );
  if (temporaryOutput.existsSync()) {
    await temporaryOutput.delete();
  }

  stdout.writeln(
      'Collecting native ListView.builder baseline on ${host.device}.');
  stdout.writeln(
    'Protocol: 5 profile runs, each at least 30 seconds and 3600 presented frames.',
  );
  final Process process = await Process.start(
    'flutter',
    <String>[
      'run',
      '-d',
      'macos',
      '--profile',
      '--target',
      'lib/main.dart',
      '--dart-define=SEEKO_BENCHMARK_METADATA_BASE64=$metadataBase64',
      '--dart-define=SEEKO_BENCHMARK_OUTPUT=${temporaryOutput.path}',
      '--dart-define=SEEKO_BENCHMARK_ITEM_COUNT=1000000',
      '--dart-define=SEEKO_BENCHMARK_ITEM_EXTENT=56',
      '--dart-define=SEEKO_BENCHMARK_WARMUP_SECONDS=5',
      '--dart-define=SEEKO_BENCHMARK_MINIMUM_RUN_SECONDS=30',
      '--dart-define=SEEKO_BENCHMARK_MINIMUM_PRESENTED_FRAMES=3600',
      '--dart-define=SEEKO_BENCHMARK_RUN_COUNT=5',
    ],
    workingDirectory: benchmarkDirectory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final int exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
      'flutter',
      const <String>['run', '-d', 'macos', '--profile'],
      'Benchmark application exited with code $exitCode.',
      exitCode,
    );
  }
  if (!temporaryOutput.existsSync()) {
    throw StateError(
      'Benchmark application exited without writing ${temporaryOutput.path}.',
    );
  }
  final Object? decoded = jsonDecode(await temporaryOutput.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Benchmark result must be a JSON object.');
  }
  _validateResult(decoded);

  final DateTime now = DateTime.now().toUtc();
  final String stamp = now.toIso8601String().replaceAll(':', '-');
  final Directory resultsDirectory = Directory(
    '${benchmarkDirectory.path}${Platform.pathSeparator}results',
  );
  await resultsDirectory.create(recursive: true);
  final String baseName = 'native-list-view-builder-$stamp';
  final File resultFile = File(
    '${resultsDirectory.path}${Platform.pathSeparator}$baseName.json',
  );
  final File reportFile = File(
    '${resultsDirectory.path}${Platform.pathSeparator}$baseName.md',
  );
  await resultFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
    flush: true,
  );
  await reportFile.writeAsString(
    _markdownReport(decoded, resultFile.path),
    flush: true,
  );
  await temporaryOutput.delete();
  stdout.writeln('Result: ${resultFile.path}');
  stdout.writeln('Report: ${reportFile.path}');
}

Future<String> _checkedOutput(String executable, List<String> arguments) async {
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

void _validateQualificationState(BenchmarkHostSnapshot host) {
  if (host.thermalState != 'nominal') {
    throw StateError(
      'Thermal state must be nominal before qualification; got '
      '${host.thermalState}.',
    );
  }
  if (!host.powerState.startsWith('AC /')) {
    throw StateError(
      'Qualification device must be connected to AC power; got '
      '${host.powerState}.',
    );
  }
  final RegExpMatch? battery = RegExp(r'AC / (\d+)%').firstMatch(
    host.powerState,
  );
  if (battery == null || int.parse(battery.group(1)!) < 50) {
    throw StateError(
      'Qualification battery must be at least 50%; got ${host.powerState}.',
    );
  }
}

Future<String> _resolveCommit(String workspacePath) async {
  final ProcessResult result = await Process.run(
    'git',
    <String>['rev-parse', 'HEAD'],
    workingDirectory: workspacePath,
  );
  if (result.exitCode != 0) {
    return 'unversioned-worktree';
  }
  final String value = result.stdout.toString().trim();
  return value.isEmpty ? 'unversioned-worktree' : value;
}

void _validateResult(Map<String, Object?> result) {
  if (result['error'] != null) {
    throw StateError('Benchmark application failed: ${result['error']}');
  }
  final Object? runsValue = result['runs'];
  if (runsValue is! List<Object?> || runsValue.length != 5) {
    throw FormatException('Benchmark result must contain exactly five runs.');
  }
  for (var index = 0; index < runsValue.length; index += 1) {
    final Object? value = runsValue[index];
    if (value is! Map<String, Object?>) {
      throw FormatException('Benchmark run ${index + 1} must be an object.');
    }
    final Object? frames = value['presentedFrames'];
    final Object? elapsedMicros = value['elapsedMicros'];
    if (frames is! int || frames < 3600) {
      throw FormatException(
        'Benchmark run ${index + 1} has fewer than 3600 frames.',
      );
    }
    if (elapsedMicros is! int ||
        elapsedMicros < const Duration(seconds: 30).inMicroseconds) {
      throw FormatException(
        'Benchmark run ${index + 1} is shorter than 30 seconds.',
      );
    }
  }
}

String _markdownReport(Map<String, Object?> result, String resultPath) {
  final List<Object?> runs = result['runs']! as List<Object?>;
  final List<Map<String, Object?>> typedRuns =
      runs.cast<Map<String, Object?>>().toList(growable: false)
        ..sort((Map<String, Object?> a, Map<String, Object?> b) {
          final Map<String, Object?> aTotal =
              a['totalMicros']! as Map<String, Object?>;
          final Map<String, Object?> bTotal =
              b['totalMicros']! as Map<String, Object?>;
          return (aTotal['p99']! as int).compareTo(bTotal['p99']! as int);
        });
  final int medianRun = typedRuns[typedRuns.length ~/ 2]['run']! as int;
  final StringBuffer buffer = StringBuffer()
    ..writeln('# Native ListView.builder baseline')
    ..writeln()
    ..writeln('- Device: ${result['device']}')
    ..writeln('- OS: ${result['operatingSystem']}')
    ..writeln('- Display: ${result['refreshRateHz']} Hz')
    ..writeln('- Flutter: ${result['flutterRevision']}')
    ..writeln('- Engine: ${result['engineRevision']}')
    ..writeln('- Thermal: ${result['thermalState']}')
    ..writeln('- Power: ${result['powerState']}')
    ..writeln('- Raw result: `$resultPath`')
    ..writeln('- Median run by total-span P99: $medianRun')
    ..writeln()
    ..writeln(
      '| Run | Frames | Build P95/P99 ms | Raster P95/P99 ms | '
      '<=8.333 ms | <=16.667 ms | Child builds |',
    )
    ..writeln('| ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final Object? value in runs) {
    final Map<String, Object?> run = value! as Map<String, Object?>;
    final Map<String, Object?> build =
        run['buildMicros']! as Map<String, Object?>;
    final Map<String, Object?> raster =
        run['rasterMicros']! as Map<String, Object?>;
    buffer.writeln(
      '| ${run['run']} | ${run['presentedFrames']} | '
      '${_millis(build['p95'])}/${_millis(build['p99'])} | '
      '${_millis(raster['p95'])}/${_millis(raster['p99'])} | '
      '${_percent(run['within8333Ratio'])} | '
      '${_percent(run['within16667Ratio'])} | ${run['childBuilds']} |',
    );
  }
  return buffer.toString();
}

String _millis(Object? micros) =>
    ((micros! as int) / Duration.microsecondsPerMillisecond).toStringAsFixed(3);

String _percent(Object? ratio) =>
    '${((ratio! as num).toDouble() * 100).toStringAsFixed(3)}%';
