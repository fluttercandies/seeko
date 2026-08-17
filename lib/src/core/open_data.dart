import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

enum SeekoOpenDirection { before, after }

@immutable
final class SeekoOpenItem<K extends Object> {
  const SeekoOpenItem({
    required this.logicalIndex,
    required this.key,
    required this.extent,
  });

  final int logicalIndex;
  final K key;
  final double extent;
}

@immutable
final class SeekoOpenPage<K extends Object> {
  SeekoOpenPage({
    required Iterable<SeekoOpenItem<K>> items,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
    required this.revision,
  }) : items = List<SeekoOpenItem<K>>.unmodifiable(items) {
    if (revision < 0) {
      throw RangeError.value(revision, 'revision');
    }
    for (var index = 0; index < this.items.length; index += 1) {
      final SeekoOpenItem<K> item = this.items[index];
      if (!item.extent.isFinite || item.extent <= 0) {
        throw ArgumentError.value(
          item.extent,
          'items[$index].extent',
          'must be finite and positive',
        );
      }
      if (index > 0 &&
          item.logicalIndex != this.items[index - 1].logicalIndex + 1) {
        throw ArgumentError.value(
          items,
          'items',
          'must be sorted and contiguous by logicalIndex',
        );
      }
    }
  }

  final List<SeekoOpenItem<K>> items;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
  final int revision;
}

@immutable
final class SeekoOpenLoadRequest {
  const SeekoOpenLoadRequest({
    required this.direction,
    required this.boundaryIndex,
    required this.suggestedCount,
    required this.revision,
  });

  final SeekoOpenDirection direction;
  final int? boundaryIndex;
  final int suggestedCount;
  final int revision;
}

abstract interface class SeekoOpenDataSource<K extends Object> {
  Future<SeekoOpenPage<K>> load(SeekoOpenLoadRequest request);
}

typedef SeekoOpenLoadCallback<K extends Object> = FutureOr<SeekoOpenPage<K>>
    Function(SeekoOpenLoadRequest request);

final class CallbackSeekoOpenDataSource<K extends Object>
    implements SeekoOpenDataSource<K> {
  const CallbackSeekoOpenDataSource(this.callback);

  final SeekoOpenLoadCallback<K> callback;

  @override
  Future<SeekoOpenPage<K>> load(SeekoOpenLoadRequest request) =>
      Future<SeekoOpenPage<K>>.sync(() => callback(request));
}

@immutable
final class SeekoOpenAnchor<K extends Object> {
  const SeekoOpenAnchor({
    required this.key,
    required this.logicalIndex,
    required this.viewportOffset,
    required this.revision,
  });

  final K key;
  final int logicalIndex;
  final double viewportOffset;
  final int revision;
}

enum SeekoOpenResolutionStatus { resolved, notLoaded, absent }

@immutable
final class SeekoOpenResolution<K extends Object> {
  const SeekoOpenResolution._({
    required this.status,
    this.item,
    this.contentOffset,
  });

  const SeekoOpenResolution.resolved(
    SeekoOpenItem<K> item,
    double contentOffset,
  ) : this._(
          status: SeekoOpenResolutionStatus.resolved,
          item: item,
          contentOffset: contentOffset,
        );

  const SeekoOpenResolution.notLoaded()
      : this._(status: SeekoOpenResolutionStatus.notLoaded);

  const SeekoOpenResolution.absent()
      : this._(status: SeekoOpenResolutionStatus.absent);

  final SeekoOpenResolutionStatus status;
  final SeekoOpenItem<K>? item;
  final double? contentOffset;
}

@immutable
final class SeekoOpenMutationResult<K extends Object> {
  const SeekoOpenMutationResult({
    required this.revision,
    required this.pixelCorrection,
    required this.anchor,
    required this.insertedCount,
    required this.updatedCount,
  });

  final int revision;
  final double pixelCorrection;
  final SeekoOpenAnchor<K>? anchor;
  final int insertedCount;
  final int updatedCount;
}

/// Maintains a finite loaded window inside an unbounded logical index space.
///
/// Loaded items use signed logical indices, so prepend and append operations
/// never renumber existing identities. Normalized progress is intentionally
/// unavailable because neither edge is assumed to be finite.
final class SeekoOpenDataController<K extends Object> extends ChangeNotifier {
  SeekoOpenDataController({
    this.source,
    this.suggestedPageSize = 40,
  }) {
    if (suggestedPageSize <= 0) {
      throw RangeError.value(suggestedPageSize, 'suggestedPageSize');
    }
  }

  final SeekoOpenDataSource<K>? source;
  final int suggestedPageSize;
  final SplayTreeMap<int, SeekoOpenItem<K>> _items =
      SplayTreeMap<int, SeekoOpenItem<K>>();
  final Map<K, int> _indexByKey = <K, int>{};
  final Map<SeekoOpenDirection, Future<SeekoOpenMutationResult<K>>>
      _pendingLoads =
      <SeekoOpenDirection, Future<SeekoOpenMutationResult<K>>>{};
  int _revision = 0;
  bool _hasMoreBefore = true;
  bool _hasMoreAfter = true;
  int? _originIndex;
  List<int> _orderedIndices = const <int>[];
  List<double> _prefixExtents = const <double>[0];
  bool _offsetCacheDirty = true;

  int get revision => _revision;
  bool get hasMoreBefore => _hasMoreBefore;
  bool get hasMoreAfter => _hasMoreAfter;
  int get loadedCount => _items.length;
  int? get firstLoadedIndex => _items.isEmpty ? null : _items.firstKey();
  int? get lastLoadedIndex => _items.isEmpty ? null : _items.lastKey();
  int? get originIndex => _originIndex;
  Iterable<SeekoOpenItem<K>> get items => _items.values;
  double? get normalizedProgress => null;

  SeekoOpenItem<K>? itemAt(int logicalIndex) => _items[logicalIndex];

  SeekoOpenItem<K>? itemForKey(K key) {
    final int? index = _indexByKey[key];
    return index == null ? null : _items[index];
  }

  SeekoOpenResolution<K> resolveIndex(int logicalIndex) {
    final SeekoOpenItem<K>? item = _items[logicalIndex];
    if (item != null) {
      return SeekoOpenResolution<K>.resolved(
        item,
        offsetOf(logicalIndex)!,
      );
    }
    final int? first = firstLoadedIndex;
    final int? last = lastLoadedIndex;
    if (first == null || last == null) {
      return SeekoOpenResolution<K>.notLoaded();
    }
    if ((logicalIndex < first && _hasMoreBefore) ||
        (logicalIndex > last && _hasMoreAfter) ||
        (logicalIndex >= first && logicalIndex <= last)) {
      return SeekoOpenResolution<K>.notLoaded();
    }
    return SeekoOpenResolution<K>.absent();
  }

  SeekoOpenResolution<K> resolveKey(K key) {
    final SeekoOpenItem<K>? item = itemForKey(key);
    if (item == null) {
      return !_hasMoreBefore && !_hasMoreAfter
          ? SeekoOpenResolution<K>.absent()
          : SeekoOpenResolution<K>.notLoaded();
    }
    return SeekoOpenResolution<K>.resolved(
      item,
      offsetOf(item.logicalIndex)!,
    );
  }

  double? offsetOf(int logicalIndex) {
    if (!_items.containsKey(logicalIndex)) {
      return null;
    }
    _ensureOffsetCache();
    final int origin = _originIndex ?? _items.firstKey()!;
    final int itemPosition = _orderedPosition(logicalIndex);
    final int originPosition = _orderedPosition(origin);
    return _prefixExtents[itemPosition] - _prefixExtents[originPosition];
  }

  SeekoOpenAnchor<K>? captureAnchor(
    K key, {
    double viewportOffset = 0,
  }) {
    final SeekoOpenItem<K>? item = itemForKey(key);
    if (item == null) {
      return null;
    }
    if (!viewportOffset.isFinite) {
      throw ArgumentError.value(viewportOffset, 'viewportOffset');
    }
    return SeekoOpenAnchor<K>(
      key: key,
      logicalIndex: item.logicalIndex,
      viewportOffset: viewportOffset,
      revision: _revision,
    );
  }

  SeekoOpenMutationResult<K> applyPage(
    SeekoOpenPage<K> page, {
    SeekoOpenAnchor<K>? preserve,
  }) {
    if (page.revision < _revision) {
      throw StateError(
        'Open data revision is older than the current revision.',
      );
    }
    final double? beforeOffset =
        preserve == null ? null : _windowOffsetOf(preserve.logicalIndex);
    var inserted = 0;
    var updated = 0;
    for (final SeekoOpenItem<K> item in page.items) {
      final int? existingIndex = _indexByKey[item.key];
      if (existingIndex != null && existingIndex != item.logicalIndex) {
        throw StateError(
          'A stable key moved without an atomic rebase.',
        );
      }
      final SeekoOpenItem<K>? existing = _items[item.logicalIndex];
      if (existing != null && existing.key != item.key) {
        throw StateError(
          'A logical index is already owned by another stable key.',
        );
      }
      if (existing == null) {
        inserted += 1;
      } else {
        updated += 1;
      }
      _items[item.logicalIndex] = item;
      _indexByKey[item.key] = item.logicalIndex;
    }
    _offsetCacheDirty = true;
    _revision = page.revision;
    _hasMoreBefore = page.hasMoreBefore;
    _hasMoreAfter = page.hasMoreAfter;
    _originIndex ??= preserve?.logicalIndex ?? firstLoadedIndex;
    final SeekoOpenItem<K>? anchorItem =
        preserve == null ? null : itemForKey(preserve.key);
    final SeekoOpenAnchor<K>? nextAnchor = anchorItem == null
        ? null
        : SeekoOpenAnchor<K>(
            key: anchorItem.key,
            logicalIndex: anchorItem.logicalIndex,
            viewportOffset: preserve!.viewportOffset,
            revision: _revision,
          );
    final double? afterOffset =
        anchorItem == null ? null : _windowOffsetOf(anchorItem.logicalIndex);
    final double correction = beforeOffset == null || afterOffset == null
        ? 0
        : afterOffset - beforeOffset;
    notifyListeners();
    return SeekoOpenMutationResult<K>(
      revision: _revision,
      pixelCorrection: correction,
      anchor: nextAnchor,
      insertedCount: inserted,
      updatedCount: updated,
    );
  }

  Future<SeekoOpenMutationResult<K>> load(
    SeekoOpenDirection direction, {
    SeekoOpenAnchor<K>? preserve,
  }) {
    final Future<SeekoOpenMutationResult<K>>? pending =
        _pendingLoads[direction];
    if (pending != null) {
      return pending;
    }
    final SeekoOpenDataSource<K>? currentSource = source;
    if (currentSource == null) {
      throw StateError('SeekoOpenDataController has no data source.');
    }
    if ((direction == SeekoOpenDirection.before && !_hasMoreBefore) ||
        (direction == SeekoOpenDirection.after && !_hasMoreAfter)) {
      return Future<SeekoOpenMutationResult<K>>.value(
        SeekoOpenMutationResult<K>(
          revision: _revision,
          pixelCorrection: 0,
          anchor: preserve,
          insertedCount: 0,
          updatedCount: 0,
        ),
      );
    }
    final Future<SeekoOpenMutationResult<K>> operation = currentSource
        .load(
          SeekoOpenLoadRequest(
            direction: direction,
            boundaryIndex: direction == SeekoOpenDirection.before
                ? firstLoadedIndex
                : lastLoadedIndex,
            suggestedCount: suggestedPageSize,
            revision: _revision,
          ),
        )
        .then(
          (SeekoOpenPage<K> page) => applyPage(
            page,
            preserve: preserve,
          ),
        );
    _pendingLoads[direction] = operation;
    return operation.whenComplete(() {
      if (identical(_pendingLoads[direction], operation)) {
        _pendingLoads.removeWhere(
          (SeekoOpenDirection key, Future<SeekoOpenMutationResult<K>> value) =>
              key == direction,
        );
      }
    });
  }

  /// Changes the zero-offset item without changing item identity.
  ///
  /// Apply the returned pixel delta to the viewport to keep it stationary.
  double rebaseOrigin(K key) {
    final SeekoOpenItem<K>? item = itemForKey(key);
    if (item == null) {
      throw StateError('Cannot rebase to an unloaded key.');
    }
    final double shift = offsetOf(item.logicalIndex)!;
    _originIndex = item.logicalIndex;
    notifyListeners();
    return shift;
  }

  void _ensureOffsetCache() {
    if (!_offsetCacheDirty) {
      return;
    }
    final List<int> indices = List<int>.of(_items.keys);
    final List<double> prefix = List<double>.filled(indices.length + 1, 0);
    for (var position = 0; position < indices.length; position += 1) {
      prefix[position + 1] =
          prefix[position] + _items[indices[position]]!.extent;
    }
    _orderedIndices = indices;
    _prefixExtents = prefix;
    _offsetCacheDirty = false;
  }

  double? _windowOffsetOf(int logicalIndex) {
    if (!_items.containsKey(logicalIndex)) {
      return null;
    }
    _ensureOffsetCache();
    return _prefixExtents[_orderedPosition(logicalIndex)];
  }

  int _orderedPosition(int logicalIndex) {
    var low = 0;
    var high = _orderedIndices.length;
    while (low < high) {
      final int middle = (low + high) >> 1;
      if (_orderedIndices[middle] < logicalIndex) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low >= _orderedIndices.length || _orderedIndices[low] != logicalIndex) {
      throw StateError('The logical index is not part of the loaded window.');
    }
    return low;
  }
}
