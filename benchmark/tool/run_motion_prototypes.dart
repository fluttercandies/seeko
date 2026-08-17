import 'dart:convert';
import 'dart:io';

import 'package:seeko_benchmark/src/benchmark_host.dart';
import 'package:seeko_benchmark/src/motion_prototype_result_contract.dart';

const int _seed = 24301;
const String _scenario = 'motion-prototype-comparison';
const int _repeats = 1;

Future<void> main() async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'Long-distance motion qualification runs on macOS.',
    );
  }
  final Directory benchmarkDirectory =
      File.fromUri(Platform.script).parent.parent;
  final Directory macosDirectory = Directory(
    '${benchmarkDirectory.path}${Platform.pathSeparator}macos',
  );
  if (!macosDirectory.existsSync()) {
    throw StateError('The benchmark macOS platform shell is missing.');
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
      <String>['--version', '--machine'],
    ),
    batteryStatus: await _checkedOutput('pmset', <String>['-g', 'batt']),
    thermalStatus: await _checkedOutput('pmset', <String>['-g', 'therm']),
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
  final String temporaryPrefix =
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'seeko-motion-prototypes-$pid';
  final File temporaryOutput = File('$temporaryPrefix.json');
  final File temporaryLog = File('$temporaryPrefix.log');
  for (final File file in <File>[temporaryOutput, temporaryLog]) {
    if (file.existsSync()) {
      await file.delete();
    }
  }

  stdout
      .writeln('Comparing long-distance motion prototypes on ${host.device}.');
  stdout.writeln(
    'Matrix: 120 cases per candidate; bounded source/destination windows; '
    'no intermediate-item traversal.',
  );
  final Process process = await Process.start(
    'flutter',
    <String>[
      'run',
      '-d',
      'macos',
      '--profile',
      '--target',
      'lib/motion_prototype_main.dart',
      '--dart-define=SEEKO_BENCHMARK_METADATA_BASE64=$metadataBase64',
      '--dart-define=SEEKO_BENCHMARK_OUTPUT=${temporaryOutput.path}',
      '--dart-define=SEEKO_MOTION_PROTOTYPE_REPEATS=$_repeats',
    ],
    workingDirectory: benchmarkDirectory.path,
  );
  final IOSink logSink = temporaryLog.openWrite();
  final Future<void> stdoutDone =
      process.stdout.transform(utf8.decoder).forEach((String chunk) {
    stdout.write(chunk);
    logSink.write(chunk);
  });
  final Future<void> stderrDone =
      process.stderr.transform(utf8.decoder).forEach((String chunk) {
    stderr.write(chunk);
    logSink.write(chunk);
  });
  final int exitCode = await process.exitCode;
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  await logSink.flush();
  await logSink.close();
  if (exitCode != 0) {
    throw ProcessException(
      'flutter',
      const <String>[
        'run',
        '-d',
        'macos',
        '--profile',
        '--target',
        'lib/motion_prototype_main.dart',
      ],
      'Motion prototype application exited with code $exitCode. '
          'Console log: ${temporaryLog.path}',
      exitCode,
    );
  }
  if (!temporaryOutput.existsSync()) {
    throw StateError(
      'Motion prototype application did not write ${temporaryOutput.path}.',
    );
  }
  final Object? decoded = jsonDecode(await temporaryOutput.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Motion result must be a JSON object.');
  }
  MotionPrototypeResultContract.validate(decoded, repeats: _repeats);

  final DateTime now = DateTime.now().toUtc();
  final String stamp = now.toIso8601String().replaceAll(':', '-');
  final Directory resultsDirectory = Directory(
    '${benchmarkDirectory.path}${Platform.pathSeparator}results',
  );
  await resultsDirectory.create(recursive: true);
  final String baseName = 'motion-prototype-comparison-$stamp';
  final File resultFile = File(
    '${resultsDirectory.path}${Platform.pathSeparator}$baseName.json',
  );
  final File reportFile = File(
    '${resultsDirectory.path}${Platform.pathSeparator}$baseName.md',
  );
  final File logFile = File(
    '${resultsDirectory.path}${Platform.pathSeparator}$baseName.log',
  );
  await temporaryOutput.copy(resultFile.path);
  await temporaryLog.copy(logFile.path);
  await reportFile.writeAsString(
    '${MotionPrototypeResultContract.markdownReport(
      decoded,
      rawResultPath: resultFile.path,
    )}\n- Console log: `${logFile.path}`\n',
    flush: true,
  );
  await temporaryOutput.delete();
  await temporaryLog.delete();
  stdout.writeln('Result: ${resultFile.path}');
  stdout.writeln('Report: ${reportFile.path}');
  stdout.writeln('Console log: ${logFile.path}');
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
      'Thermal state must be nominal; got ${host.thermalState}.',
    );
  }
  if (!host.powerState.startsWith('AC /')) {
    throw StateError(
      'Qualification device must use AC power; got ${host.powerState}.',
    );
  }
  final RegExpMatch? battery =
      RegExp(r'AC / (\d+)%').firstMatch(host.powerState);
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
