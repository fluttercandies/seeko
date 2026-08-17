import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'seeko_two_dimensional.dart';

@immutable
final class SeekoTableColumn<K extends Object> {
  const SeekoTableColumn({
    required this.key,
    required this.width,
    this.minWidth = 32,
    this.maxWidth = double.infinity,
    this.resizable = true,
    this.semanticLabel,
  });

  final K key;
  final double width;
  final double minWidth;
  final double maxWidth;
  final bool resizable;
  final String? semanticLabel;

  SeekoTableColumn<K> withWidth(double value) {
    if (!value.isFinite || value < minWidth || value > maxWidth) {
      throw ArgumentError.value(
        value,
        'value',
        'must be finite and within the column width bounds',
      );
    }
    return SeekoTableColumn<K>(
      key: key,
      width: value,
      minWidth: minWidth,
      maxWidth: maxWidth,
      resizable: resizable,
      semanticLabel: semanticLabel,
    );
  }
}

@immutable
final class SeekoTableCellKey<R extends Object, C extends Object> {
  const SeekoTableCellKey(this.row, this.column);

  final R row;
  final C column;

  @override
  bool operator ==(Object other) =>
      other is SeekoTableCellKey<R, C> &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

typedef SeekoTableRowKeyAt<R extends Object> = R Function(int row);
typedef SeekoTableRowIndexOf<R extends Object> = int? Function(R key);

/// O(rows + columns) layout metadata for a potentially huge table.
///
/// No cell matrix is retained. Fixed row height is O(1); variable row height
/// uses a compact prefix table and O(log n) offset lookup.
final class SeekoTableLayout<R extends Object, C extends Object>
    extends SeekoTwoDimensionalLayout with ChangeNotifier {
  SeekoTableLayout({
    required this.rowCount,
    required Iterable<SeekoTableColumn<C>> columns,
    required this.rowKeyAt,
    required this.rowIndexOf,
    double rowExtent = 40,
    List<double>? rowExtents,
    this.frozenPanes = const SeekoFrozenPaneConfiguration(),
  })  : _columns = List<SeekoTableColumn<C>>.of(columns),
        _rows = rowExtents == null
            ? SeekoExtentTable.fixed(count: rowCount, extent: rowExtent)
            : SeekoExtentTable.variable(rowExtents),
        _columnWidths = SeekoExtentTable.variable(const <double>[]) {
    if (rowCount < 0) {
      throw RangeError.value(rowCount, 'rowCount');
    }
    if (rowExtents != null && rowExtents.length != rowCount) {
      throw ArgumentError(
        'rowExtents length must match rowCount.',
      );
    }
    _validateColumns(_columns);
    _columnWidths = SeekoExtentTable.variable(
      _columns.map((SeekoTableColumn<C> column) => column.width).toList(),
    );
    _rebuildColumnIndex();
  }

  @override
  final int rowCount;
  final SeekoTableRowKeyAt<R> rowKeyAt;
  final SeekoTableRowIndexOf<R> rowIndexOf;
  final SeekoFrozenPaneConfiguration frozenPanes;
  final SeekoExtentTable _rows;
  List<SeekoTableColumn<C>> _columns;
  late SeekoExtentTable _columnWidths;
  final Map<C, int> _columnIndex = <C, int>{};

  @override
  int get columnCount => _columns.length;
  List<SeekoTableColumn<C>> get columns =>
      List<SeekoTableColumn<C>>.unmodifiable(_columns);

  @override
  double rowExtent(int row) => _rows.extentAt(row);
  @override
  double columnExtent(int column) => _columnWidths.extentAt(column);
  @override
  double rowOffset(int row) => _rows.offsetOf(row);
  @override
  double columnOffset(int column) => _columnWidths.offsetOf(column);
  @override
  int rowAtOffset(double offset) => _rows.indexAt(offset);
  @override
  int columnAtOffset(double offset) => _columnWidths.indexAt(offset);
  @override
  double get totalHeight => _rows.totalExtent;
  @override
  double get totalWidth => _columnWidths.totalExtent;

  @override
  Object keyAt(int row, int column) =>
      SeekoTableCellKey<R, C>(rowKeyAt(row), _columns[column].key);

  @override
  SeekoCellCoordinate? coordinateOfKey(Object key) {
    if (key is! SeekoTableCellKey<R, C>) {
      return null;
    }
    final int? row = rowIndexOf(key.row);
    final int? column = _columnIndex[key.column];
    if (row == null || row < 0 || row >= rowCount || column == null) {
      return null;
    }
    return SeekoCellCoordinate(row, column);
  }

  double resizeColumn(C key, double width) {
    final int? index = _columnIndex[key];
    if (index == null) {
      throw StateError('Cannot resize an unknown table column.');
    }
    final SeekoTableColumn<C> column = _columns[index];
    if (!column.resizable) {
      throw StateError('The requested table column is not resizable.');
    }
    final double oldWidth = column.width;
    final List<SeekoTableColumn<C>> next =
        List<SeekoTableColumn<C>>.of(_columns);
    next[index] = column.withWidth(width);
    _columns = next;
    _columnWidths = SeekoExtentTable.variable(
      next.map((SeekoTableColumn<C> value) => value.width).toList(),
    );
    notifyListeners();
    return width - oldWidth;
  }

  void reorderColumns(List<C> order) {
    if (order.length != _columns.length ||
        order.toSet().length != order.length) {
      throw ArgumentError('Column order must contain every column once.');
    }
    final Map<C, SeekoTableColumn<C>> byKey = <C, SeekoTableColumn<C>>{
      for (final SeekoTableColumn<C> column in _columns) column.key: column,
    };
    final List<SeekoTableColumn<C>> next = <SeekoTableColumn<C>>[];
    for (final C key in order) {
      final SeekoTableColumn<C>? column = byKey[key];
      if (column == null) {
        throw ArgumentError('Column order contains an unknown key.');
      }
      next.add(column);
    }
    _columns = next;
    _columnWidths = SeekoExtentTable.variable(
      next.map((SeekoTableColumn<C> value) => value.width).toList(),
    );
    _rebuildColumnIndex();
    notifyListeners();
  }

  void _rebuildColumnIndex() {
    _columnIndex
      ..clear()
      ..addEntries(
        <MapEntry<C, int>>[
          for (var index = 0; index < _columns.length; index += 1)
            MapEntry<C, int>(_columns[index].key, index),
        ],
      );
  }

  static void _validateColumns<K extends Object>(
    List<SeekoTableColumn<K>> columns,
  ) {
    final Set<K> keys = <K>{};
    for (final SeekoTableColumn<K> column in columns) {
      if (!column.width.isFinite ||
          column.width <= 0 ||
          !column.minWidth.isFinite ||
          column.minWidth <= 0 ||
          column.maxWidth < column.minWidth ||
          column.width < column.minWidth ||
          column.width > column.maxWidth) {
        throw ArgumentError('Table column widths are inconsistent.');
      }
      if (!keys.add(column.key)) {
        throw ArgumentError('Table column keys must be unique.');
      }
    }
  }
}

/// Keeps a table layout and two-dimensional controller attached.
final class SeekoTableBinding<R extends Object, C extends Object> {
  SeekoTableBinding({
    required this.controller,
    required this.layout,
    this.frozenPaneBinding,
  }) {
    controller.setLayout(layout);
    layout.addListener(_handleLayoutChanged);
  }

  final SeekoTwoDimensionalController controller;
  final SeekoTableLayout<R, C> layout;
  final SeekoFrozenPaneBinding? frozenPaneBinding;
  bool _disposed = false;

  void _handleLayoutChanged() {
    controller.setLayout(null);
    controller.setLayout(layout);
    frozenPaneBinding?.syncNow();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    layout.removeListener(_handleLayoutChanged);
    if (identical(controller.layout, layout)) {
      controller.setLayout(null);
    }
    frozenPaneBinding?.dispose();
  }
}

enum SeekoTableNavigationIntent {
  up,
  down,
  left,
  right,
  rowStart,
  rowEnd,
  tableStart,
  tableEnd,
  pageUp,
  pageDown,
}

/// Keyboard focus model independent of any particular cell widget.
final class SeekoTableNavigationController extends ChangeNotifier {
  SeekoTableNavigationController({
    required this.rowCount,
    required this.columnCount,
    SeekoCellCoordinate initial = SeekoCellCoordinate.zero,
  }) : _current = initial {
    if (rowCount <= 0 || columnCount <= 0) {
      throw RangeError('rowCount and columnCount must be positive.');
    }
    _current = _clamp(initial);
  }

  final int rowCount;
  final int columnCount;
  SeekoCellCoordinate _current;

  SeekoCellCoordinate get current => _current;
  SeekoCellTarget get target =>
      SeekoCellTarget.cell(_current.row, _current.column);

  /// Selects [coordinate], clamped to the current table bounds.
  ///
  /// This is useful for pointer and accessibility focus changes that need to
  /// share the same virtual focus model as keyboard navigation.
  SeekoCellCoordinate select(SeekoCellCoordinate coordinate) {
    final SeekoCellCoordinate clamped = _clamp(coordinate);
    if (clamped != _current) {
      _current = clamped;
      notifyListeners();
    }
    return _current;
  }

  SeekoCellCoordinate move(
    SeekoTableNavigationIntent intent, {
    int visibleRows = 1,
  }) {
    final int page = visibleRows < 1 ? 1 : visibleRows;
    final (int, int) next = switch (intent) {
      SeekoTableNavigationIntent.up => (_current.row - 1, _current.column),
      SeekoTableNavigationIntent.down => (_current.row + 1, _current.column),
      SeekoTableNavigationIntent.left => (_current.row, _current.column - 1),
      SeekoTableNavigationIntent.right => (_current.row, _current.column + 1),
      SeekoTableNavigationIntent.rowStart => (_current.row, 0),
      SeekoTableNavigationIntent.rowEnd => (_current.row, columnCount - 1),
      SeekoTableNavigationIntent.tableStart => (0, 0),
      SeekoTableNavigationIntent.tableEnd => (rowCount - 1, columnCount - 1),
      SeekoTableNavigationIntent.pageUp => (
          _current.row - page,
          _current.column
        ),
      SeekoTableNavigationIntent.pageDown => (
          _current.row + page,
          _current.column
        ),
    };
    final SeekoCellCoordinate clamped = _clampValues(next.$1, next.$2);
    if (clamped != _current) {
      _current = clamped;
      notifyListeners();
    }
    return _current;
  }

  bool handleKeyEvent(KeyEvent event, {int visibleRows = 1}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool primaryModifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final SeekoTableNavigationIntent? intent = switch (key) {
      LogicalKeyboardKey.arrowUp => SeekoTableNavigationIntent.up,
      LogicalKeyboardKey.arrowDown => SeekoTableNavigationIntent.down,
      LogicalKeyboardKey.arrowLeft => SeekoTableNavigationIntent.left,
      LogicalKeyboardKey.arrowRight => SeekoTableNavigationIntent.right,
      LogicalKeyboardKey.home => primaryModifier
          ? SeekoTableNavigationIntent.tableStart
          : SeekoTableNavigationIntent.rowStart,
      LogicalKeyboardKey.end => primaryModifier
          ? SeekoTableNavigationIntent.tableEnd
          : SeekoTableNavigationIntent.rowEnd,
      LogicalKeyboardKey.pageUp => SeekoTableNavigationIntent.pageUp,
      LogicalKeyboardKey.pageDown => SeekoTableNavigationIntent.pageDown,
      _ => null,
    };
    if (intent == null) {
      return false;
    }
    move(intent, visibleRows: visibleRows);
    return true;
  }

  SeekoCellCoordinate _clamp(SeekoCellCoordinate value) {
    return _clampValues(value.row, value.column);
  }

  SeekoCellCoordinate _clampValues(int row, int column) {
    return SeekoCellCoordinate(
      row.clamp(0, rowCount - 1),
      column.clamp(0, columnCount - 1),
    );
  }
}

@immutable
final class SeekoTreeNodeDescriptor<K extends Object> {
  const SeekoTreeNodeDescriptor({
    required this.key,
    required this.children,
    this.extent = 40,
    this.semanticLabel,
  });

  final K key;
  final Iterable<K> children;
  final double extent;
  final String? semanticLabel;
}

typedef SeekoTreeNodeResolver<K extends Object> = SeekoTreeNodeDescriptor<K>
    Function(K key);

@immutable
final class SeekoTreeVisibleRow<K extends Object> {
  const SeekoTreeVisibleRow({
    required this.key,
    required this.depth,
    required this.extent,
    required this.expanded,
    required this.hasChildren,
    this.parent,
    this.semanticLabel,
  });

  final K key;
  final K? parent;
  final int depth;
  final double extent;
  final bool expanded;
  final bool hasChildren;
  final String? semanticLabel;
}

@immutable
final class SeekoTreeAnchor<K extends Object> {
  const SeekoTreeAnchor({
    required this.key,
    required this.viewportOffset,
  });

  final K key;
  final double viewportOffset;
}

@immutable
final class SeekoTreeMutationResult<K extends Object> {
  const SeekoTreeMutationResult({
    required this.pixelCorrection,
    required this.anchor,
    required this.visibleRowCount,
  });

  final double pixelCorrection;
  final SeekoTreeAnchor<K>? anchor;
  final int visibleRowCount;
}

/// Flattens only expanded tree branches and preserves a stable row anchor.
///
/// Work is proportional to visible nodes, so collapsed descendants do not
/// increase scrolling memory or per-frame cost.
final class SeekoTreeTableController<K extends Object> extends ChangeNotifier {
  SeekoTreeTableController({
    required Iterable<K> roots,
    required this.resolveNode,
    Iterable<K> initiallyExpanded = const <Never>[],
  })  : _roots = List<K>.unmodifiable(roots),
        _expanded = Set<K>.of(initiallyExpanded) {
    _rebuildVisible();
  }

  final SeekoTreeNodeResolver<K> resolveNode;
  List<K> _roots;
  final Set<K> _expanded;
  List<SeekoTreeVisibleRow<K>> _visible = <SeekoTreeVisibleRow<K>>[];
  Map<K, int> _visibleIndex = <K, int>{};
  Map<K, K?> _parent = <K, K?>{};
  SeekoExtentTable _extents = SeekoExtentTable.variable(const <double>[]);

  List<SeekoTreeVisibleRow<K>> get visibleRows => _visible;
  int get visibleRowCount => _visible.length;
  Set<K> get expandedKeys => Set<K>.unmodifiable(_expanded);

  bool isExpanded(K key) => _expanded.contains(key);
  int? indexOf(K key) => _visibleIndex[key];
  double? offsetOf(K key) {
    final int? index = _visibleIndex[key];
    return index == null ? null : _extents.offsetOf(index);
  }

  SeekoTreeAnchor<K>? captureAnchor(
    K key, {
    double viewportOffset = 0,
  }) {
    if (!_visibleIndex.containsKey(key)) {
      return null;
    }
    if (!viewportOffset.isFinite) {
      throw ArgumentError.value(viewportOffset, 'viewportOffset');
    }
    return SeekoTreeAnchor<K>(
      key: key,
      viewportOffset: viewportOffset,
    );
  }

  SeekoTreeMutationResult<K> setExpanded(
    K key,
    bool expanded, {
    SeekoTreeAnchor<K>? preserve,
  }) {
    final SeekoTreeNodeDescriptor<K> node = resolveNode(key);
    final List<K> children = List<K>.of(node.children);
    if (expanded && children.isEmpty) {
      return SeekoTreeMutationResult<K>(
        pixelCorrection: 0,
        anchor: preserve,
        visibleRowCount: _visible.length,
      );
    }
    final bool changed = expanded ? _expanded.add(key) : _expanded.remove(key);
    if (!changed) {
      return SeekoTreeMutationResult<K>(
        pixelCorrection: 0,
        anchor: preserve,
        visibleRowCount: _visible.length,
      );
    }
    return _commitMutation(preserve);
  }

  SeekoTreeMutationResult<K> toggle(
    K key, {
    SeekoTreeAnchor<K>? preserve,
  }) {
    return setExpanded(
      key,
      !_expanded.contains(key),
      preserve: preserve,
    );
  }

  SeekoTreeMutationResult<K> replaceRoots(
    Iterable<K> roots, {
    SeekoTreeAnchor<K>? preserve,
  }) {
    _roots = List<K>.unmodifiable(roots);
    return _commitMutation(preserve);
  }

  SeekoTreeMutationResult<K> _commitMutation(
    SeekoTreeAnchor<K>? preserve,
  ) {
    final double? before = preserve == null ? null : offsetOf(preserve.key);
    final Map<K, K?> oldParents = _parent;
    _rebuildVisible();
    K? anchorKey = preserve?.key;
    while (anchorKey != null && !_visibleIndex.containsKey(anchorKey)) {
      anchorKey = oldParents[anchorKey];
    }
    final double? after = anchorKey == null ? null : offsetOf(anchorKey);
    final SeekoTreeAnchor<K>? nextAnchor = preserve == null || anchorKey == null
        ? null
        : SeekoTreeAnchor<K>(
            key: anchorKey,
            viewportOffset: preserve.viewportOffset,
          );
    final double correction =
        before == null || after == null ? 0 : after - before;
    notifyListeners();
    return SeekoTreeMutationResult<K>(
      pixelCorrection: correction,
      anchor: nextAnchor,
      visibleRowCount: _visible.length,
    );
  }

  void _rebuildVisible() {
    final List<SeekoTreeVisibleRow<K>> rows = <SeekoTreeVisibleRow<K>>[];
    final Map<K, int> indices = <K, int>{};
    final Map<K, K?> parents = <K, K?>{};
    final Set<K> visiting = <K>{};
    final List<_TreeStackEntry<K>> stack = <_TreeStackEntry<K>>[
      for (var index = _roots.length - 1; index >= 0; index -= 1)
        _TreeStackEntry<K>(_roots[index], null, 0, false),
    ];
    while (stack.isNotEmpty) {
      final _TreeStackEntry<K> entry = stack.removeLast();
      if (entry.leaving) {
        visiting.remove(entry.key);
        continue;
      }
      if (!visiting.add(entry.key)) {
        throw StateError('Tree data contains a visible cycle.');
      }
      if (indices.containsKey(entry.key)) {
        throw StateError('Tree stable keys must be unique.');
      }
      final SeekoTreeNodeDescriptor<K> node = resolveNode(entry.key);
      if (!node.extent.isFinite || node.extent <= 0) {
        throw StateError('Tree row extent must be finite and positive.');
      }
      final List<K> children = List<K>.of(node.children);
      final bool expanded = _expanded.contains(entry.key);
      indices[entry.key] = rows.length;
      parents[entry.key] = entry.parent;
      rows.add(
        SeekoTreeVisibleRow<K>(
          key: entry.key,
          parent: entry.parent,
          depth: entry.depth,
          extent: node.extent,
          expanded: expanded,
          hasChildren: children.isNotEmpty,
          semanticLabel: node.semanticLabel,
        ),
      );
      stack.add(
        _TreeStackEntry<K>(
          entry.key,
          entry.parent,
          entry.depth,
          true,
        ),
      );
      if (expanded) {
        for (var index = children.length - 1; index >= 0; index -= 1) {
          stack.add(
            _TreeStackEntry<K>(
              children[index],
              entry.key,
              entry.depth + 1,
              false,
            ),
          );
        }
      }
    }
    _visible = List<SeekoTreeVisibleRow<K>>.unmodifiable(rows);
    _visibleIndex = indices;
    _parent = parents;
    _extents = SeekoExtentTable.variable(
      rows.map((SeekoTreeVisibleRow<K> row) => row.extent).toList(),
    );
  }
}

final class _TreeStackEntry<K extends Object> {
  const _TreeStackEntry(
    this.key,
    this.parent,
    this.depth,
    this.leaving,
  );

  final K key;
  final K? parent;
  final int depth;
  final bool leaving;
}

/// Rebuilds row metadata only when tree expansion changes.
final class SeekoTreeTableBinding<K extends Object, C extends Object> {
  SeekoTreeTableBinding({
    required this.controller,
    required this.tree,
    required Iterable<SeekoTableColumn<C>> columns,
    this.frozenPanes = const SeekoFrozenPaneConfiguration(),
  }) : _columns = List<SeekoTableColumn<C>>.unmodifiable(columns) {
    tree.addListener(_rebuildLayout);
    _rebuildLayout();
  }

  final SeekoTwoDimensionalController controller;
  final SeekoTreeTableController<K> tree;
  final SeekoFrozenPaneConfiguration frozenPanes;
  final List<SeekoTableColumn<C>> _columns;
  SeekoTableLayout<K, C>? _layout;
  bool _disposed = false;

  SeekoTableLayout<K, C> get layout => _layout!;

  void _rebuildLayout() {
    final List<SeekoTreeVisibleRow<K>> rows = tree.visibleRows;
    final SeekoTableLayout<K, C> next = SeekoTableLayout<K, C>(
      rowCount: rows.length,
      columns: _columns,
      rowKeyAt: (int index) => rows[index].key,
      rowIndexOf: tree.indexOf,
      rowExtents: rows.map((SeekoTreeVisibleRow<K> row) => row.extent).toList(),
      frozenPanes: frozenPanes,
    );
    final SeekoTableLayout<K, C>? previous = _layout;
    _layout = next;
    controller.setLayout(next);
    previous?.dispose();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    tree.removeListener(_rebuildLayout);
    if (_layout != null && identical(controller.layout, _layout)) {
      controller.setLayout(null);
    }
    _layout?.dispose();
  }
}
