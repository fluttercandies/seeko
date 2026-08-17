import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  testWidgets('PageStorage keeps semantic anchors beside Flutter pixel state',
      (WidgetTester tester) async {
    final PageStorageBucket bucket = PageStorageBucket();
    final SeekoRestorationAnchor<String> anchor =
        SeekoRestorationAnchor<String>(
      driverKind: 'tagged',
      key: 'message-42',
      lastKnownIndex: 41,
      itemAnchor: 0.25,
      viewportAnchor: 0.5,
      logicalOffset: -8,
      fallbackProgress: 0.7,
    );
    late double nativePixels;
    late SeekoRestorationAnchor<String>? restored;

    await tester.pumpWidget(
      PageStorage(
        bucket: bucket,
        child: KeyedSubtree(
          key: const PageStorageKey<String>('feed'),
          child: Builder(
            builder: (BuildContext context) {
              bucket.writeState(context, 320.0);
              SeekoPageStorage.write(
                context,
                storageKey: 'messages',
                anchor: anchor,
              );
              nativePixels = bucket.readState(context)! as double;
              restored = SeekoPageStorage.read<String>(
                context,
                storageKey: 'messages',
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(nativePixels, 320);
    expect(restored, anchor);
  });

  testWidgets('controller saves and restores its anchor through PageStorage',
      (WidgetTester tester) async {
    final PageStorageBucket bucket = PageStorageBucket();
    final ValueNotifier<int> revision = ValueNotifier<int>(2);
    final List<String> items =
        List<String>.generate(20, (int index) => 'item-$index');
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    late BuildContext storageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: KeyedSubtree(
            key: const PageStorageKey<String>('feed'),
            child: Builder(
              builder: (BuildContext context) {
                storageContext = context;
                return _taggedViewport(controller, items);
              },
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(250);
    await tester.pump();

    expect(
      controller.saveRestorationToPageStorage(
        storageContext,
        storageKey: 'messages',
      ),
      isTrue,
    );
    controller.jumpTo(0);
    await tester.pump();
    final Future<ScrollResult?> future =
        controller.restoreRestorationFromPageStorage(
      storageContext,
      storageKey: 'messages',
    );
    await _pumpUntilNullableComplete(tester, future);
    final ScrollResult? result = await future;

    expect(result, isNotNull);
    expect(result!.outcome, ScrollOutcome.completed);
    expect(controller.offset, closeTo(250, 0.5));
    expect(controller.state.value.origin, ScrollEventOrigin.restoration);
    controller.dispose();
    revision.dispose();
  });

  testWidgets('missing PageStorage anchor returns null without movement',
      (WidgetTester tester) async {
    final PageStorageBucket bucket = PageStorageBucket();
    final SeekoController controller = SeekoController();
    late BuildContext storageContext;
    final List<String> items =
        List<String>.generate(10, (int index) => 'item-$index');
    await tester.pumpWidget(
      MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: KeyedSubtree(
            key: const PageStorageKey<String>('feed'),
            child: Builder(
              builder: (BuildContext context) {
                storageContext = context;
                return _taggedViewport(controller, items);
              },
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(200);
    await tester.pump();

    final ScrollResult? result =
        await controller.restoreRestorationFromPageStorage(
      storageContext,
      storageKey: 'missing',
    );

    expect(result, isNull);
    expect(controller.offset, closeTo(200, 0.5));
    controller.dispose();
  });

  testWidgets('RestorableSeekoAnchor survives a Flutter restoration restart',
      (WidgetTester tester) async {
    final GlobalKey<_RestorationHostState> key =
        GlobalKey<_RestorationHostState>();
    await tester.pumpWidget(
      RootRestorationScope(
        restorationId: 'root',
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _RestorationHost(key: key),
        ),
      ),
    );

    key.currentState!.setAnchor(SeekoRestorationAnchor<String>(
      driverKind: 'indexed-sliver',
      key: 'message-99',
      lastKnownIndex: 98,
      itemAnchor: 0,
      viewportAnchor: 0.5,
      logicalOffset: 4,
      dataRevisionHint: 7,
      fallbackProgress: 0.8,
    ));
    await tester.pump();
    expect(find.text('message-99'), findsOneWidget);

    await tester.restartAndRestore();

    expect(find.text('message-99'), findsOneWidget);
    expect(key.currentState!.anchor.value!.lastKnownIndex, 98);
    expect(key.currentState!.anchor.value!.dataRevisionHint, 7);
  });

  testWidgets('controller captures the current semantic restoration anchor',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(7);
    final List<String> items =
        List<String>.generate(20, (int index) => 'item-$index');
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));
    controller.jumpTo(250);
    await tester.pump();

    final SeekoRestorationAnchor<String>? anchor =
        controller.captureRestorationAnchor<String>();

    expect(anchor, isNotNull);
    expect(anchor!.driverKind, 'tagged');
    expect(anchor.key, 'item-2');
    expect(anchor.lastKnownIndex, 2);
    expect(anchor.itemAnchor, closeTo(0.5, 0.001));
    expect(anchor.viewportAnchor, 0);
    expect(anchor.logicalOffset, 0);
    expect(anchor.dataRevisionHint, 7);
    expect(anchor.fallbackProgress, closeTo(250 / 1700, 0.001));
    controller.dispose();
    revision.dispose();
  });

  testWidgets('capture rejects a mismatched requested key type actionably',
      (WidgetTester tester) async {
    final SeekoController controller = SeekoController();
    final List<String> items =
        List<String>.generate(10, (int index) => 'item-$index');
    await tester.pumpWidget(_taggedList(controller, items));

    expect(
      controller.captureRestorationAnchor<int>,
      throwsA(
        isA<StateError>()
            .having(
              (StateError error) => error.message.toString(),
              'message',
              contains('SeekoRestorationAnchor<int>'),
            )
            .having(
              (StateError error) => error.message.toString(),
              'message',
              contains('runtime type String'),
            ),
      ),
    );
    controller.dispose();
  });

  testWidgets('controller restores an exact anchor with restoration origin',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(3);
    final List<String> items =
        List<String>.generate(20, (int index) => 'item-$index');
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));

    final Future<ScrollResult> future = controller.restoreRestorationAnchor(
      SeekoRestorationAnchor<Object>(
        driverKind: 'tagged',
        key: 'item-8',
        lastKnownIndex: 8,
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
        dataRevisionHint: 2,
        fallbackProgress: 0.5,
      ),
    );
    await _pumpUntilComplete(tester, future);
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.requestedTarget, ScrollTarget.key('item-8'));
    expect(result.capturedTarget, ScrollTarget.key('item-8'));
    expect(result.resolutionMode, ScrollResolutionMode.exact);
    expect(controller.offset, closeTo(800, 0.5));
    expect(controller.state.value.origin, ScrollEventOrigin.restoration);
    controller.dispose();
    revision.dispose();
  });

  testWidgets('restoration movement emits raw events with restoration origin',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(3);
    final List<String> items =
        List<String>.generate(20, (int index) => 'item-$index');
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));
    final List<ScrollRawEvent> events = <ScrollRawEvent>[];
    final StreamSubscription<ScrollRawEvent> subscription =
        controller.rawEvents.listen(events.add);

    final Future<ScrollResult> future = controller.restoreRestorationAnchor(
      SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'item-8',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ),
    );
    await _pumpUntilComplete(tester, future);
    await future;

    expect(events, isNotEmpty);
    expect(
      events.where(
        (ScrollRawEvent event) => event.origin == ScrollEventOrigin.restoration,
      ),
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(subscription.cancel());
    controller.dispose();
    revision.dispose();
  });

  testWidgets('controller applies index-hint restoration as fallback',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(4);
    final List<String> items = <String>['a', 'b', 'replacement', 'd', 'e'];
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));

    final Future<ScrollResult> future = controller.restoreRestorationAnchor(
      SeekoRestorationAnchor<Object>(
        driverKind: 'tagged',
        key: 'deleted',
        lastKnownIndex: 2,
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
        dataRevisionHint: 1,
        fallbackProgress: 0.5,
      ),
    );
    await _pumpUntilComplete(tester, future);
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.requestedTarget, ScrollTarget.key('deleted'));
    expect(result.capturedTarget, ScrollTarget.key('replacement'));
    expect(result.resolutionMode, ScrollResolutionMode.fallback);
    expect(result.diagnostics, containsPair('fallbackStep', 'indexHint'));
    expect(controller.offset, closeTo(200, 0.5));
    expect(controller.state.value.origin, ScrollEventOrigin.restoration);
    controller.dispose();
    revision.dispose();
  });

  testWidgets('controller preserves typed restoration resolver contexts',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(4);
    final List<String> items =
        List<String>.generate(10, (int index) => 'item-$index');
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));

    final Future<ScrollResult> future = controller.restoreRestorationAnchor(
      SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'deleted',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ),
      policy: SeekoRestorationPolicy<String>(
        steps: const <SeekoRestorationFallbackStep>[
          SeekoRestorationFallbackStep.resolver,
        ],
        resolver: (SeekoRestorationContext<String> context) =>
            ScrollTarget.key(context.delegate.keyAt(4)),
      ),
    );
    await _pumpUntilComplete(tester, future);
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('item-4'));
    expect(result.resolutionMode, ScrollResolutionMode.fallback);
    controller.dispose();
    revision.dispose();
  });

  testWidgets('restoration preserves target-not-loaded as a typed outcome',
      (WidgetTester tester) async {
    final _NotLoadedStringDelegate delegate = _NotLoadedStringDelegate();
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
    );
    final List<String> items =
        List<String>.generate(10, (int index) => 'item-$index');
    await tester.pumpWidget(_taggedList(controller, items));
    controller.jumpTo(200);
    await tester.pump();

    final Future<ScrollResult> future = controller.restoreRestorationAnchor(
      SeekoRestorationAnchor<String>(
        driverKind: 'paged',
        key: 'remote-item',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ),
    );
    await _pumpUntilComplete(tester, future);
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.targetNotLoaded);
    expect(result.requestedTarget, ScrollTarget.key('remote-item'));
    expect(result.capturedTarget, ScrollTarget.key('remote-item'));
    expect(result.resolutionMode, ScrollResolutionMode.exact);
    expect(result.diagnostics, containsPair('keyStatus', 'notLoaded'));
    expect(controller.offset, closeTo(200, 0.5));
    expect(controller.state.value.origin, ScrollEventOrigin.restoration);
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('failed restoration policy returns a deterministic outcome',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(5);
    final List<String> items =
        List<String>.generate(10, (int index) => 'item-$index');
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));
    controller.jumpTo(200);
    await tester.pump();

    final Future<ScrollResult> future = controller.restoreRestorationAnchor(
      SeekoRestorationAnchor<String>(
        driverKind: 'tagged',
        key: 'deleted',
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ),
      policy: SeekoRestorationPolicy<String>(
        steps: const <SeekoRestorationFallbackStep>[
          SeekoRestorationFallbackStep.fail,
        ],
      ),
    );
    await _pumpUntilComplete(tester, future);
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.targetDeleted);
    expect(result.requestedTarget, ScrollTarget.key('deleted'));
    expect(result.capturedTarget, isNull);
    expect(result.resolutionMode, ScrollResolutionMode.fallback);
    expect(result.diagnostics, containsPair('fallbackStep', 'fail'));
    expect(controller.offset, closeTo(200, 0.5));
    expect(controller.state.value.origin, ScrollEventOrigin.restoration);
    controller.dispose();
    revision.dispose();
  });

  testWidgets('controller restores codec failure metadata through fallback',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(5);
    final List<String> items = <String>['a', 'b', 'replacement', 'd', 'e'];
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));

    final Future<ScrollResult> future = controller.restoreRestorationFallback(
      SeekoRestorationFallbackState(
        driverKind: 'tagged',
        lastKnownIndex: 2,
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
        dataRevisionHint: 1,
        fallbackProgress: 0.5,
        cause: const SeekoRestorationFormatException('codec mismatch'),
      ),
    );
    await _pumpUntilComplete(tester, future);
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('replacement'));
    expect(result.resolutionMode, ScrollResolutionMode.fallback);
    expect(result.diagnostics, containsPair('fallbackStep', 'indexHint'));
    expect(result.diagnostics!['restorationFailure'], contains('codec'));
    expect(controller.offset, closeTo(200, 0.5));
    expect(controller.state.value.origin, ScrollEventOrigin.restoration);
    controller.dispose();
    revision.dispose();
  });

  testWidgets('requireExact rejects restoration fallback before movement',
      (WidgetTester tester) async {
    final ValueNotifier<int> revision = ValueNotifier<int>(4);
    final List<String> items = <String>['a', 'b', 'replacement', 'd', 'e'];
    final SeekoController controller = SeekoController(
      indexDelegate: ListSeekoIndexDelegate<String>(
        itemCount: items.length,
        revision: revision,
        keyAt: (int index) => items[index],
        indexOfKey: items.indexOf,
      ),
    );
    await tester.pumpWidget(_taggedList(controller, items));

    final Future<ScrollResult> future = controller.restoreRestorationAnchor(
      SeekoRestorationAnchor<Object>(
        driverKind: 'tagged',
        key: 'deleted',
        lastKnownIndex: 2,
        itemAnchor: 0,
        viewportAnchor: 0,
        logicalOffset: 0,
      ),
      options: const ScrollCommandOptions(
        resolutionPolicy: ScrollResolutionPolicy(requireExact: true),
      ),
    );
    await _pumpUntilComplete(tester, future);
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.unsupported);
    expect(result.resolutionMode, ScrollResolutionMode.fallback);
    expect(controller.offset, 0);
    controller.dispose();
    revision.dispose();
  });

  test('restorable codec mismatch exposes fallback metadata without crashing',
      () {
    const _StringCodec storedCodec = _StringCodec('stored');
    const _StringCodec currentCodec = _StringCodec('current');
    final Map<String, Object?> payload = SeekoRestorationAnchor<String>(
      driverKind: 'tagged',
      key: 'message-7',
      lastKnownIndex: 6,
      itemAnchor: 0.25,
      viewportAnchor: 0.5,
      logicalOffset: -4,
      fallbackProgress: 0.4,
    ).encode(storedCodec);
    final RestorableSeekoAnchor<String> property =
        RestorableSeekoAnchor<String>(codec: currentCodec);

    final SeekoRestorationAnchor<String>? restored =
        property.fromPrimitives(payload);

    expect(restored, isNull);
    expect(property.decodeFailure, isNotNull);
    expect(property.decodeFailure!.fallbackState!.lastKnownIndex, 6);
    expect(property.decodeFailure!.fallbackState!.fallbackProgress, 0.4);
    property.dispose();
  });
}

final class _RestorationHost extends StatefulWidget {
  const _RestorationHost({super.key});

  @override
  State<_RestorationHost> createState() => _RestorationHostState();
}

final class _RestorationHostState extends State<_RestorationHost>
    with RestorationMixin {
  final RestorableSeekoAnchor<String> anchor =
      RestorableSeekoAnchor<String>(codec: const _StringCodec('messages'));

  @override
  String get restorationId => 'seeko-host';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(anchor, 'anchor');
  }

  void setAnchor(SeekoRestorationAnchor<String> value) {
    setState(() => anchor.value = value);
  }

  @override
  Widget build(BuildContext context) => Text(anchor.value?.key ?? 'none');

  @override
  void dispose() {
    anchor.dispose();
    super.dispose();
  }
}

final class _StringCodec implements SeekoKeyCodec<String> {
  const _StringCodec(this.namespace);

  @override
  final String namespace;

  @override
  int get schemaVersion => 1;

  @override
  String decode(Object? value) => value! as String;

  @override
  Object? encode(String key) => key;
}

final class _NotLoadedStringDelegate extends ChangeNotifier
    implements SeekoIndexDelegate<String> {
  @override
  int get revision => 1;

  @override
  int? get itemCount => null;

  @override
  LoadedRangeSet get loadedRanges => LoadedRangeSet(const <IndexRange>[]);

  @override
  Listenable get changes => this;

  @override
  String keyAt(int index) {
    throw StateError('No remote keys are loaded.');
  }

  @override
  SeekoKeyLookup<String> lookupKey(String key) =>
      const SeekoKeyLookup<String>.notLoaded();

  @override
  SeekoKeyLookup<String> captureIndex(int index) =>
      const SeekoKeyLookup<String>.notLoaded();
}

Widget _taggedList(SeekoController controller, List<String> items) {
  return MaterialApp(
    home: _taggedViewport(controller, items),
  );
}

Widget _taggedViewport(SeekoController controller, List<String> items) {
  return Align(
    alignment: Alignment.topCenter,
    child: SizedBox(
      height: 300,
      child: SingleChildScrollView(
        controller: controller,
        child: Column(
          children: List<Widget>.generate(
            items.length,
            (int index) => SeekoTag(
              controller: controller,
              targetKey: items[index],
              index: index,
              child: SizedBox(height: 100, child: Text(items[index])),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntilComplete(
  WidgetTester tester,
  Future<ScrollResult> future,
) async {
  var complete = false;
  unawaited(future.whenComplete(() => complete = true));
  for (var frame = 0; frame < 20 && !complete; frame += 1) {
    await tester.pump();
  }
  expect(complete, isTrue);
}

Future<void> _pumpUntilNullableComplete(
  WidgetTester tester,
  Future<ScrollResult?> future,
) async {
  var complete = false;
  unawaited(future.whenComplete(() => complete = true));
  for (var frame = 0; frame < 20 && !complete; frame += 1) {
    await tester.pump();
  }
  expect(complete, isTrue);
}
