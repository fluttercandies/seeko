import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('semantic anchors round-trip through restorable primitives', () {
    const _MessageKeyCodec codec = _MessageKeyCodec();
    final SeekoRestorationAnchor<String> anchor =
        SeekoRestorationAnchor<String>(
      driverKind: 'indexed-sliver',
      key: 'message-42',
      lastKnownIndex: 41,
      itemAnchor: 0.25,
      viewportAnchor: 0.5,
      logicalOffset: -12.5,
      dataRevisionHint: 9,
      fallbackProgress: 0.75,
    );

    final Map<String, Object?> encoded = anchor.encode(codec);
    final SeekoRestorationAnchor<String> decoded =
        SeekoRestorationAnchor<String>.decode(encoded, codec);

    expect(decoded, anchor);
    expect(encoded['codecNamespace'], 'messages');
    expect(encoded['codecVersion'], 2);
  });

  test('restoration rejects namespace and future-version mismatches', () {
    const _MessageKeyCodec codec = _MessageKeyCodec();
    final Map<String, Object?> encoded = SeekoRestorationAnchor<String>(
      driverKind: 'tagged',
      key: 'message-1',
      itemAnchor: 0,
      viewportAnchor: 0,
      logicalOffset: 0,
    ).encode(codec);

    expect(
      () => SeekoRestorationAnchor<String>.decode(
        <String, Object?>{
          ...encoded,
          'codecNamespace': 'other',
        },
        codec,
      ),
      throwsA(isA<SeekoRestorationFormatException>()),
    );
    expect(
      () => SeekoRestorationAnchor<String>.decode(
        <String, Object?>{
          ...encoded,
          'codecVersion': 99,
        },
        codec,
      ),
      throwsA(isA<SeekoRestorationFormatException>()),
    );
  });

  test('restoration rejects negative metadata and non-finite payload numbers',
      () {
    const _MessageKeyCodec codec = _MessageKeyCodec();
    final Map<String, Object?> encoded = SeekoRestorationAnchor<String>(
      driverKind: 'tagged',
      key: 'message-1',
      itemAnchor: 0,
      viewportAnchor: 0,
      logicalOffset: 0,
    ).encode(codec);

    expect(
      () => SeekoRestorationAnchor<String>.decode(
        <String, Object?>{...encoded, 'lastKnownIndex': -1},
        codec,
      ),
      throwsRangeError,
    );
    expect(
      () => SeekoRestorationAnchor<String>.decode(
        <String, Object?>{...encoded, 'dataRevisionHint': -1},
        codec,
      ),
      throwsRangeError,
    );
    expect(
      () => SeekoRestorationAnchor<String>.decode(
        <String, Object?>{...encoded, 'logicalOffset': double.nan},
        codec,
      ),
      throwsArgumentError,
    );
    expect(
      () => SeekoRestorationAnchor<String>.decode(
        <String, Object?>{...encoded, 'fallbackProgress': double.infinity},
        codec,
      ),
      throwsRangeError,
    );
  });

  test('older key schemas migrate one version at a time before decoding', () {
    const _MessageKeyCodec codec = _MessageKeyCodec();
    final SeekoRestorationMigrations migrations =
        SeekoRestorationMigrations(<int, SeekoKeyMigration>{
      0: (Object? value) => <String, Object?>{'legacy': value},
      1: (Object? value) =>
          (value! as Map<Object?, Object?>)['legacy'] as String,
    });

    final SeekoRestorationAnchor<String> decoded =
        SeekoRestorationAnchor<String>.decode(
      <String, Object?>{
        'formatVersion': 1,
        'driverKind': 'indexed-sliver',
        'codecNamespace': 'messages',
        'codecVersion': 0,
        'encodedKey': 'legacy-7',
        'lastKnownIndex': 6,
        'itemAnchor': 0.0,
        'viewportAnchor': 0.0,
        'logicalOffset': 0.0,
        'dataRevisionHint': null,
        'fallbackProgress': null,
      },
      codec,
      migrations: migrations,
    );

    expect(decoded.key, 'legacy-7');
    expect(decoded.lastKnownIndex, 6);
  });

  test('migration failures identify the failing schema transition', () {
    const _MessageKeyCodec codec = _MessageKeyCodec();
    final SeekoRestorationMigrations migrations =
        SeekoRestorationMigrations(<int, SeekoKeyMigration>{
      0: (Object? value) => throw StateError('broken migration'),
    });

    expect(
      () => SeekoRestorationAnchor<String>.decode(
        <String, Object?>{
          'formatVersion': 1,
          'driverKind': 'indexed-sliver',
          'codecNamespace': 'messages',
          'codecVersion': 0,
          'encodedKey': 'legacy-7',
          'lastKnownIndex': 6,
          'itemAnchor': 0.0,
          'viewportAnchor': 0.0,
          'logicalOffset': 0.0,
          'dataRevisionHint': null,
          'fallbackProgress': null,
        },
        codec,
        migrations: migrations,
      ),
      throwsA(
        isA<SeekoRestorationFormatException>().having(
          (SeekoRestorationFormatException error) => error.message,
          'message',
          allOf(contains('0'), contains('1'), contains('broken migration')),
        ),
      ),
    );
  });

  test('codec output and payload geometry are validated eagerly', () {
    expect(
      () => SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'x',
        itemAnchor: 2,
        viewportAnchor: 0,
        logicalOffset: 0,
      ),
      throwsRangeError,
    );
    expect(
      () => SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'x',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'x',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ).encode(const _InvalidKeyCodec()),
      throwsA(isA<SeekoRestorationFormatException>()),
    );
  });

  test('encoded primitive collections are detached immutable snapshots', () {
    final List<Object?> encodedKey = <Object?>[
      <String, Object?>{'id': 42},
    ];
    final Map<String, Object?> payload = SeekoRestorationAnchor<String>(
      driverKind: 'tagged',
      key: 'x',
      itemAnchor: 0,
      viewportAnchor: 0,
      logicalOffset: 0,
    ).encode(_MutablePrimitiveCodec(encodedKey));

    encodedKey.add('mutated');
    (encodedKey.first! as Map<String, Object?>)['id'] = 99;
    final List<Object?> snapshot = payload['encodedKey']! as List<Object?>;

    expect(snapshot, <Object?>[
      <String, Object?>{'id': 42},
    ]);
    expect(() => snapshot.add('forbidden'), throwsUnsupportedError);
    expect(
      () => (snapshot.first! as Map<String, Object?>)['id'] = 7,
      throwsUnsupportedError,
    );
  });

  test('encoded primitives reject cycles and unsupported large integers', () {
    final List<Object?> cyclic = <Object?>[];
    cyclic.add(cyclic);
    expect(
      () => SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'x',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ).encode(_MutablePrimitiveCodec(cyclic)),
      throwsA(isA<SeekoRestorationFormatException>()),
    );
    expect(
      () => SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'x',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ).encode(const _LargeIntegerCodec()),
      throwsA(isA<SeekoRestorationFormatException>()),
    );
  });

  test('encoded primitives accept JavaScript safe-integer boundaries', () {
    const int safeInteger = 9007199254740991;
    final SeekoRestorationAnchor<String> anchor =
        SeekoRestorationAnchor<String>(
      driverKind: 'tagged',
      key: 'x',
      itemAnchor: 0,
      viewportAnchor: 0,
      logicalOffset: 0,
    );
    final Map<String, Object?> payload = anchor.encode(
      _MutablePrimitiveCodec(<Object?>[safeInteger, -safeInteger]),
    );
    expect(payload['encodedKey'], <Object?>[safeInteger, -safeInteger]);
  });

  test('restoration resolves a surviving stable key exactly', () {
    final _MutableStringDelegate delegate = _MutableStringDelegate(
      <String>['a', 'message-42', 'c'],
    );
    final SeekoRestorationResolution resolution = resolveSeekoRestoration(
      anchor: SeekoRestorationAnchor<String>(
        driverKind: 'indexed-sliver',
        key: 'message-42',
        lastKnownIndex: 1,
        itemAnchor: 0.25,
        viewportAnchor: 0.5,
        logicalOffset: -12.5,
        fallbackProgress: 0.75,
      ),
      delegate: delegate,
    );

    expect(resolution.status, SeekoRestorationResolutionStatus.exact);
    expect(resolution.target, ScrollTarget.key('message-42'));
    expect(resolution.mode, ScrollResolutionMode.exact);
    expect(
      (resolution as dynamic).placement,
      ScrollPlacement.exact(
        targetAnchor: 0.25,
        viewportAnchor: 0.5,
        offset: -12.5,
      ),
    );
  });

  test('missing keys use the current key captured at the clamped index hint',
      () {
    final _MutableStringDelegate delegate = _MutableStringDelegate(
      <String>['new-a', 'new-b'],
    );
    final SeekoRestorationResolution resolution = resolveSeekoRestoration(
      anchor: SeekoRestorationAnchor<String>(
        driverKind: 'indexed-sliver',
        key: 'deleted',
        lastKnownIndex: 99,
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
        fallbackProgress: 0.25,
      ),
      delegate: delegate,
    );

    expect(resolution.status, SeekoRestorationResolutionStatus.fallback);
    expect(resolution.target, ScrollTarget.key('new-b'));
    expect(resolution.fallbackStep, SeekoRestorationFallbackStep.indexHint);
    expect(resolution.mode, ScrollResolutionMode.fallback);
    expect(
      (resolution as dynamic).placement,
      ScrollPlacement.exact(
        targetAnchor: 0,
        viewportAnchor: 0,
      ),
    );
  });

  test('a not-loaded restored key never degrades to progress', () {
    final _PagedStringDelegate delegate = _PagedStringDelegate();
    final SeekoRestorationResolution resolution = resolveSeekoRestoration(
      anchor: SeekoRestorationAnchor<String>(
        driverKind: 'indexed-sliver',
        key: 'message-42',
        itemAnchor: 0.25,
        viewportAnchor: 0.75,
        logicalOffset: 8,
        fallbackProgress: 0.5,
      ),
      delegate: delegate,
    );

    expect(
      resolution.status,
      SeekoRestorationResolutionStatus.targetNotLoaded,
    );
    expect(resolution.target, ScrollTarget.key('message-42'));
    expect(resolution.fallbackStep, isNull);
    expect(
      (resolution as dynamic).placement,
      ScrollPlacement.exact(
        targetAnchor: 0.25,
        viewportAnchor: 0.75,
        offset: 8,
      ),
    );
  });

  test('not-loaded index fallback remains distinguishable from absence', () {
    final _PagedStringDelegate delegate = _PagedStringDelegate();
    final SeekoRestorationResolution resolution = resolveSeekoRestoration(
      fallbackState: SeekoRestorationFallbackState(
        driverKind: 'indexed-sliver',
        lastKnownIndex: 40,
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
        fallbackProgress: 0.5,
        cause: const SeekoRestorationFormatException('codec mismatch'),
      ),
      delegate: delegate,
    );

    expect(
      resolution.status,
      SeekoRestorationResolutionStatus.targetNotLoaded,
    );
    expect(resolution.target, ScrollTarget.index(40));
    expect(resolution.fallbackStep, SeekoRestorationFallbackStep.indexHint);
  });

  test('fallback policy is ordered, diagnostic, and never silently uses zero',
      () {
    final _MutableStringDelegate delegate = _MutableStringDelegate(<String>[]);
    final SeekoRestorationResolution resolution = resolveSeekoRestoration(
      fallbackState: SeekoRestorationFallbackState(
        driverKind: 'tagged',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
        fallbackProgress: 0.6,
        cause: const SeekoRestorationFormatException('namespace mismatch'),
      ),
      delegate: delegate,
      policy: SeekoRestorationPolicy<String>(
        steps: const <SeekoRestorationFallbackStep>[
          SeekoRestorationFallbackStep.resolver,
          SeekoRestorationFallbackStep.progress,
          SeekoRestorationFallbackStep.fail,
        ],
        resolver: (SeekoRestorationContext<String> context) => null,
      ),
    );

    expect(resolution.status, SeekoRestorationResolutionStatus.fallback);
    expect(resolution.target, ScrollTarget.progress(0.6));
    expect(resolution.fallbackStep, SeekoRestorationFallbackStep.progress);
    expect(resolution.diagnostics, contains('restorationFailure'));
    expect(
      () => resolution.diagnostics['tampered'] = true,
      throwsUnsupportedError,
    );
  });

  test('fallback policy requires an explicit resolver callback', () {
    expect(
      () => SeekoRestorationPolicy<String>(
        steps: const <SeekoRestorationFallbackStep>[
          SeekoRestorationFallbackStep.resolver,
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => SeekoRestorationPolicy<String>(
        steps: const <SeekoRestorationFallbackStep>[
          SeekoRestorationFallbackStep.indexHint,
          SeekoRestorationFallbackStep.resolver,
          SeekoRestorationFallbackStep.fail,
        ],
      ),
      throwsArgumentError,
    );
  });
}

final class _MessageKeyCodec implements SeekoKeyCodec<String> {
  const _MessageKeyCodec();

  @override
  String get namespace => 'messages';

  @override
  int get schemaVersion => 2;

  @override
  String decode(Object? value) => value! as String;

  @override
  Object? encode(String key) => key;
}

final class _InvalidKeyCodec implements SeekoKeyCodec<String> {
  const _InvalidKeyCodec();

  @override
  String get namespace => 'invalid';

  @override
  int get schemaVersion => 1;

  @override
  String decode(Object? value) => 'x';

  @override
  Object? encode(String key) => DateTime(2026);
}

final class _MutablePrimitiveCodec implements SeekoKeyCodec<String> {
  const _MutablePrimitiveCodec(this.encoded);

  final Object? encoded;

  @override
  String get namespace => 'mutable';

  @override
  int get schemaVersion => 1;

  @override
  String decode(Object? value) => 'x';

  @override
  Object? encode(String key) => encoded;
}

final class _LargeIntegerCodec implements SeekoKeyCodec<String> {
  const _LargeIntegerCodec();

  @override
  String get namespace => 'large-int';

  @override
  int get schemaVersion => 1;

  @override
  String decode(Object? value) => 'x';

  @override
  Object? encode(String key) => BigInt.parse('9223372036854775808');
}

final class _MutableStringDelegate implements SeekoIndexDelegate<String> {
  _MutableStringDelegate(this.items);

  final List<String> items;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  @override
  Listenable get changes => _revision;

  @override
  int get revision => _revision.value;

  @override
  int get itemCount => items.length;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, items.length)]);

  @override
  String keyAt(int index) => items[index];

  @override
  SeekoKeyLookup<String> lookupKey(String key) {
    final int index = items.indexOf(key);
    return index < 0
        ? const SeekoKeyLookup<String>.absent()
        : SeekoKeyLookup<String>.found(index, key: key);
  }

  @override
  SeekoKeyLookup<String> captureIndex(int index) {
    if (index < 0 || index >= items.length) {
      return const SeekoKeyLookup<String>.absent();
    }
    return SeekoKeyLookup<String>.found(index, key: items[index]);
  }
}

final class _PagedStringDelegate implements SeekoIndexDelegate<String> {
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  @override
  Listenable get changes => _revision;

  @override
  int get revision => 0;

  @override
  int? get itemCount => null;

  @override
  LoadedRangeSet get loadedRanges => LoadedRangeSet(<IndexRange>[]);

  @override
  String keyAt(int index) => throw StateError('not loaded');

  @override
  SeekoKeyLookup<String> lookupKey(String key) =>
      const SeekoKeyLookup<String>.notLoaded();

  @override
  SeekoKeyLookup<String> captureIndex(int index) =>
      const SeekoKeyLookup<String>.notLoaded();
}
