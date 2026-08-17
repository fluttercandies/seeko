import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_coverage.dart';

void main() {
  group('CoverageSummary', () {
    test('aggregates line totals across lcov records', () {
      const String report = '''
SF:lib/first.dart
LF:8
LH:6
end_of_record
SF:lib/second.dart
LF:4
LH:3
end_of_record
''';

      final CoverageSummary summary = CoverageSummary.parse(report);

      expect(summary.foundLines, 12);
      expect(summary.hitLines, 9);
      expect(summary.percentage, 75);
    });

    test('rejects reports without line coverage data', () {
      expect(
        () => CoverageSummary.parse('TN:\nend_of_record\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('runCoverageGate', () {
    test('passes when measured coverage meets the minimum', () async {
      final List<String> output = <String>[];

      final int result = await runCoverageGate(
        <String>['--minimum', '85', 'coverage/lcov.info'],
        readFile: (_) async => 'LF:100\nLH:86\n',
        writeOutput: output.add,
      );

      expect(result, 0);
      expect(output.single, contains('86.00%'));
      expect(output.single, contains('minimum 85.00%'));
    });

    test('fails when measured coverage is below the minimum', () async {
      final List<String> errors = <String>[];

      final int result = await runCoverageGate(
        <String>['--minimum', '85', 'coverage/lcov.info'],
        readFile: (_) async => 'LF:100\nLH:84\n',
        writeError: errors.add,
      );

      expect(result, 1);
      expect(errors.single, contains('84.00%'));
      expect(errors.single, contains('below minimum 85.00%'));
    });

    test('rejects an invalid minimum without reading the report', () async {
      bool readAttempted = false;
      final List<String> errors = <String>[];

      final int result = await runCoverageGate(
        <String>['--minimum', '101', 'coverage/lcov.info'],
        readFile: (_) async {
          readAttempted = true;
          return '';
        },
        writeError: errors.add,
      );

      expect(result, 64);
      expect(readAttempted, isFalse);
      expect(errors.single, contains('between 0 and 100'));
    });

    test('reports malformed lcov data as a data error', () async {
      final List<String> errors = <String>[];

      final int result = await runCoverageGate(
        <String>['--minimum', '85', 'coverage/lcov.info'],
        readFile: (_) async => 'LF:not-a-number\nLH:4\n',
        writeError: errors.add,
      );

      expect(result, 65);
      expect(errors.single, contains('Invalid lcov report'));
    });

    test('reports an unreadable coverage file without a stack trace', () async {
      final List<String> errors = <String>[];

      final int result = await runCoverageGate(
        <String>['--minimum', '85', 'coverage/lcov.info'],
        readFile: (_) async => throw FileSystemException('not found'),
        writeError: errors.add,
      );

      expect(result, 66);
      expect(errors.single, contains('Unable to read coverage/lcov.info'));
    });
  });
}
