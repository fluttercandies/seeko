import 'dart:collection';

import 'package:flutter/foundation.dart';

/// A half-open range of logical item indexes.
final class IndexRange {
  const IndexRange(this.start, this.end)
      : assert(start >= 0),
        assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;
  bool contains(int index) => index >= start && index < end;

  @override
  bool operator ==(Object other) =>
      other is IndexRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Sorted, non-overlapping loaded ranges.
final class LoadedRangeSet {
  LoadedRangeSet(Iterable<IndexRange> source) : ranges = _normalize(source);

  final List<IndexRange> ranges;

  bool contains(int index) {
    var low = 0;
    var high = ranges.length - 1;
    while (low <= high) {
      final int middle = low + ((high - low) >> 1);
      final IndexRange range = ranges[middle];
      if (index < range.start) {
        high = middle - 1;
      } else if (index >= range.end) {
        low = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  static List<IndexRange> _normalize(Iterable<IndexRange> source) {
    final List<IndexRange> sorted = source.toList()
      ..sort((IndexRange a, IndexRange b) => a.start.compareTo(b.start));
    final List<IndexRange> result = <IndexRange>[];
    for (final IndexRange range in sorted) {
      if (range.length == 0) {
        continue;
      }
      if (result.isEmpty || range.start > result.last.end) {
        result.add(range);
      } else {
        final IndexRange previous = result.removeLast();
        result.add(IndexRange(previous.start, _max(previous.end, range.end)));
      }
    }
    return UnmodifiableListView<IndexRange>(result);
  }
}

enum SeekoKeyLookupStatus { found, notLoaded, absent }

/// A typed key/index lookup that preserves loading and absence semantics.
final class SeekoKeyLookup<K> {
  factory SeekoKeyLookup.found(int index, {K? key}) {
    RangeError.checkNotNegative(index, 'index');
    return SeekoKeyLookup<K>._(
      SeekoKeyLookupStatus.found,
      index,
      key,
    );
  }

  const SeekoKeyLookup.notLoaded()
      : this._(SeekoKeyLookupStatus.notLoaded, null, null);

  const SeekoKeyLookup.absent()
      : this._(SeekoKeyLookupStatus.absent, null, null);

  const SeekoKeyLookup._(this.status, this.index, this.key);

  final SeekoKeyLookupStatus status;
  final int? index;
  final K? key;

  bool get isFound => status == SeekoKeyLookupStatus.found;

  @override
  bool operator ==(Object other) =>
      other is SeekoKeyLookup<K> &&
      other.status == status &&
      other.index == index &&
      other.key == key;

  @override
  int get hashCode => Object.hash(status, index, key);
}

sealed class SeekoChange {
  const SeekoChange._();

  factory SeekoChange.insert({required int index, required int count}) {
    _validateRange(index, count);
    return SeekoInsertChange._(index, count);
  }

  factory SeekoChange.remove({required int index, required int count}) {
    _validateRange(index, count);
    return SeekoRemoveChange._(index, count);
  }

  factory SeekoChange.move({
    required int from,
    required int to,
    required int count,
  }) {
    _validateRange(from, count);
    RangeError.checkNotNegative(to, 'to');
    return SeekoMoveChange._(from, to, count);
  }

  factory SeekoChange.update({required int index, required int count}) {
    _validateRange(index, count);
    return SeekoUpdateChange._(index, count);
  }

  const factory SeekoChange.reset() = SeekoResetChange._;
}

final class SeekoInsertChange extends SeekoChange {
  const SeekoInsertChange._(this.index, this.count) : super._();
  final int index;
  final int count;
}

final class SeekoRemoveChange extends SeekoChange {
  const SeekoRemoveChange._(this.index, this.count) : super._();
  final int index;
  final int count;
}

final class SeekoMoveChange extends SeekoChange {
  const SeekoMoveChange._(this.from, this.to, this.count) : super._();
  final int from;
  final int to;
  final int count;
}

final class SeekoUpdateChange extends SeekoChange {
  const SeekoUpdateChange._(this.index, this.count) : super._();
  final int index;
  final int count;
}

final class SeekoResetChange extends SeekoChange {
  const SeekoResetChange._() : super._();
}

final class SeekoChangeSet {
  factory SeekoChangeSet({
    required int beforeRevision,
    required int afterRevision,
    required Iterable<SeekoChange> changes,
  }) {
    if (afterRevision <= beforeRevision) {
      throw ArgumentError('afterRevision must be greater than beforeRevision');
    }
    final List<SeekoChange> values = List<SeekoChange>.unmodifiable(changes);
    if (values.isEmpty) {
      throw ArgumentError.value(changes, 'changes', 'must not be empty');
    }
    return SeekoChangeSet._(beforeRevision, afterRevision, values);
  }

  const SeekoChangeSet._(
    this.beforeRevision,
    this.afterRevision,
    this.changes,
  );

  final int beforeRevision;
  final int afterRevision;
  final List<SeekoChange> changes;
}

/// Publishes atomic data mutations together with their revision transition.
///
/// [SeekoIndexedSliver] consumes this notifier incrementally, retaining
/// unaffected sparse extent measurements across inserts, removals, moves, and
/// updates. Delegates that expose only a plain [Listenable] remain compatible
/// but require a conservative extent-index reset after each notification.
final class SeekoChangeNotifier extends ChangeNotifier
    implements ValueListenable<SeekoChangeSet?> {
  SeekoChangeNotifier({int initialRevision = 0})
      : _revision = RangeError.checkNotNegative(
          initialRevision,
          'initialRevision',
        );

  int _revision;
  SeekoChangeSet? _value;

  int get revision => _revision;

  @override
  SeekoChangeSet? get value => _value;

  void publish(SeekoChangeSet changeSet) {
    if (changeSet.beforeRevision != _revision) {
      throw StateError(
        'SeekoChangeSet.beforeRevision ${changeSet.beforeRevision} does not '
        'match the current revision $_revision.',
      );
    }
    _revision = changeSet.afterRevision;
    _value = changeSet;
    notifyListeners();
  }
}

abstract interface class SeekoIndexDelegate<K extends Object> {
  int get revision;
  int? get itemCount;
  LoadedRangeSet get loadedRanges;
  Listenable get changes;
  K keyAt(int index);
  SeekoKeyLookup<K> lookupKey(K key);
  SeekoKeyLookup<K> captureIndex(int index);
}

final class ListSeekoIndexDelegate<K extends Object>
    implements SeekoIndexDelegate<K> {
  ListSeekoIndexDelegate({
    required this.itemCount,
    required ValueListenable<int> revision,
    required K Function(int index) keyAt,
    required int? Function(K key) indexOfKey,
  })  : _revision = revision,
        _keyAt = keyAt,
        _indexOfKey = indexOfKey,
        loadedRanges = LoadedRangeSet(<IndexRange>[IndexRange(0, itemCount)]);

  final ValueListenable<int> _revision;
  final K Function(int index) _keyAt;
  final int? Function(K key) _indexOfKey;

  @override
  final int itemCount;

  @override
  final LoadedRangeSet loadedRanges;

  @override
  Listenable get changes => _revision;

  @override
  int get revision => _revision.value;

  @override
  K keyAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', itemCount);
    return _keyAt(index);
  }

  @override
  SeekoKeyLookup<K> lookupKey(K key) {
    final int? index = _indexOfKey(key);
    if (index == null || index < 0 || index >= itemCount) {
      return SeekoKeyLookup<K>.absent();
    }
    return SeekoKeyLookup<K>.found(index);
  }

  @override
  SeekoKeyLookup<K> captureIndex(int index) {
    if (index < 0 || index >= itemCount) {
      return SeekoKeyLookup<K>.absent();
    }
    return SeekoKeyLookup<K>.found(index, key: _keyAt(index));
  }

  void validateKeys(IndexRange range) {
    if (range.end > itemCount) {
      throw RangeError.range(range.end, 0, itemCount, 'range.end');
    }
    final Map<K, int> seen = <K, int>{};
    for (var index = range.start; index < range.end; index += 1) {
      final K key = _keyAt(index);
      final int? firstIndex = seen[key];
      if (firstIndex != null) {
        throw DuplicateSeekoKeyError(key, firstIndex, index);
      }
      seen[key] = index;
    }
  }
}

final class DuplicateSeekoKeyError extends StateError {
  DuplicateSeekoKeyError(Object key, int firstIndex, int duplicateIndex)
      : super(
          'Duplicate Seeko key $key at indexes $firstIndex and $duplicateIndex.',
        );
}

void _validateRange(int index, int count) {
  RangeError.checkNotNegative(index, 'index');
  RangeError.checkValueInInterval(count, 1, 0x7fffffff, 'count');
}

int _max(int a, int b) => a > b ? a : b;
