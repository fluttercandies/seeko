import 'dart:io';

Future<void> main() async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('The G6 qualification runner currently uses macOS.');
  }
  final Directory benchmarkDirectory =
      File.fromUri(Platform.script).parent.parent;
  await _run(
    'flutter',
    const <String>[
      'build',
      'macos',
      '--release',
      '-t',
      'lib/g6_core_main.dart',
    ],
    workingDirectory: benchmarkDirectory.path,
  );
  final String executable = <String>[
    benchmarkDirectory.path,
    'build',
    'macos',
    'Build',
    'Products',
    'Release',
    'seeko_benchmark.app',
    'Contents',
    'MacOS',
    'seeko_benchmark',
  ].join(Platform.pathSeparator);
  await _run(
    executable,
    const <String>[],
    workingDirectory: benchmarkDirectory.path,
  );
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: Platform.environment,
    mode: ProcessStartMode.inheritStdio,
  );
  final int exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, '', exitCode);
  }
}
