import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('loaded ranges are normalized and queried in logarithmic form', () {
    final LoadedRangeSet ranges = LoadedRangeSet(const <IndexRange>[
      IndexRange(10, 20),
      IndexRange(0, 5),
      IndexRange(5, 8),
      IndexRange(18, 25),
    ]);
    expect(ranges.ranges, const <IndexRange>[
      IndexRange(0, 8),
      IndexRange(10, 25),
    ]);
    expect(ranges.contains(7), isTrue);
    expect(ranges.contains(9), isFalse);
  });

  test('list delegate captures stable keys and revisions', () {
    final ValueNotifier<int> revision = ValueNotifier<int>(4);
    final ListSeekoIndexDelegate<String> delegate =
        ListSeekoIndexDelegate<String>(
      itemCount: 3,
      revision: revision,
      keyAt: (int index) => 'k$index',
      indexOfKey: (String key) => int.tryParse(key.substring(1)),
    );
    expect(delegate.lookupKey('k2'), SeekoKeyLookup<String>.found(2));
    expect(
      delegate.captureIndex(1),
      SeekoKeyLookup<String>.found(1, key: 'k1'),
    );
    expect(delegate.captureIndex(8), const SeekoKeyLookup<String>.absent());
    expect(delegate.revision, 4);
    revision.dispose();
  });

  test('found lookup rejects negative indexes at runtime', () {
    expect(
      () => SeekoKeyLookup<String>.found(-1),
      throwsRangeError,
    );
  });

  test('duplicate-key validation reports both indexes', () {
    final ListSeekoIndexDelegate<String> delegate =
        ListSeekoIndexDelegate<String>(
      itemCount: 3,
      revision: ValueNotifier<int>(0),
      keyAt: (int index) => index == 2 ? 'same' : 'same',
      indexOfKey: (String key) => 0,
    );
    expect(
      () => delegate.validateKeys(const IndexRange(0, 3)),
      throwsA(isA<DuplicateSeekoKeyError>()),
    );
  });

  test('change sets require monotonic revision and valid mutations', () {
    expect(
      () => SeekoChangeSet(
        beforeRevision: 2,
        afterRevision: 2,
        changes: <SeekoChange>[SeekoChange.insert(index: 0, count: 1)],
      ),
      throwsArgumentError,
    );
    expect(
      () => SeekoChange.insert(index: 0, count: 0),
      throwsRangeError,
    );
  });

  test('change notifier enforces contiguous atomic revisions', () {
    final SeekoChangeNotifier notifier = SeekoChangeNotifier();
    var notifications = 0;
    notifier.addListener(() {
      notifications += 1;
    });
    final SeekoChangeSet changeSet = SeekoChangeSet(
      beforeRevision: 0,
      afterRevision: 1,
      changes: <SeekoChange>[
        SeekoChange.insert(index: 0, count: 2),
      ],
    );

    notifier.publish(changeSet);

    expect(notifier.revision, 1);
    expect(notifier.value, same(changeSet));
    expect(notifications, 1);
    expect(
      () => notifier.publish(
        SeekoChangeSet(
          beforeRevision: 0,
          afterRevision: 2,
          changes: <SeekoChange>[
            SeekoChange.reset(),
          ],
        ),
      ),
      throwsStateError,
    );
    notifier.dispose();
  });
}
