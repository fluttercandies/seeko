import 'dart:convert';
import 'dart:io';

typedef CoverageFileReader = Future<String> Function(String path);
typedef CoverageMessageWriter = void Function(String message);

final class CoverageSummary {
  const CoverageSummary({required this.foundLines, required this.hitLines});

  factory CoverageSummary.parse(String report) {
    int foundLines = 0;
    int hitLines = 0;
    bool foundLineTotal = false;
    bool foundHitTotal = false;

    for (final String line in const LineSplitter().convert(report)) {
      if (line.startsWith('LF:')) {
        foundLines += _parseLineTotal(line, 'LF');
        foundLineTotal = true;
      } else if (line.startsWith('LH:')) {
        hitLines += _parseLineTotal(line, 'LH');
        foundHitTotal = true;
      }
    }

    if (!foundLineTotal || !foundHitTotal || foundLines == 0) {
      throw const FormatException(
        'The report must contain non-zero LF and matching LH totals.',
      );
    }
    if (hitLines > foundLines) {
      throw FormatException(
        'Hit line total $hitLines exceeds found line total $foundLines.',
      );
    }
    return CoverageSummary(foundLines: foundLines, hitLines: hitLines);
  }

  final int foundLines;
  final int hitLines;

  double get percentage => hitLines * 100 / foundLines;

  static int _parseLineTotal(String line, String field) {
    final int? value = int.tryParse(line.substring(field.length + 1));
    if (value == null || value < 0) {
      throw FormatException('Invalid $field total: $line');
    }
    return value;
  }
}

Future<int> runCoverageGate(
  List<String> arguments, {
  CoverageFileReader? readFile,
  CoverageMessageWriter? writeOutput,
  CoverageMessageWriter? writeError,
}) async {
  final CoverageMessageWriter output = writeOutput ?? stdout.writeln;
  final CoverageMessageWriter errorOutput = writeError ?? stderr.writeln;

  late final _CoverageArguments parsed;
  try {
    parsed = _CoverageArguments.parse(arguments);
  } on FormatException catch (error) {
    errorOutput(error.message.toString());
    return 64;
  }

  late final String report;
  try {
    report = await (readFile ?? _readCoverageFile)(parsed.path);
  } on FileSystemException catch (error) {
    errorOutput('Unable to read ${parsed.path}: ${error.message}');
    return 66;
  }

  late final CoverageSummary summary;
  try {
    summary = CoverageSummary.parse(report);
  } on FormatException catch (error) {
    errorOutput('Invalid lcov report: ${error.message}');
    return 65;
  }

  final String measured = summary.percentage.toStringAsFixed(2);
  final String minimum = parsed.minimum.toStringAsFixed(2);
  final String counts = '${summary.hitLines}/${summary.foundLines} lines';
  if (summary.percentage < parsed.minimum) {
    errorOutput(
      'Line coverage $measured% ($counts) is below minimum $minimum%.',
    );
    return 1;
  }

  output('Line coverage $measured% ($counts) meets minimum $minimum%.');
  return 0;
}

Future<String> _readCoverageFile(String path) => File(path).readAsString();

final class _CoverageArguments {
  const _CoverageArguments({required this.minimum, required this.path});

  factory _CoverageArguments.parse(List<String> arguments) {
    if (arguments.length != 3 || arguments.first != '--minimum') {
      throw const FormatException(
        'Usage: dart run tool/check_coverage.dart '
        '--minimum <0..100> <lcov-file>',
      );
    }
    final double? minimum = double.tryParse(arguments[1]);
    if (minimum == null || !minimum.isFinite || minimum < 0 || minimum > 100) {
      throw const FormatException(
          'Coverage minimum must be between 0 and 100.');
    }
    return _CoverageArguments(minimum: minimum, path: arguments[2]);
  }

  final double minimum;
  final String path;
}

Future<void> main(List<String> arguments) async {
  exitCode = await runCoverageGate(arguments);
}
