import 'dart:convert';

final class BenchmarkHostSnapshot {
  const BenchmarkHostSnapshot._({
    required this.device,
    required this.operatingSystem,
    required this.thermalState,
    required this.powerState,
    required this.refreshRateHz,
    required this.flutterRevision,
    required this.engineRevision,
  });

  factory BenchmarkHostSnapshot.parse({
    required String systemProfileJson,
    required String flutterVersionJson,
    required String batteryStatus,
    required String thermalStatus,
  }) {
    final Map<String, Object?> profile = _decodeObject(
      systemProfileJson,
      'system_profiler',
    );
    final Map<String, Object?> flutter = _decodeObject(
      flutterVersionJson,
      'flutter --version --machine',
    );
    final Map<String, Object?> hardware = _firstObject(
      profile,
      'SPHardwareDataType',
    );
    final Map<String, Object?> software = _firstObject(
      profile,
      'SPSoftwareDataType',
    );
    final Map<String, Object?> display = _mainDisplay(profile);
    final String resolution = _requiredString(
      display,
      '_spdisplays_resolution',
    );
    final RegExpMatch? refreshMatch = RegExp(
      r'@\s*([0-9]+(?:\.[0-9]+)?)Hz',
    ).firstMatch(resolution);
    if (refreshMatch == null) {
      throw FormatException(
        'Main display resolution does not report a refresh rate: $resolution',
      );
    }
    final double refreshRateHz = double.parse(refreshMatch.group(1)!);
    if (refreshRateHz < 120) {
      throw StateError(
        'The main display must run at 120 Hz or higher; got '
        '$refreshRateHz Hz.',
      );
    }
    final String model = _requiredString(hardware, 'machine_model');
    final String chip = _requiredString(hardware, 'chip_type');
    final String memory = _requiredString(hardware, 'physical_memory');
    return BenchmarkHostSnapshot._(
      device: '$model / $chip / $memory',
      operatingSystem: _requiredString(software, 'os_version'),
      thermalState: _thermalState(thermalStatus),
      powerState: _powerState(batteryStatus),
      refreshRateHz: refreshRateHz,
      flutterRevision: _requiredString(flutter, 'frameworkRevision'),
      engineRevision: _requiredString(flutter, 'engineRevision'),
    );
  }

  final String device;
  final String operatingSystem;
  final String thermalState;
  final String powerState;
  final double refreshRateHz;
  final String flutterRevision;
  final String engineRevision;

  Map<String, Object?> toJson() => <String, Object?>{
        'device': device,
        'operatingSystem': operatingSystem,
        'thermalState': thermalState,
        'powerState': powerState,
        'refreshRateHz': refreshRateHz,
        'flutterRevision': flutterRevision,
        'engineRevision': engineRevision,
      };
}

Map<String, Object?> _decodeObject(String source, String command) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on Object catch (error) {
    throw FormatException('$command did not return valid JSON.', error);
  }
  if (decoded is! Map<String, Object?>) {
    throw FormatException('$command must return a JSON object.');
  }
  return decoded;
}

Map<String, Object?> _firstObject(
  Map<String, Object?> source,
  String key,
) {
  final Object? value = source[key];
  if (value is! List<Object?> || value.isEmpty) {
    throw FormatException('$key must contain at least one object.');
  }
  final Object? first = value.first;
  if (first is! Map<String, Object?>) {
    throw FormatException('$key must contain JSON objects.');
  }
  return first;
}

Map<String, Object?> _mainDisplay(Map<String, Object?> profile) {
  final Object? gpuValues = profile['SPDisplaysDataType'];
  if (gpuValues is! List<Object?>) {
    throw const FormatException('SPDisplaysDataType must be a JSON array.');
  }
  Map<String, Object?>? fallback;
  for (final Object? gpuValue in gpuValues) {
    if (gpuValue is! Map<String, Object?>) {
      continue;
    }
    final Object? displays = gpuValue['spdisplays_ndrvs'];
    if (displays is! List<Object?>) {
      continue;
    }
    for (final Object? displayValue in displays) {
      if (displayValue is! Map<String, Object?>) {
        continue;
      }
      fallback ??= displayValue;
      if (displayValue['spdisplays_main'] == 'spdisplays_yes') {
        return displayValue;
      }
    }
  }
  if (fallback == null) {
    throw const FormatException('No online display was reported.');
  }
  return fallback;
}

String _requiredString(Map<String, Object?> source, String key) {
  final Object? value = source[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

String _thermalState(String status) {
  final String lower = status.toLowerCase();
  if (lower.contains('no thermal warning') &&
      (lower.contains('no performance warning') ||
          !lower.contains('performance warning'))) {
    return 'nominal';
  }
  final String normalized = status
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .join(' | ');
  if (normalized.isEmpty) {
    throw const FormatException('Thermal status is empty.');
  }
  return normalized;
}

String _powerState(String status) {
  final String lower = status.toLowerCase();
  final String source =
      lower.contains('ac power') || lower.contains('ac attached')
          ? 'AC'
          : 'Battery';
  final RegExpMatch? percentage = RegExp(r'(\d+)%').firstMatch(status);
  if (percentage == null) {
    throw FormatException(
        'Battery status does not include a percentage: $status');
  }
  final String charging = lower.contains('not charging')
      ? 'not charging'
      : lower.contains('charging')
          ? 'charging'
          : 'charge state unknown';
  return '$source / ${percentage.group(1)}% / $charging';
}
