import 'command_model.dart';
import 'index_delegate.dart';
import 'scroll_placement.dart';
import 'scroll_target.dart';

/// Converts an application key to and from state-restoration primitives.
///
/// Implementations must keep [namespace] stable for the logical key domain and
/// increment [schemaVersion] whenever the encoded representation changes.
abstract interface class SeekoKeyCodec<K extends Object> {
  String get namespace;
  int get schemaVersion;
  Object? encode(K key);
  K decode(Object? value);
}

/// Converts an encoded key from schema version `n` to version `n + 1`.
typedef SeekoKeyMigration = Object? Function(Object? encodedKey);

/// A contiguous set of key-schema migrations.
final class SeekoRestorationMigrations {
  SeekoRestorationMigrations(Map<int, SeekoKeyMigration> migrations)
      : _migrations = Map<int, SeekoKeyMigration>.unmodifiable(migrations) {
    for (final int version in _migrations.keys) {
      RangeError.checkNotNegative(version, 'migration version');
    }
  }

  final Map<int, SeekoKeyMigration> _migrations;

  Object? migrate(Object? value, {required int from, required int to}) {
    var current = value;
    for (var version = from; version < to; version += 1) {
      final SeekoKeyMigration? migration = _migrations[version];
      if (migration == null) {
        throw SeekoRestorationFormatException(
          'Missing key migration from schema $version to ${version + 1}.',
        );
      }
      try {
        current = _canonicalRestorableValue(
          migration(current),
          'migrated key',
        );
      } on Object catch (error) {
        throw SeekoRestorationFormatException(
          'Key migration from schema $version to ${version + 1} failed: '
          '$error',
        );
      }
    }
    return current;
  }
}

/// A stable semantic anchor suitable for Flutter state restoration.
final class SeekoRestorationAnchor<K extends Object> {
  factory SeekoRestorationAnchor({
    required String driverKind,
    required K key,
    required double itemAnchor,
    required double viewportAnchor,
    required double logicalOffset,
    int? lastKnownIndex,
    int? dataRevisionHint,
    double? fallbackProgress,
  }) {
    if (driverKind.isEmpty) {
      throw ArgumentError.value(driverKind, 'driverKind', 'must not be empty');
    }
    if (lastKnownIndex != null) {
      RangeError.checkNotNegative(lastKnownIndex, 'lastKnownIndex');
    }
    if (dataRevisionHint != null) {
      RangeError.checkNotNegative(dataRevisionHint, 'dataRevisionHint');
    }
    _validateAnchor(itemAnchor, 'itemAnchor');
    _validateAnchor(viewportAnchor, 'viewportAnchor');
    if (!logicalOffset.isFinite) {
      throw ArgumentError.value(
        logicalOffset,
        'logicalOffset',
        'must be finite',
      );
    }
    if (fallbackProgress != null) {
      _validateAnchor(fallbackProgress, 'fallbackProgress');
    }
    return SeekoRestorationAnchor<K>._(
      driverKind: driverKind,
      key: key,
      lastKnownIndex: lastKnownIndex,
      itemAnchor: itemAnchor,
      viewportAnchor: viewportAnchor,
      logicalOffset: logicalOffset,
      dataRevisionHint: dataRevisionHint,
      fallbackProgress: fallbackProgress,
    );
  }

  /// Decodes a versioned restoration payload using [codec].
  factory SeekoRestorationAnchor.decode(
    Map<String, Object?> payload,
    SeekoKeyCodec<K> codec, {
    SeekoRestorationMigrations? migrations,
  }) {
    _validateCodec(codec);
    final int payloadFormat = _requiredInt(payload, 'formatVersion');
    if (payloadFormat != formatVersion) {
      throw SeekoRestorationFormatException(
        'Unsupported restoration format version $payloadFormat.',
      );
    }
    final String namespace = _requiredString(payload, 'codecNamespace');
    if (namespace != codec.namespace) {
      throw SeekoRestorationFormatException(
        'Restoration codec namespace "$namespace" does not match '
        '"${codec.namespace}".',
      );
    }
    final int storedVersion = _requiredInt(payload, 'codecVersion');
    if (storedVersion < 0 || storedVersion > codec.schemaVersion) {
      throw SeekoRestorationFormatException(
        'Unsupported key schema version $storedVersion for '
        '${codec.namespace}@${codec.schemaVersion}.',
      );
    }
    Object? encodedKey =
        _canonicalRestorableValue(payload['encodedKey'], 'encoded key');
    if (storedVersion < codec.schemaVersion) {
      if (migrations == null) {
        throw SeekoRestorationFormatException(
          'Key schema $storedVersion requires migrations to '
          '${codec.schemaVersion}.',
        );
      }
      encodedKey = migrations.migrate(
        encodedKey,
        from: storedVersion,
        to: codec.schemaVersion,
      );
    }
    final K key;
    try {
      key = codec.decode(encodedKey);
    } on Object catch (error) {
      throw SeekoRestorationFormatException(
        'The key codec rejected the restored key: $error',
      );
    }
    return SeekoRestorationAnchor<K>(
      driverKind: _requiredString(payload, 'driverKind'),
      key: key,
      lastKnownIndex: _optionalInt(payload, 'lastKnownIndex'),
      itemAnchor: _requiredDouble(payload, 'itemAnchor'),
      viewportAnchor: _requiredDouble(payload, 'viewportAnchor'),
      logicalOffset: _requiredDouble(payload, 'logicalOffset'),
      dataRevisionHint: _optionalInt(payload, 'dataRevisionHint'),
      fallbackProgress: _optionalDouble(payload, 'fallbackProgress'),
    );
  }

  const SeekoRestorationAnchor._({
    required this.driverKind,
    required this.key,
    required this.lastKnownIndex,
    required this.itemAnchor,
    required this.viewportAnchor,
    required this.logicalOffset,
    required this.dataRevisionHint,
    required this.fallbackProgress,
  });

  static const int formatVersion = 1;

  final String driverKind;
  final K key;
  final int? lastKnownIndex;
  final double itemAnchor;
  final double viewportAnchor;
  final double logicalOffset;
  final int? dataRevisionHint;
  final double? fallbackProgress;

  Map<String, Object?> encode(SeekoKeyCodec<K> codec) {
    _validateCodec(codec);
    final Object? encodedKey;
    try {
      encodedKey = codec.encode(key);
    } on Object catch (error) {
      throw SeekoRestorationFormatException(
        'The key codec failed to encode a key: $error',
      );
    }
    final Object? encodedSnapshot =
        _canonicalRestorableValue(encodedKey, 'encoded key');
    return <String, Object?>{
      'formatVersion': formatVersion,
      'driverKind': driverKind,
      'codecNamespace': codec.namespace,
      'codecVersion': codec.schemaVersion,
      'encodedKey': encodedSnapshot,
      'lastKnownIndex': lastKnownIndex,
      'itemAnchor': itemAnchor,
      'viewportAnchor': viewportAnchor,
      'logicalOffset': logicalOffset,
      'dataRevisionHint': dataRevisionHint,
      'fallbackProgress': fallbackProgress,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SeekoRestorationAnchor<K> &&
      other.driverKind == driverKind &&
      other.key == key &&
      other.lastKnownIndex == lastKnownIndex &&
      other.itemAnchor == itemAnchor &&
      other.viewportAnchor == viewportAnchor &&
      other.logicalOffset == logicalOffset &&
      other.dataRevisionHint == dataRevisionHint &&
      other.fallbackProgress == fallbackProgress;

  @override
  int get hashCode => Object.hash(
        driverKind,
        key,
        lastKnownIndex,
        itemAnchor,
        viewportAnchor,
        logicalOffset,
        dataRevisionHint,
        fallbackProgress,
      );
}

/// The ordered strategies available when an exact semantic key cannot be
/// restored.
enum SeekoRestorationFallbackStep {
  indexHint,
  resolver,
  progress,
  leadingEdge,
  fail,
}

/// Why restoration did or did not produce a scroll target.
enum SeekoRestorationResolutionStatus {
  exact,
  fallback,
  targetNotLoaded,
  failed,
}

/// The codec-independent state retained when a persisted key cannot be
/// decoded.
final class SeekoRestorationFallbackState {
  SeekoRestorationFallbackState({
    required String driverKind,
    required double itemAnchor,
    required double viewportAnchor,
    required double logicalOffset,
    required this.cause,
    int? lastKnownIndex,
    int? dataRevisionHint,
    double? fallbackProgress,
  })  : _driverKind = _checkedDriverKind(driverKind),
        _lastKnownIndex = _checkedOptionalNonNegative(
          lastKnownIndex,
          'lastKnownIndex',
        ),
        _itemAnchor = _checkedAnchor(itemAnchor, 'itemAnchor'),
        _viewportAnchor = _checkedAnchor(viewportAnchor, 'viewportAnchor'),
        _logicalOffset = _checkedFinite(logicalOffset, 'logicalOffset'),
        _dataRevisionHint = _checkedOptionalNonNegative(
          dataRevisionHint,
          'dataRevisionHint',
        ),
        _fallbackProgress = fallbackProgress == null
            ? null
            : _checkedAnchor(fallbackProgress, 'fallbackProgress');

  final String _driverKind;
  final int? _lastKnownIndex;
  final double _itemAnchor;
  final double _viewportAnchor;
  final double _logicalOffset;
  final int? _dataRevisionHint;
  final double? _fallbackProgress;

  String get driverKind => _driverKind;
  int? get lastKnownIndex => _lastKnownIndex;
  double get itemAnchor => _itemAnchor;
  double get viewportAnchor => _viewportAnchor;
  double get logicalOffset => _logicalOffset;
  int? get dataRevisionHint => _dataRevisionHint;
  double? get fallbackProgress => _fallbackProgress;
  final Object cause;
}

/// Context supplied to an application-specific restoration fallback.
final class SeekoRestorationContext<K extends Object> {
  const SeekoRestorationContext({
    required this.anchor,
    required this.fallbackState,
    required this.delegate,
  });

  final SeekoRestorationAnchor<K>? anchor;
  final SeekoRestorationFallbackState? fallbackState;
  final SeekoIndexDelegate<K> delegate;
}

typedef RestorationFallbackResolver<K extends Object> = ScrollTarget? Function(
  SeekoRestorationContext<K> context,
);

/// Defines the explicit fallback order for semantic restoration.
final class SeekoRestorationPolicy<K extends Object> {
  factory SeekoRestorationPolicy({
    List<SeekoRestorationFallbackStep>? steps,
    RestorationFallbackResolver<K>? resolver,
  }) {
    final List<SeekoRestorationFallbackStep> effectiveSteps = steps ??
        <SeekoRestorationFallbackStep>[
          SeekoRestorationFallbackStep.indexHint,
          if (resolver != null) SeekoRestorationFallbackStep.resolver,
          SeekoRestorationFallbackStep.progress,
          SeekoRestorationFallbackStep.leadingEdge,
          SeekoRestorationFallbackStep.fail,
        ];
    if (effectiveSteps.isEmpty) {
      throw ArgumentError.value(effectiveSteps, 'steps', 'must not be empty');
    }
    if (effectiveSteps.contains(SeekoRestorationFallbackStep.resolver) &&
        resolver == null) {
      throw ArgumentError(
        'A restoration resolver step requires a resolver callback.',
      );
    }
    return SeekoRestorationPolicy<K>._(
      List<SeekoRestorationFallbackStep>.unmodifiable(effectiveSteps),
      resolver,
    );
  }

  const SeekoRestorationPolicy._(this.steps, this.resolver);

  final List<SeekoRestorationFallbackStep> steps;
  final RestorationFallbackResolver<K>? resolver;
}

/// A restoration decision that preserves exact, degraded, loading, and
/// failure semantics.
final class SeekoRestorationResolution {
  SeekoRestorationResolution._({
    required this.status,
    required this.target,
    required this.mode,
    required this.fallbackStep,
    required this.placement,
    required Map<String, Object?> diagnostics,
  }) : diagnostics = Map<String, Object?>.unmodifiable(diagnostics);

  final SeekoRestorationResolutionStatus status;
  final ScrollTarget? target;
  final ScrollResolutionMode mode;
  final SeekoRestorationFallbackStep? fallbackStep;
  final ScrollPlacement placement;
  final Map<String, Object?> diagnostics;
}

/// Resolves a restored semantic anchor against the current data revision.
///
/// Exactly one of [anchor] and [fallbackState] must be supplied. The function
/// never invents key ordering and never silently substitutes pixel zero.
SeekoRestorationResolution resolveSeekoRestoration<K extends Object>({
  SeekoRestorationAnchor<K>? anchor,
  SeekoRestorationFallbackState? fallbackState,
  required SeekoIndexDelegate<K> delegate,
  SeekoRestorationPolicy<K>? policy,
}) {
  if ((anchor == null) == (fallbackState == null)) {
    throw ArgumentError(
      'Provide exactly one of anchor or fallbackState.',
    );
  }
  final Map<String, Object?> diagnostics = <String, Object?>{
    'driverKind': anchor?.driverKind ?? fallbackState!.driverKind,
    'restoredRevisionHint':
        anchor?.dataRevisionHint ?? fallbackState?.dataRevisionHint,
    'currentRevision': delegate.revision,
    if (fallbackState != null)
      'restorationFailure': fallbackState.cause.toString(),
  };
  final ScrollPlacement placement = ScrollPlacement.exact(
    targetAnchor: anchor?.itemAnchor ?? fallbackState!.itemAnchor,
    viewportAnchor: anchor?.viewportAnchor ?? fallbackState!.viewportAnchor,
    offset: anchor?.logicalOffset ?? fallbackState!.logicalOffset,
  );
  if (anchor != null) {
    final SeekoKeyLookup<K> lookup = delegate.lookupKey(anchor.key);
    if (lookup.status == SeekoKeyLookupStatus.found) {
      return SeekoRestorationResolution._(
        status: SeekoRestorationResolutionStatus.exact,
        target: ScrollTarget.key(anchor.key),
        mode: ScrollResolutionMode.exact,
        fallbackStep: null,
        placement: placement,
        diagnostics: diagnostics,
      );
    }
    if (lookup.status == SeekoKeyLookupStatus.notLoaded) {
      diagnostics['keyStatus'] = 'notLoaded';
      return SeekoRestorationResolution._(
        status: SeekoRestorationResolutionStatus.targetNotLoaded,
        target: ScrollTarget.key(anchor.key),
        mode: ScrollResolutionMode.exact,
        fallbackStep: null,
        placement: placement,
        diagnostics: diagnostics,
      );
    } else {
      diagnostics['keyStatus'] = 'absent';
    }
  }
  final SeekoRestorationPolicy<K> effective =
      policy ?? SeekoRestorationPolicy<K>();
  for (final SeekoRestorationFallbackStep step in effective.steps) {
    switch (step) {
      case SeekoRestorationFallbackStep.indexHint:
        final int? hint =
            anchor?.lastKnownIndex ?? fallbackState?.lastKnownIndex;
        if (hint == null) {
          continue;
        }
        final int? itemCount = delegate.itemCount;
        if (itemCount == 0) {
          continue;
        }
        final int candidate =
            itemCount == null ? hint : hint.clamp(0, itemCount - 1);
        final SeekoKeyLookup<K> capture = delegate.captureIndex(candidate);
        if (capture.status == SeekoKeyLookupStatus.found) {
          final K key = capture.key ?? delegate.keyAt(candidate);
          return _fallbackResolution(
            ScrollTarget.key(key),
            step,
            placement,
            diagnostics,
          );
        }
        if (capture.status == SeekoKeyLookupStatus.notLoaded) {
          return SeekoRestorationResolution._(
            status: SeekoRestorationResolutionStatus.targetNotLoaded,
            target: ScrollTarget.index(candidate),
            mode: ScrollResolutionMode.fallback,
            fallbackStep: step,
            placement: placement,
            diagnostics: diagnostics,
          );
        }
      case SeekoRestorationFallbackStep.resolver:
        final ScrollTarget? target = effective.resolver?.call(
          SeekoRestorationContext<K>(
            anchor: anchor,
            fallbackState: fallbackState,
            delegate: delegate,
          ),
        );
        if (target != null) {
          return _fallbackResolution(target, step, placement, diagnostics);
        }
      case SeekoRestorationFallbackStep.progress:
        final double? progress =
            anchor?.fallbackProgress ?? fallbackState?.fallbackProgress;
        if (progress != null) {
          return _fallbackResolution(
            ScrollTarget.progress(progress),
            step,
            placement,
            diagnostics,
          );
        }
      case SeekoRestorationFallbackStep.leadingEdge:
        return _fallbackResolution(
          const ScrollTarget.edge(ScrollEdge.leading),
          step,
          placement,
          diagnostics,
        );
      case SeekoRestorationFallbackStep.fail:
        return SeekoRestorationResolution._(
          status: SeekoRestorationResolutionStatus.failed,
          target: null,
          mode: ScrollResolutionMode.fallback,
          fallbackStep: step,
          placement: placement,
          diagnostics: diagnostics,
        );
    }
  }
  return SeekoRestorationResolution._(
    status: SeekoRestorationResolutionStatus.failed,
    target: null,
    mode: ScrollResolutionMode.fallback,
    fallbackStep: null,
    placement: placement,
    diagnostics: diagnostics,
  );
}

SeekoRestorationResolution _fallbackResolution(
  ScrollTarget target,
  SeekoRestorationFallbackStep step,
  ScrollPlacement placement,
  Map<String, Object?> diagnostics,
) {
  return SeekoRestorationResolution._(
    status: SeekoRestorationResolutionStatus.fallback,
    target: target,
    mode: ScrollResolutionMode.fallback,
    fallbackStep: step,
    placement: placement,
    diagnostics: diagnostics,
  );
}

/// Indicates that persisted scroll state is invalid or incompatible.
final class SeekoRestorationFormatException extends FormatException {
  const SeekoRestorationFormatException(super.message);
}

String _checkedDriverKind(String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'driverKind', 'must not be empty');
  }
  return value;
}

int? _checkedOptionalNonNegative(int? value, String name) {
  if (value != null) {
    RangeError.checkNotNegative(value, name);
  }
  return value;
}

double _checkedAnchor(double value, String name) {
  _validateAnchor(value, name);
  return value;
}

double _checkedFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
  return value;
}

void _validateCodec<K extends Object>(SeekoKeyCodec<K> codec) {
  if (codec.namespace.isEmpty) {
    throw SeekoRestorationFormatException(
      'A key codec namespace must not be empty.',
    );
  }
  if (codec.schemaVersion < 0) {
    throw SeekoRestorationFormatException(
      'A key codec schema version must not be negative.',
    );
  }
}

void _validateAnchor(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw RangeError.value(value, name, 'must be finite and between 0 and 1');
  }
}

Object? _canonicalRestorableValue(Object? value, String name) {
  return _canonicalRestorableValueInner(value, name, <Object>{});
}

// Restorable payloads must round-trip through JSON and dart2js without losing
// integer precision. Keep the bound representable exactly on every platform.
const int _maxRestorableInteger = 9007199254740991;

Object? _canonicalRestorableValueInner(
  Object? value,
  String name,
  Set<Object> activeContainers,
) {
  if (value == null || value is bool || value is int || value is String) {
    if (value is int &&
        (value < -_maxRestorableInteger || value > _maxRestorableInteger)) {
      throw SeekoRestorationFormatException(
        '$name contains an integer outside the JavaScript safe-integer range.',
      );
    }
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw SeekoRestorationFormatException(
          '$name contains a non-finite number.');
    }
    return value;
  }
  if (value is List<Object?>) {
    if (!activeContainers.add(value)) {
      throw SeekoRestorationFormatException(
        '$name contains a cyclic List or Map.',
      );
    }
    final List<Object?> result = <Object?>[];
    for (final Object? element in value) {
      result.add(_canonicalRestorableValueInner(
        element,
        name,
        activeContainers,
      ));
    }
    activeContainers.remove(value);
    return List<Object?>.unmodifiable(result);
  }
  if (value is Map<Object?, Object?>) {
    if (!activeContainers.add(value)) {
      throw SeekoRestorationFormatException(
        '$name contains a cyclic List or Map.',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw SeekoRestorationFormatException(
            '$name contains a non-string map key.');
      }
      result[entry.key! as String] = _canonicalRestorableValueInner(
        entry.value,
        name,
        activeContainers,
      );
    }
    activeContainers.remove(value);
    return Map<String, Object?>.unmodifiable(result);
  }
  throw SeekoRestorationFormatException(
    '$name contains unsupported ${value.runtimeType}.',
  );
}

int _requiredInt(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value is int) {
    return value;
  }
  throw SeekoRestorationFormatException('$key must be an int.');
}

int? _optionalInt(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw SeekoRestorationFormatException('$key must be an int or null.');
}

double _requiredDouble(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value is num) {
    return value.toDouble();
  }
  throw SeekoRestorationFormatException('$key must be numeric.');
}

double? _optionalDouble(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw SeekoRestorationFormatException('$key must be numeric or null.');
}

String _requiredString(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw SeekoRestorationFormatException('$key must be a non-empty string.');
}
