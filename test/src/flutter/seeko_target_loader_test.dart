import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

import '../../support/scroll_command_tester.dart';

void main() {
  testWidgets('unloaded index loads and scrolls in one command result', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    var loadCount = 0;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        loadCount += 1;
        expectSync(request.target, ScrollTarget.index(80));
        delegate.loadThrough(100);
        return ScrollTargetLoadResult.loaded(revision: delegate.revision);
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToIndex(
        80,
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 20,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('remote-80'));
    expect(result.startRevision, 0);
    expect(result.endRevision, 1);
    expect(loadCount, 1);
    expect(controller.offset, closeTo(4800, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('loader retry stays inside the original command', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    var loadCount = 0;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoadPolicy: ScrollTargetLoadPolicy(
        maxAttempts: 2,
        initialRetryDelay: Duration.zero,
        maxRetryDelay: Duration.zero,
      ),
      targetLoader: CallbackScrollTargetLoader((request) {
        loadCount += 1;
        if (request.attempt == 1) {
          return ScrollTargetLoadResult.retry();
        }
        delegate.loadThrough(100);
        return ScrollTargetLoadResult.loaded(revision: delegate.revision);
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey('remote-80'),
      maxFrames: 20,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(loadCount, 2);
    expect(result.commandId, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('unloaded index animates after loading in the same command', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        delegate.loadThrough(100);
        return ScrollTargetLoadResult.loaded(revision: delegate.revision);
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.animateToIndex(
        80,
        placement: const ScrollPlacement.start(),
        motion: const ScrollMotion.duration(
          duration: Duration(milliseconds: 160),
          curve: Curves.easeInOutCubic,
        ),
      ),
      maxFrames: 30,
      frameDuration: const Duration(milliseconds: 16),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('remote-80'));
    expect(result.startRevision, 0);
    expect(result.endRevision, 1);
    expect(controller.offset, closeTo(4800, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('loaded result waits for the committed data revision', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    var loadCount = 0;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        loadCount += 1;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          delegate.loadThrough(100);
        });
        return ScrollTargetLoadResult.loaded();
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'remote-80',
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 20,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.startRevision, 0);
    expect(result.endRevision, 1);
    expect(loadCount, 1);
    expect(controller.offset, closeTo(4800, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('loader not-found remains distinct from not-loaded', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        return ScrollTargetLoadResult.notFound(
          outcome: ScrollOutcome.targetDeleted,
          diagnostic: 'server-confirmed-absence',
        );
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey('remote-80'),
    );

    expect(result.outcome, ScrollOutcome.targetDeleted);
    expect(result.diagnostics?['targetLoader'], 'server-confirmed-absence');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('loaded revision reports a target deleted during loading', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        delegate.delete(80);
        return ScrollTargetLoadResult.loaded(revision: delegate.revision);
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey('remote-80'),
    );

    expect(result.outcome, ScrollOutcome.targetDeleted);
    expect(result.startRevision, 0);
    expect(result.endRevision, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('head pagination follows the stable target into its new index', (
    WidgetTester tester,
  ) async {
    final _MutablePagedIndexDelegate delegate =
        _MutablePagedIndexDelegate(loadedCount: 10);
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        delegate.prependAndLoad(5);
        return ScrollTargetLoadResult.loaded(revision: delegate.revision);
      }),
    );
    await tester.pumpWidget(
      _mutablePagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey(
        'remote-80',
        placement: const ScrollPlacement.start(),
      ),
      maxFrames: 30,
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(result.capturedTarget, ScrollTarget.key('remote-80'));
    expect(result.startRevision, 0);
    expect(result.endRevision, 1);
    expect(delegate.lookupKey('remote-80').index, 85);
    expect(controller.offset, closeTo(85 * 60, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('loader exceptions retry within bounds and stay diagnostic', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    var loadCount = 0;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoadPolicy: ScrollTargetLoadPolicy(
        maxAttempts: 2,
        initialRetryDelay: Duration.zero,
        maxRetryDelay: Duration.zero,
      ),
      targetLoader: CallbackScrollTargetLoader((request) {
        loadCount += 1;
        throw StateError('remote-loader-failed');
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey('remote-80'),
    );

    expect(result.outcome, ScrollOutcome.resolverRejected);
    expect(loadCount, 2);
    expect(result.diagnostics?['targetLoaderAttempts'], 2);
    expect(
      result.diagnostics?['targetLoader'],
      isA<StateError>().having(
        (StateError error) => error.message,
        'message',
        'remote-loader-failed',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('loaded without a visible revision remains bounded not-loaded', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    var loadCount = 0;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoadPolicy: ScrollTargetLoadPolicy(
        maxAttempts: 2,
        initialRetryDelay: Duration.zero,
        maxRetryDelay: Duration.zero,
      ),
      targetLoader: CallbackScrollTargetLoader((request) {
        loadCount += 1;
        return ScrollTargetLoadResult.loaded(revision: delegate.revision);
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final ScrollResult result = await pumpScrollCommand(
      tester,
      controller.jumpToKey('remote-80'),
      maxFrames: 20,
    );

    expect(result.outcome, ScrollOutcome.targetNotLoaded);
    expect(loadCount, 2);
    expect(result.diagnostics?['targetLoaderAttempts'], 2);
    expect(result.diagnostics?['targetLoaderRevision'], 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('stop cancels a non-cooperative pending loader immediately', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    final Completer<ScrollTargetLoadResult> pending =
        Completer<ScrollTargetLoadResult>();
    ScrollCancellationToken? loaderCancellation;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        loaderCancellation = request.cancellationToken;
        return pending.future;
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final Future<ScrollResult> future = controller.jumpToKey('remote-80');
    await tester.pump();
    controller.stop();
    await tester.pump();
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.cancelled);
    expect(loaderCancellation?.isCancelled, isTrue);
    expect(pending.isCompleted, isFalse);

    pending.complete(ScrollTargetLoadResult.loaded());
    await tester.pump();
    await tester.pump();
    expect(controller.offset, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('replace cancels the previous pending target load', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    final Completer<ScrollTargetLoadResult> firstPending =
        Completer<ScrollTargetLoadResult>();
    ScrollCancellationToken? firstCancellation;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        if (request.target == ScrollTarget.key('remote-80')) {
          firstCancellation = request.cancellationToken;
          return firstPending.future;
        }
        delegate.loadThrough(100);
        return ScrollTargetLoadResult.loaded(revision: delegate.revision);
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final Future<ScrollResult> first = controller.jumpToKey('remote-80');
    await tester.pump();
    final Future<ScrollResult> second = controller.jumpToKey('remote-20');
    final ScrollResult firstResult = await first;
    final ScrollResult secondResult = await pumpScrollCommand(tester, second);

    expect(firstResult.outcome, ScrollOutcome.superseded);
    expect(firstCancellation?.isCancelled, isTrue);
    expect(firstCancellation?.reason, ScrollStopReason.superseded);
    expect(firstPending.isCompleted, isFalse);
    expect(secondResult.outcome, ScrollOutcome.completed);
    expect(secondResult.commandId, firstResult.commandId + 1);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('stop cancels a pending retry delay without waiting', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    var loadCount = 0;
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        loadCount += 1;
        return ScrollTargetLoadResult.retry(
          retryAfter: const Duration(seconds: 1),
        );
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final Future<ScrollResult> future = controller.jumpToKey('remote-80');
    await tester.pump();
    controller.stop();
    await tester.pump();
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.cancelled);
    expect(loadCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });

  testWidgets('command deadline terminates a pending loader', (
    WidgetTester tester,
  ) async {
    final _PagedIndexDelegate delegate = _PagedIndexDelegate(loadedCount: 10);
    final SeekoController controller = SeekoController(
      indexDelegate: delegate,
      targetLoader: CallbackScrollTargetLoader((request) {
        return Completer<ScrollTargetLoadResult>().future;
      }),
    );
    await tester.pumpWidget(
      _pagedScrollView(controller: controller, delegate: delegate),
    );

    final Future<ScrollResult> future = controller.jumpToKey(
      'remote-80',
      options: ScrollCommandOptions(
        executionPolicy: ScrollExecutionPolicy(
          deadline: Duration(milliseconds: 50),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final ScrollResult result = await future;

    expect(result.outcome, ScrollOutcome.timedOut);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    delegate.dispose();
  });
}

Widget _pagedScrollView({
  required SeekoController controller,
  required _PagedIndexDelegate delegate,
}) {
  return MaterialApp(
    home: SizedBox(
      height: 300,
      child: CustomScrollView(
        controller: controller,
        slivers: <Widget>[
          SeekoIndexedSliver(
            controller: controller,
            indexDelegate: delegate,
            estimatedExtent: 60,
            delegate: SliverChildBuilderDelegate(
              (_, int index) => SizedBox(
                height: 60,
                child: Text('Remote item $index'),
              ),
              childCount: delegate.itemCount,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _mutablePagedScrollView({
  required SeekoController controller,
  required _MutablePagedIndexDelegate delegate,
}) {
  return MaterialApp(
    home: SizedBox(
      height: 300,
      child: ListenableBuilder(
        listenable: delegate.changes,
        builder: (BuildContext context, Widget? child) {
          return CustomScrollView(
            controller: controller,
            slivers: <Widget>[
              SeekoIndexedSliver(
                controller: controller,
                indexDelegate: delegate,
                estimatedExtent: 60,
                delegate: SliverChildBuilderDelegate(
                  (_, int index) => SizedBox(
                    height: 60,
                    child: Text(delegate.keyAt(index)),
                  ),
                  childCount: delegate.itemCount,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

final class _PagedIndexDelegate implements SeekoIndexDelegate<String> {
  _PagedIndexDelegate({required int loadedCount})
      : _loadedCount = loadedCount,
        _changes = ValueNotifier<int>(0);

  int _loadedCount;
  final ValueNotifier<int> _changes;
  final Set<int> _deletedIndexes = <int>{};

  @override
  int get itemCount => 100;

  @override
  int get revision => _changes.value;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, _loadedCount)]);

  @override
  Listenable get changes => _changes;

  @override
  String keyAt(int index) => 'remote-$index';

  @override
  SeekoKeyLookup<String> lookupKey(String key) {
    if (!key.startsWith('remote-')) {
      return const SeekoKeyLookup<String>.absent();
    }
    final int? index = int.tryParse(key.substring('remote-'.length));
    if (index == null || index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<String>.absent();
    }
    if (_deletedIndexes.contains(index)) {
      return const SeekoKeyLookup<String>.absent();
    }
    if (index >= _loadedCount) {
      return const SeekoKeyLookup<String>.notLoaded();
    }
    return SeekoKeyLookup<String>.found(index, key: key);
  }

  @override
  SeekoKeyLookup<String> captureIndex(int index) {
    if (index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<String>.absent();
    }
    if (index >= _loadedCount) {
      return const SeekoKeyLookup<String>.notLoaded();
    }
    return SeekoKeyLookup<String>.found(index, key: keyAt(index));
  }

  void loadThrough(int count) {
    _loadedCount = count.clamp(0, itemCount);
    _changes.value += 1;
  }

  void delete(int index) {
    _deletedIndexes.add(index);
    _changes.value += 1;
  }

  void dispose() => _changes.dispose();
}

final class _MutablePagedIndexDelegate implements SeekoIndexDelegate<String> {
  _MutablePagedIndexDelegate({required int loadedCount})
      : _loadedCount = loadedCount,
        _keys = List<String>.generate(100, (int index) => 'remote-$index'),
        _changes = SeekoChangeNotifier();

  int _loadedCount;
  final List<String> _keys;
  final SeekoChangeNotifier _changes;
  final Map<String, int> _indexes = <String, int>{};

  @override
  int get itemCount => _keys.length;

  @override
  int get revision => _changes.revision;

  @override
  LoadedRangeSet get loadedRanges =>
      LoadedRangeSet(<IndexRange>[IndexRange(0, _loadedCount)]);

  @override
  Listenable get changes => _changes;

  @override
  String keyAt(int index) => _keys[index];

  @override
  SeekoKeyLookup<String> lookupKey(String key) {
    _ensureIndexes();
    final int? index = _indexes[key];
    if (index == null) {
      return const SeekoKeyLookup<String>.absent();
    }
    if (index >= _loadedCount) {
      return const SeekoKeyLookup<String>.notLoaded();
    }
    return SeekoKeyLookup<String>.found(index, key: key);
  }

  @override
  SeekoKeyLookup<String> captureIndex(int index) {
    if (index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<String>.absent();
    }
    if (index >= _loadedCount) {
      return const SeekoKeyLookup<String>.notLoaded();
    }
    return SeekoKeyLookup<String>.found(index, key: keyAt(index));
  }

  void prependAndLoad(int count) {
    final int beforeRevision = revision;
    _keys.insertAll(
      0,
      List<String>.generate(count, (int index) => 'history-$index'),
    );
    _loadedCount = _keys.length;
    _indexes.clear();
    _changes.publish(
      SeekoChangeSet(
        beforeRevision: beforeRevision,
        afterRevision: beforeRevision + 1,
        changes: <SeekoChange>[
          SeekoChange.insert(index: 0, count: count),
        ],
      ),
    );
  }

  void _ensureIndexes() {
    if (_indexes.length == _keys.length) {
      return;
    }
    for (var index = 0; index < _keys.length; index += 1) {
      _indexes[_keys[index]] = index;
    }
  }

  void dispose() => _changes.dispose();
}
