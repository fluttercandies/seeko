import 'package:flutter/widgets.dart';

import '../core/command_model.dart';
import '../core/restoration.dart';
import 'seeko_controller.dart';

/// Stores process-local semantic anchors without overwriting Flutter's native
/// pixel entry in the same [PageStorageBucket].
abstract final class SeekoPageStorage {
  static void write<K extends Object>(
    BuildContext context, {
    required Object storageKey,
    required SeekoRestorationAnchor<K> anchor,
  }) {
    final PageStorageBucket? bucket = PageStorage.maybeOf(context);
    if (bucket == null) {
      return;
    }
    bucket.writeState(
      context,
      anchor,
      identifier: _SeekoPageStorageIdentifier(storageKey),
    );
  }

  static SeekoRestorationAnchor<K>? read<K extends Object>(
    BuildContext context, {
    required Object storageKey,
  }) {
    final Object? value = PageStorage.maybeOf(context)?.readState(
      context,
      identifier: _SeekoPageStorageIdentifier(storageKey),
    );
    if (value == null) {
      return null;
    }
    if (value is! SeekoRestorationAnchor<K>) {
      throw SeekoRestorationFormatException(
        'PageStorage entry "$storageKey" is not a '
        'SeekoRestorationAnchor<$K>.',
      );
    }
    return value;
  }

  static void remove(
    BuildContext context, {
    required Object storageKey,
  }) {
    PageStorage.maybeOf(context)?.writeState(
      context,
      null,
      identifier: _SeekoPageStorageIdentifier(storageKey),
    );
  }
}

/// Process-local PageStorage integration for [SeekoController].
extension SeekoControllerPageStorageRestoration on SeekoController {
  /// Captures and writes the current semantic anchor.
  ///
  /// Returns false without mutating PageStorage when no stable-key target is
  /// currently visible.
  bool saveRestorationToPageStorage(
    BuildContext context, {
    required Object storageKey,
    String driverKind = 'tagged',
  }) {
    final SeekoRestorationAnchor<Object>? anchor =
        captureRestorationAnchor<Object>(driverKind: driverKind);
    if (anchor == null) {
      return false;
    }
    SeekoPageStorage.write<Object>(
      context,
      storageKey: storageKey,
      anchor: anchor,
    );
    return true;
  }

  /// Reads a process-local anchor and applies it through the controller's
  /// scheduler and driver.
  ///
  /// Returns null when no Seeko anchor exists for [storageKey]. Native Flutter
  /// pixel PageStorage state remains untouched.
  Future<ScrollResult?> restoreRestorationFromPageStorage(
    BuildContext context, {
    required Object storageKey,
    SeekoRestorationPolicy<Object>? policy,
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    final SeekoRestorationAnchor<Object>? anchor =
        SeekoPageStorage.read<Object>(
      context,
      storageKey: storageKey,
    );
    if (anchor == null) {
      return Future<ScrollResult?>.value();
    }
    return restoreRestorationAnchor(
      anchor,
      policy: policy,
      options: options,
    );
  }
}

final class _SeekoPageStorageIdentifier {
  const _SeekoPageStorageIdentifier(this.key);

  final Object key;

  @override
  bool operator ==(Object other) =>
      other is _SeekoPageStorageIdentifier && other.key == key;

  @override
  int get hashCode => Object.hash(SeekoPageStorage, key);
}

/// Details retained when Flutter restoration payload decoding fails.
final class SeekoRestorationDecodeFailure {
  const SeekoRestorationDecodeFailure({
    required this.error,
    required this.fallbackState,
  });

  final SeekoRestorationFormatException error;
  final SeekoRestorationFallbackState? fallbackState;
}

/// A Flutter [RestorableValue] for a nullable semantic scroll anchor.
///
/// Invalid or incompatible persisted payloads never crash restoration. The
/// value becomes null and [decodeFailure] exposes enough metadata for an
/// explicit [SeekoRestorationPolicy] to select a fallback target.
final class RestorableSeekoAnchor<K extends Object>
    extends RestorableValue<SeekoRestorationAnchor<K>?> {
  RestorableSeekoAnchor({
    required this.codec,
    this.migrations,
    SeekoRestorationAnchor<K>? defaultValue,
  }) : _defaultValue = defaultValue;

  final SeekoKeyCodec<K> codec;
  final SeekoRestorationMigrations? migrations;
  final SeekoRestorationAnchor<K>? _defaultValue;
  SeekoRestorationDecodeFailure? _decodeFailure;

  SeekoRestorationDecodeFailure? get decodeFailure => _decodeFailure;

  @override
  SeekoRestorationAnchor<K>? createDefaultValue() => _defaultValue;

  @override
  void didUpdateValue(SeekoRestorationAnchor<K>? oldValue) {
    _decodeFailure = null;
    notifyListeners();
  }

  @override
  SeekoRestorationAnchor<K>? fromPrimitives(Object? data) {
    if (data == null) {
      _decodeFailure = null;
      return null;
    }
    final Map<String, Object?> payload;
    try {
      payload = _asStringKeyedMap(data);
      final SeekoRestorationAnchor<K> anchor = SeekoRestorationAnchor<K>.decode(
        payload,
        codec,
        migrations: migrations,
      );
      _decodeFailure = null;
      return anchor;
    } on SeekoRestorationFormatException catch (error) {
      _decodeFailure = SeekoRestorationDecodeFailure(
        error: error,
        fallbackState: _fallbackStateFromPayload(data, error),
      );
      return null;
    } on Object catch (error) {
      final SeekoRestorationFormatException wrapped =
          SeekoRestorationFormatException(
        'Invalid Seeko restoration payload: $error',
      );
      _decodeFailure = SeekoRestorationDecodeFailure(
        error: wrapped,
        fallbackState: _fallbackStateFromPayload(data, wrapped),
      );
      return null;
    }
  }

  @override
  Object? toPrimitives() => value?.encode(codec);
}

Map<String, Object?> _asStringKeyedMap(Object data) {
  if (data is! Map<Object?, Object?>) {
    throw const SeekoRestorationFormatException(
      'Restoration payload must be a map.',
    );
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in data.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw const SeekoRestorationFormatException(
        'Restoration payload contains a non-string map key.',
      );
    }
    result[key] = entry.value;
  }
  return result;
}

SeekoRestorationFallbackState? _fallbackStateFromPayload(
  Object? data,
  Object cause,
) {
  if (data is! Map<Object?, Object?>) {
    return null;
  }
  try {
    final Map<String, Object?> payload = _asStringKeyedMap(data);
    return SeekoRestorationFallbackState(
      driverKind: payload['driverKind']! as String,
      lastKnownIndex: payload['lastKnownIndex'] as int?,
      itemAnchor: (payload['itemAnchor']! as num).toDouble(),
      viewportAnchor: (payload['viewportAnchor']! as num).toDouble(),
      logicalOffset: (payload['logicalOffset']! as num).toDouble(),
      dataRevisionHint: payload['dataRevisionHint'] as int?,
      fallbackProgress: (payload['fallbackProgress'] as num?)?.toDouble(),
      cause: cause,
    );
  } on Object {
    return null;
  }
}
