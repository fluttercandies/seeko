import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification schema pins the macOS 120 Hz evidence contract', () {
    final Object? decoded = jsonDecode(
      File('schema/qualification-result.schema.json').readAsStringSync(),
    );
    final Map<String, Object?> schema = decoded! as Map<String, Object?>;
    expect(schema[r'$schema'], contains('2020-12'));
    final Map<String, Object?> properties =
        schema['properties']! as Map<String, Object?>;
    final Map<String, Object?> refreshRate =
        properties['refreshRateHz']! as Map<String, Object?>;
    expect(refreshRate['minimum'], 120);
    final List<Object?> required = schema['required']! as List<Object?>;
    expect(required, containsAll(<String>['thermalState', 'powerState']));
    final Map<String, Object?> runs =
        properties['runs']! as Map<String, Object?>;
    final Map<String, Object?> run = runs['items']! as Map<String, Object?>;
    final Map<String, Object?> runProperties =
        run['properties']! as Map<String, Object?>;
    final Map<String, Object?> samples =
        runProperties['samples']! as Map<String, Object?>;
    final Map<String, Object?> sample =
        samples['items']! as Map<String, Object?>;
    expect(
      sample['required'],
      containsAll(<String>[
        'frameNumber',
        'buildMicros',
        'rasterMicros',
        'totalMicros',
        'vsyncOverheadMicros',
      ]),
    );
  });

  test('motion schema freezes the full comparison and blind-review gates', () {
    final Object? decoded = jsonDecode(
      File('schema/motion-prototype-result.schema.json').readAsStringSync(),
    );
    final Map<String, Object?> schema = decoded! as Map<String, Object?>;
    final Map<String, Object?> properties =
        schema['properties']! as Map<String, Object?>;
    expect(
        (properties['matrixCaseCount']! as Map<String, Object?>)['const'], 120);
    expect(
      (properties['requiredBlindReviewers']! as Map<String, Object?>)['const'],
      5,
    );
    final Map<String, Object?> evaluations =
        properties['evaluations']! as Map<String, Object?>;
    expect(evaluations['minItems'], 3);
    expect(evaluations['maxItems'], 3);
    final Map<String, Object?> frameSample =
        schema[r'$defs']! as Map<String, Object?>;
    expect(frameSample, contains('frameSample'));
  });
}
