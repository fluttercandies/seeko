import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class TwoDimensionalPage extends StatefulWidget {
  const TwoDimensionalPage({super.key});

  @override
  State<TwoDimensionalPage> createState() => _TwoDimensionalPageState();
}

class _TwoDimensionalPageState extends State<TwoDimensionalPage> {
  static const int _rowCount = 40;
  static const int _columnCount = 18;
  static const double _rowExtent = 52;
  static const double _columnExtent = 124;

  late final SeekoFiniteTwoDimensionalLayout _layout;
  late final SeekoTwoDimensionalController _controller;
  SeekoTwoDimensionalResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _layout = SeekoFiniteTwoDimensionalLayout.fixed(
      rowCount: _rowCount,
      columnCount: _columnCount,
      rowExtent: _rowExtent,
      columnExtent: _columnExtent,
      keyAt: (int row, int column) => _cellKey(row, column),
      coordinateOfKey: _coordinateOfKey,
    );
    _controller = SeekoTwoDimensionalController(layout: _layout);
  }

  static String _cellKey(int row, int column) => 'cell-$row-$column';

  static SeekoCellCoordinate? _coordinateOfKey(Object key) {
    if (key is! String) return null;
    final RegExpMatch? match = RegExp(r'^cell-(\d+)-(\d+)$').firstMatch(key);
    if (match == null) return null;
    return SeekoCellCoordinate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  Future<void> _seek(SeekoCellTarget target, {required bool animated}) async {
    final SeekoTwoDimensionalResult result = animated
        ? await _controller.animateToCell(
            target,
            placement: const SeekoTwoDimensionalPlacement.center(),
          )
        : await _controller.jumpToCell(
            target,
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('two-dimensional-page'),
      child: Column(
        children: <Widget>[
          ScenarioPageHeader(
            title: 'Two-dimensional Navigation',
            description:
                'Seek rows and columns independently while the surface stays '
                'a pair of native Flutter scrollables.',
            actions: <Widget>[
              IconButton.filledTonal(
                key: const Key('two-dimensional-jump'),
                tooltip: 'Jump to cell R18 C9',
                onPressed: () => unawaited(
                  _seek(SeekoCellTarget.cell(18, 9), animated: false),
                ),
                icon: const Icon(Icons.my_location),
              ),
              IconButton.filledTonal(
                key: const Key('two-dimensional-animate'),
                tooltip: 'Animate to keyed cell R32 C15',
                onPressed: () => unawaited(
                  _seek(SeekoCellTarget.key(_cellKey(32, 15)), animated: true),
                ),
                icon: const Icon(Icons.motion_photos_on_outlined),
              ),
              IconButton.filledTonal(
                key: const Key('two-dimensional-reset'),
                tooltip: 'Reset both axes',
                onPressed: () => unawaited(_reset()),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
            status: ScenarioStatusBadge(
              label: _lastResult?.outcome.name ?? 'Ready',
              widgetKey: const Key('two-dimensional-result'),
              tone: scenarioToneForOutcome(_lastResult?.outcome.name),
              icon: Icons.grid_on_outlined,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Column(
              children: <Widget>[
                _ViewportStatus(controller: _controller),
                const Divider(height: 1),
                Expanded(
                  child: SeekoTwoDimensionalViewportObserver(
                    controller: _controller,
                    child: Scrollbar(
                      controller: _controller.horizontalController,
                      thumbVisibility: true,
                      notificationPredicate:
                          (ScrollNotification notification) =>
                              notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        key: const Key('two-dimensional-horizontal'),
                        controller: _controller.horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: _layout.totalWidth,
                          child: Scrollbar(
                            controller: _controller.verticalController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              key: const Key('two-dimensional-vertical'),
                              controller: _controller.verticalController,
                              child: _CellSurface(
                                rowCount: _rowCount,
                                columnCount: _columnCount,
                                rowExtent: _rowExtent,
                                columnExtent: _columnExtent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewportStatus extends StatelessWidget {
  const _ViewportStatus({required this.controller});

  final SeekoTwoDimensionalController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SeekoTwoDimensionalSnapshot>(
      valueListenable: controller.state,
      builder: (BuildContext context, SeekoTwoDimensionalSnapshot value, _) {
        final SeekoCellCoordinate? first =
            value.visibleCells.firstOrNull?.coordinate;
        final String visible = first == null
            ? 'Waiting for viewport'
            : 'Leading cell R${first.row} C${first.column}';
        return Semantics(
          liveRegion: true,
          label: '$visible, ${value.visibleCells.length} visible cells',
          child: ScenarioPaneHeader(
            title: visible,
            description:
                '${value.visibleCells.length} visible · '
                'x ${value.horizontalPixels.toStringAsFixed(0)} · '
                'y ${value.verticalPixels.toStringAsFixed(0)}',
            trailing: const ScenarioStatusBadge(
              label: '2 axes',
              icon: Icons.open_with,
              tone: ScenarioStatusTone.active,
            ),
          ),
        );
      },
    );
  }
}

class _CellSurface extends StatelessWidget {
  const _CellSurface({
    required this.rowCount,
    required this.columnCount,
    required this.rowExtent,
    required this.columnExtent,
  });

  final int rowCount;
  final int columnCount;
  final double rowExtent;
  final double columnExtent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Two-dimensional data grid',
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var row = 0; row < rowCount; row++)
            SizedBox(
              height: rowExtent,
              child: Row(
                children: <Widget>[
                  for (var column = 0; column < columnCount; column++)
                    Semantics(
                      label: 'Row $row, column $column',
                      child: Container(
                        key: Key(
                          _TwoDimensionalPageState._cellKey(row, column),
                        ),
                        width: columnExtent,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: row == 0 || column == 0
                              ? colors.primaryContainer.withValues(alpha: 0.45)
                              : row.isEven
                              ? colors.surface
                              : colors.surfaceContainerLowest,
                          border: Border(
                            right: BorderSide(color: colors.outlineVariant),
                            bottom: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: Text(
                          row == 0
                              ? (column == 0 ? 'Index' : 'Column $column')
                              : column == 0
                              ? 'Row $row'
                              : 'R$row · C$column',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
