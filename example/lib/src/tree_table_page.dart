import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class TreeTablePage extends StatefulWidget {
  const TreeTablePage({super.key});

  @override
  State<TreeTablePage> createState() => _TreeTablePageState();
}

class _TreeTablePageState extends State<TreeTablePage> {
  static const List<String> _columnKeys = <String>[
    'name',
    'status',
    'owner',
    'updated',
  ];
  static const List<String> _groups = <String>[
    'Applications',
    'Packages',
    'Infrastructure',
    'Design system',
    'Quality',
    'Release trains',
  ];

  late final SeekoTwoDimensionalController _controller;
  late final SeekoTreeTableController<String> _tree;
  late final SeekoTreeTableBinding<String, String> _binding;
  late SeekoTableNavigationController _navigation;
  late final ScrollController _headerHorizontal;
  late final SeekoFrozenPaneBinding _frozenBinding;
  SeekoTwoDimensionalResult? _lastResult;
  bool _wideStatus = false;

  @override
  void initState() {
    super.initState();
    _controller = SeekoTwoDimensionalController();
    _tree = SeekoTreeTableController<String>(
      roots: const <String>['workspace'],
      resolveNode: _resolveNode,
      initiallyExpanded: <String>[
        'workspace',
        for (var index = 0; index < _groups.length; index++) 'group-$index',
      ],
    );
    _binding = SeekoTreeTableBinding<String, String>(
      controller: _controller,
      tree: _tree,
      columns: _columns,
      frozenPanes: const SeekoFrozenPaneConfiguration(rows: 1),
    );
    _navigation = _createNavigation();
    _navigation.addListener(_handleNavigationChanged);
    _tree.addListener(_handleTreeChanged);
    _headerHorizontal = ScrollController();
    _frozenBinding = SeekoFrozenPaneBinding(
      bodyVertical: _controller.verticalController,
      bodyHorizontal: _controller.horizontalController,
      frozenRowsHorizontal: _headerHorizontal,
      configuration: const SeekoFrozenPaneConfiguration(rows: 1),
    );
  }

  List<SeekoTableColumn<String>> get _columns => <SeekoTableColumn<String>>[
    const SeekoTableColumn<String>(
      key: 'name',
      width: 260,
      minWidth: 180,
      semanticLabel: 'Name',
    ),
    SeekoTableColumn<String>(
      key: 'status',
      width: _wideStatus ? 190 : 132,
      minWidth: 104,
      semanticLabel: 'Status',
    ),
    const SeekoTableColumn<String>(
      key: 'owner',
      width: 160,
      minWidth: 120,
      semanticLabel: 'Owner',
    ),
    const SeekoTableColumn<String>(
      key: 'updated',
      width: 180,
      minWidth: 140,
      semanticLabel: 'Updated',
    ),
  ];

  SeekoTreeNodeDescriptor<String> _resolveNode(String key) {
    if (key == 'workspace') {
      return SeekoTreeNodeDescriptor<String>(
        key: key,
        children: <String>[
          for (var index = 0; index < _groups.length; index++) 'group-$index',
        ],
        extent: 46,
        semanticLabel: 'Workspace root',
      );
    }
    if (key.startsWith('group-')) {
      final int group = int.parse(key.substring('group-'.length));
      return SeekoTreeNodeDescriptor<String>(
        key: key,
        children: <String>[
          for (var index = 0; index < 6; index++) 'node-$group-$index',
        ],
        extent: 44,
        semanticLabel: _groups[group],
      );
    }
    return SeekoTreeNodeDescriptor<String>(
      key: key,
      children: const <String>[],
      extent: 42,
      semanticLabel: _labelFor(key),
    );
  }

  String _labelFor(String key) {
    if (key == 'workspace') return 'Seeko workspace';
    if (key.startsWith('group-')) {
      return _groups[int.parse(key.substring('group-'.length))];
    }
    final List<String> parts = key.split('-');
    final int group = int.parse(parts[1]);
    final int item = int.parse(parts[2]);
    return '${_groups[group]} module ${item + 1}';
  }

  SeekoTableNavigationController _createNavigation({
    SeekoCellCoordinate initial = SeekoCellCoordinate.zero,
  }) {
    return SeekoTableNavigationController(
      rowCount: _tree.visibleRowCount,
      columnCount: _columnKeys.length,
      initial: initial,
    );
  }

  void _handleNavigationChanged() {
    if (mounted) setState(() {});
  }

  void _handleTreeChanged() {
    final SeekoCellCoordinate current = _navigation.current;
    _navigation
      ..removeListener(_handleNavigationChanged)
      ..dispose();
    _navigation = _createNavigation(initial: current)
      ..addListener(_handleNavigationChanged);
    if (mounted) setState(() {});
  }

  Future<void> _toggle(String key) async {
    final int currentRow = _navigation.current.row;
    final List<SeekoTreeVisibleRow<String>> before = _tree.visibleRows;
    final String anchorKey = before[currentRow.clamp(0, before.length - 1)].key;
    final SeekoTreeMutationResult<String> mutation = _tree.toggle(
      key,
      preserve: _tree.captureAnchor(anchorKey),
    );
    await SchedulerBinding.instance.endOfFrame;
    if (mutation.pixelCorrection != 0 &&
        _controller.verticalController.hasClients) {
      await _controller.jumpTo(
        verticalPixels:
            _controller.verticalController.offset + mutation.pixelCorrection,
      );
    }
  }

  Future<void> _seekDeepCell() async {
    final SeekoTwoDimensionalResult result = await _controller.animateToCell(
      SeekoCellTarget.key(
        const SeekoTableCellKey<String, String>('node-5-5', 'owner'),
      ),
      placement: const SeekoTwoDimensionalPlacement.center(),
    );
    if (mounted) setState(() => _lastResult = result);
  }

  Future<void> _reset() async {
    final SeekoTwoDimensionalResult result = await _controller.jumpTo(
      horizontalPixels: 0,
      verticalPixels: 0,
    );
    if (mounted) setState(() => _lastResult = result);
  }

  void _resizeStatusColumn() {
    setState(() => _wideStatus = !_wideStatus);
    _binding.layout.resizeColumn('status', _wideStatus ? 190 : 132);
    _controller
      ..setLayout(null)
      ..setLayout(_binding.layout);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_navigation.handleKeyEvent(
      event,
      visibleRows: (_controller.viewportSize.height / 44).floor(),
    )) {
      return KeyEventResult.ignored;
    }
    unawaited(
      _controller.animateToCell(
        _navigation.target,
        placement: const SeekoTwoDimensionalPlacement.nearest(),
      ),
    );
    return KeyEventResult.handled;
  }

  void _selectCell(int row, int column) {
    _navigation.select(SeekoCellCoordinate(row, column));
    unawaited(
      _controller.animateToCell(
        _navigation.target,
        placement: const SeekoTwoDimensionalPlacement.nearest(),
      ),
    );
  }

  @override
  void dispose() {
    _tree.removeListener(_handleTreeChanged);
    _navigation
      ..removeListener(_handleNavigationChanged)
      ..dispose();
    _frozenBinding.dispose();
    _headerHorizontal.dispose();
    _binding.dispose();
    _tree.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('tree-table-page'),
      child: Column(
        children: <Widget>[
          ScenarioPageHeader(
            title: 'Tree Table Navigation',
            description:
                'Expanded branches stay flat and virtualizable while stable '
                'cell keys drive two-axis navigation.',
            actions: <Widget>[
              IconButton.filledTonal(
                key: const Key('tree-table-seek'),
                tooltip: 'Animate to a deep table cell',
                onPressed: () => unawaited(_seekDeepCell()),
                icon: const Icon(Icons.center_focus_strong),
              ),
              IconButton.filledTonal(
                key: const Key('tree-table-resize-column'),
                tooltip: 'Resize status column',
                onPressed: _resizeStatusColumn,
                icon: const Icon(Icons.width_normal),
              ),
              IconButton.filledTonal(
                key: const Key('tree-table-reset'),
                tooltip: 'Reset table viewport',
                onPressed: () => unawaited(_reset()),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
            status: ScenarioStatusBadge(
              label: _lastResult?.outcome.name ?? 'Ready',
              widgetKey: const Key('tree-table-result'),
              tone: scenarioToneForOutcome(_lastResult?.outcome.name),
              icon: Icons.account_tree_outlined,
            ),
          ),
          const Divider(height: 1),
          ScenarioPaneHeader(
            title:
                'Cell R${_navigation.current.row} C${_navigation.current.column}',
            description:
                '${_tree.visibleRowCount} visible rows · arrow, Home, End, '
                'Page Up and Page Down navigation',
            trailing: const ScenarioStatusBadge(
              label: 'Header frozen',
              icon: Icons.vertical_align_top,
              tone: ScenarioStatusTone.active,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Focus(
              autofocus: true,
              onKeyEvent: _handleKey,
              child: _buildTable(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final SeekoTableLayout<String, String> layout = _binding.layout;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 44,
          child: SingleChildScrollView(
            key: const Key('tree-table-header-scroll'),
            controller: _headerHorizontal,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: _TableHeader(columns: layout.columns),
          ),
        ),
        Expanded(
          child: Semantics(
            container: true,
            label:
                'Tree table with ${_tree.visibleRowCount} rows and ${layout.columnCount} columns',
            child: SeekoTwoDimensionalViewportObserver(
              controller: _controller,
              child: Scrollbar(
                controller: _controller.horizontalController,
                thumbVisibility: true,
                notificationPredicate: (ScrollNotification notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  key: const Key('tree-table-horizontal'),
                  controller: _controller.horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: layout.totalWidth,
                    child: Scrollbar(
                      controller: _controller.verticalController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const Key('tree-table-vertical'),
                        controller: _controller.verticalController,
                        child: _TableBody(
                          rows: _tree.visibleRows,
                          columns: layout.columns,
                          selected: _navigation.current,
                          labelFor: _labelFor,
                          onSelectCell: _selectCell,
                          onToggle: (String key) => unawaited(_toggle(key)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.columns});

  final List<SeekoTableColumn<String>> columns;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        for (final SeekoTableColumn<String> column in columns)
          Semantics(
            container: true,
            header: true,
            excludeSemantics: true,
            label: '${column.semanticLabel ?? column.key} column',
            child: Container(
              width: column.width,
              height: 44,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                border: Border(
                  right: BorderSide(color: colors.outlineVariant),
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Text(
                column.semanticLabel ?? column.key,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
      ],
    );
  }
}

class _TableBody extends StatelessWidget {
  const _TableBody({
    required this.rows,
    required this.columns,
    required this.selected,
    required this.labelFor,
    required this.onSelectCell,
    required this.onToggle,
  });

  final List<SeekoTreeVisibleRow<String>> rows;
  final List<SeekoTableColumn<String>> columns;
  final SeekoCellCoordinate selected;
  final String Function(String key) labelFor;
  final void Function(int row, int column) onSelectCell;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
          SizedBox(
            height: rows[rowIndex].extent,
            child: Row(
              children: <Widget>[
                for (
                  var columnIndex = 0;
                  columnIndex < columns.length;
                  columnIndex++
                )
                  _buildCell(context, colors, rowIndex, columnIndex),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(
    BuildContext context,
    ColorScheme colors,
    int rowIndex,
    int columnIndex,
  ) {
    final SeekoTreeVisibleRow<String> row = rows[rowIndex];
    final SeekoTableColumn<String> column = columns[columnIndex];
    final bool isSelected =
        selected.row == rowIndex && selected.column == columnIndex;
    final bool isExpandableNameCell = columnIndex == 0 && row.hasChildren;
    final String rowLabel = labelFor(row.key);
    final String columnLabel = column.semanticLabel ?? column.key;
    final String value = _cellValue(row, column.key, rowIndex);

    void selectCell() => onSelectCell(rowIndex, columnIndex);

    void activateCell() {
      selectCell();
      if (isExpandableNameCell) {
        onToggle(row.key);
      }
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$rowLabel, $columnLabel',
      value: value,
      selected: isSelected,
      focusable: true,
      focused: isSelected,
      button: isExpandableNameCell,
      expanded: isExpandableNameCell ? row.expanded : null,
      hint: isExpandableNameCell
          ? row.expanded
                ? 'Activate to collapse this row'
                : 'Activate to expand this row'
          : 'Use arrow keys to move between cells',
      onTap: activateCell,
      onExpand: isExpandableNameCell && !row.expanded ? activateCell : null,
      onCollapse: isExpandableNameCell && row.expanded ? activateCell : null,
      onDidGainAccessibilityFocus: selectCell,
      child: InkWell(
        key: ValueKey<SeekoTableCellKey<String, String>>(
          SeekoTableCellKey<String, String>(row.key, column.key),
        ),
        onTap: activateCell,
        child: Container(
          width: column.width,
          height: row.extent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primaryContainer
                : rowIndex.isEven
                ? colors.surface
                : colors.surfaceContainerLowest,
            border: Border(
              right: BorderSide(color: colors.outlineVariant),
              bottom: BorderSide(color: colors.outlineVariant),
            ),
          ),
          child: _cellContent(context, row, column.key, rowIndex),
        ),
      ),
    );
  }

  String _cellValue(
    SeekoTreeVisibleRow<String> row,
    String column,
    int rowIndex,
  ) {
    if (column == 'name') {
      if (!row.hasChildren) {
        return 'Leaf row';
      }
      return row.expanded ? 'Expanded row' : 'Collapsed row';
    }
    if (column == 'status') {
      return rowIndex % 4 == 0 ? 'Review' : 'Healthy';
    }
    if (column == 'owner') {
      return 'Team ${(rowIndex % 7) + 1}';
    }
    return '${(rowIndex % 28) + 1} Aug 2026';
  }

  Widget _cellContent(
    BuildContext context,
    SeekoTreeVisibleRow<String> row,
    String column,
    int rowIndex,
  ) {
    if (column == 'name') {
      return Row(
        children: <Widget>[
          SizedBox(width: row.depth * 18),
          if (row.hasChildren)
            Icon(
              row.expanded ? Icons.expand_more : Icons.chevron_right,
              size: 20,
            )
          else
            const SizedBox(width: 20),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              labelFor(row.key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    if (column == 'status') {
      return Text(_cellValue(row, column, rowIndex));
    }
    return Text(_cellValue(row, column, rowIndex));
  }
}
