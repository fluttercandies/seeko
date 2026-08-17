import 'dart:convert';

import 'benchmark_models.dart';

final class MotionPrototypeLaunchConfiguration {
  const MotionPrototypeLaunchConfiguration._({
    required this.metadata,
    required this.outputPath,
    required this.repeats,
  });

  factory MotionPrototypeLaunchConfiguration.fromCompileTimeEnvironment() {
    return MotionPrototypeLaunchConfiguration.parse(
      metadataBase64: const String.fromEnvironment(
        'SEEKO_BENCHMARK_METADATA_BASE64',
      ),
      outputPath: const String.fromEnvironment('SEEKO_BENCHMARK_OUTPUT'),
      repeats: const String.fromEnvironment(
        'SEEKO_MOTION_PROTOTYPE_REPEATS',
        defaultValue: '1',
      ),
    );
  }

  factory MotionPrototypeLaunchConfiguration.parse({
    required String metadataBase64,
    required String outputPath,
    required String repeats,
  }) {
    if (metadataBase64.isEmpty) {
      throw const FormatException('Benchmark metadata is required.');
    }
    if (outputPath.isEmpty) {
      throw const FormatException('Benchmark output path is required.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(metadataBase64))),
      );
    } on Object catch (error) {
      throw FormatException(
        'Benchmark metadata is not valid base64 JSON.',
        error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Benchmark metadata must be a JSON object.');
    }
    final double refreshRateHz = _requiredDouble(decoded, 'refreshRateHz');
    if (refreshRateHz < 120) {
      throw FormatException(
        'Benchmark refreshRateHz must be at least 120; got $refreshRateHz.',
      );
    }
    final String buildMode = _requiredString(decoded, 'buildMode');
    if (buildMode != 'profile' && buildMode != 'release') {
      throw FormatException(
        'Benchmark buildMode must be profile or release; got $buildMode.',
      );
    }
    final int parsedRepeats = int.tryParse(repeats) ?? -1;
    if (parsedRepeats < 1 || parsedRepeats > 5) {
      throw FormatException('repeats must be inside [1, 5]; got $repeats.');
    }
    return MotionPrototypeLaunchConfiguration._(
      metadata: BenchmarkQualificationMetadata(
        device: _requiredString(decoded, 'device'),
        operatingSystem: _requiredString(decoded, 'operatingSystem'),
        thermalState: _requiredString(decoded, 'thermalState'),
        powerState: _requiredString(decoded, 'powerState'),
        refreshRateHz: refreshRateHz,
        flutterRevision: _requiredString(decoded, 'flutterRevision'),
        engineRevision: _requiredString(decoded, 'engineRevision'),
        buildMode: buildMode,
        commit: _requiredString(decoded, 'commit'),
        seed: _requiredInt(decoded, 'seed'),
        scenario: _requiredString(decoded, 'scenario'),
      ),
      outputPath: outputPath,
      repeats: parsedRepeats,
    );
  }

  final BenchmarkQualificationMetadata metadata;
  final String outputPath;
  final int repeats;
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Benchmark metadata $key must be a non-empty string.',
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('Benchmark metadata $key must be an integer.');
  }
  return value;
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! num) {
    throw FormatException('Benchmark metadata $key must be numeric.');
  }
  final double result = value.toDouble();
  if (!result.isFinite) {
    throw FormatException('Benchmark metadata $key must be finite.');
  }
  return result;
}
