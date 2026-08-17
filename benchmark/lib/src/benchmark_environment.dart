import 'dart:convert';

import 'benchmark_models.dart';

final class BenchmarkLaunchConfiguration {
  const BenchmarkLaunchConfiguration._({
    required this.metadata,
    required this.configuration,
    required this.outputPath,
  });

  factory BenchmarkLaunchConfiguration.fromCompileTimeEnvironment() {
    return BenchmarkLaunchConfiguration.parse(
      metadataBase64: const String.fromEnvironment(
        'SEEKO_BENCHMARK_METADATA_BASE64',
      ),
      outputPath: const String.fromEnvironment('SEEKO_BENCHMARK_OUTPUT'),
      itemCount: const String.fromEnvironment(
        'SEEKO_BENCHMARK_ITEM_COUNT',
        defaultValue: '1000000',
      ),
      itemExtent: const String.fromEnvironment(
        'SEEKO_BENCHMARK_ITEM_EXTENT',
        defaultValue: '56',
      ),
      warmUpSeconds: const String.fromEnvironment(
        'SEEKO_BENCHMARK_WARMUP_SECONDS',
        defaultValue: '5',
      ),
      minimumRunSeconds: const String.fromEnvironment(
        'SEEKO_BENCHMARK_MINIMUM_RUN_SECONDS',
        defaultValue: '30',
      ),
      minimumPresentedFrames: const String.fromEnvironment(
        'SEEKO_BENCHMARK_MINIMUM_PRESENTED_FRAMES',
        defaultValue: '3600',
      ),
      runCount: const String.fromEnvironment(
        'SEEKO_BENCHMARK_RUN_COUNT',
        defaultValue: '5',
      ),
    );
  }

  factory BenchmarkLaunchConfiguration.parse({
    required String metadataBase64,
    required String outputPath,
    required String itemCount,
    required String itemExtent,
    required String warmUpSeconds,
    required String minimumRunSeconds,
    required String minimumPresentedFrames,
    required String runCount,
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
          'Benchmark metadata is not valid base64 JSON.', error);
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
    final BenchmarkQualificationMetadata metadata =
        BenchmarkQualificationMetadata(
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
    );
    final int parsedItemCount = _parseInt(itemCount, 'itemCount');
    final double parsedItemExtent = _parseDouble(itemExtent, 'itemExtent');
    final double parsedWarmUp = _parseDouble(warmUpSeconds, 'warmUpSeconds');
    final double parsedMinimumRun = _parseDouble(
      minimumRunSeconds,
      'minimumRunSeconds',
    );
    final int parsedMinimumFrames = _parseInt(
      minimumPresentedFrames,
      'minimumPresentedFrames',
    );
    final int parsedRunCount = _parseInt(runCount, 'runCount');
    return BenchmarkLaunchConfiguration._(
      metadata: metadata,
      configuration: BenchmarkScenarioConfiguration(
        itemCount: parsedItemCount,
        itemExtent: parsedItemExtent,
        warmUp: _seconds(parsedWarmUp, 'warmUpSeconds'),
        minimumRunDuration: _seconds(
          parsedMinimumRun,
          'minimumRunSeconds',
        ),
        minimumPresentedFrames: parsedMinimumFrames,
        runCount: parsedRunCount,
      ),
      outputPath: outputPath,
    );
  }

  final BenchmarkQualificationMetadata metadata;
  final BenchmarkScenarioConfiguration configuration;
  final String outputPath;
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException(
        'Benchmark metadata $key must be a non-empty string.');
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

int _parseInt(String value, String name) {
  final int? parsed = int.tryParse(value);
  if (parsed == null) {
    throw FormatException('$name must be an integer; got $value.');
  }
  return parsed;
}

double _parseDouble(String value, String name) {
  final double? parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('$name must be finite; got $value.');
  }
  return parsed;
}

Duration _seconds(double value, String name) {
  if (value <= 0) {
    throw FormatException('$name must be positive; got $value.');
  }
  return Duration(
      microseconds: (value * Duration.microsecondsPerSecond).round());
}
