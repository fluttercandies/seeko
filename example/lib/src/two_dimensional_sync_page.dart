import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class TwoDimensionalSyncPage extends StatefulWidget {
  const TwoDimensionalSyncPage({super.key});

  @override
  State<TwoDimensionalSyncPage> createState() => _TwoDimensionalSyncPageState();
}

class _TwoDimensionalSyncPageState extends State<TwoDimensionalSyncPage> {
  static const int _rowCount = 30;
  static const int _columnCount = 16;
  static const double _rowExtent = 54;
  static const double _columnExtent = 126;

  late final SeekoFiniteTwoDimensionalLayout _layout;
  late final List<SeekoTwoDimensionalController> _controllers;
  late SeekoTwoDimensionalSyncGroup _group;
  SeekoTwoDimensionalSyncMode _mode = SeekoTwoDimensionalSyncMode.progress;
  int _leaderIndex = 0;
  bool _joined = true;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _layout = SeekoFiniteTwoDimensionalLayout.fixed(
      rowCount: _rowCount,
      columnCount: _columnCount,
      rowExtent: _rowExtent,
      columnExtent: _columnExtent,
      keyAt: (int row, int column) => 'cell-$row-$column',
      coordinateOfKey: (Object key) {
        if (key is! String) return null;
        final RegExpMatch? match = RegExp(
          r'^cell-(\d+)-(\d+)$',
        ).firstMatch(key);
        if (match == null) return null;
        return SeekoCellCoordinate(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
        );
      },
    );
    _controllers = <SeekoTwoDimensionalController>[
      SeekoTwoDimensionalController(layout: _layout),
      SeekoTwoDimensionalController(layout: _layout),
    ];
    _group = SeekoTwoDimensionalSyncGroup(mode: _mode);
    _rebuildGroup();
  }

  void _rebuildGroup() {
    _group.dispose();
    _group = SeekoTwoDimensionalSyncGroup(mode: _mode);
    _group.add(
      _controllers[0],
      member: SeekoTwoDimensionalSyncMember(
        role: _leaderIndex == 0
            ? SeekoTwoDimensionalSyncRole.leader
            : SeekoTwoDimensionalSyncRole.follower,
        priority: _leaderIndex == 0 ? 10 : 0,
      ),
    );
    if (_joined) {
      _group.add(
        _controllers[1],
        member: SeekoTwoDimensionalSyncMember(
          role: _leaderIndex == 1
              ? SeekoTwoDimensionalSyncRole.leader
              : SeekoTwoDimensionalSyncRole.follower,
          priority: _leaderIndex == 1 ? 10 : 0,
        ),
      );
    }
  }

  void _setMode(SeekoTwoDimensionalSyncMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _rebuildGroup();
    setState(() => _status = 'Mode: ${mode.name}');
  }

  void _setLeader(int index) {
    if (_leaderIndex == index) return;
    if (index == 1 && !_joined) _joined = true;
    _leaderIndex = index;
    _rebuildGroup();
    setState(() => _status = 'Leader: view ${index + 1}');
  }

  void _toggleMember() {
    _joined = !_joined;
    _rebuildGroup();
    setState(() => _status = _joined ? 'View 2 rejoined' : 'View 2 detached');
  }

  Future<void> _seek({required bool animate}) async {
    final SeekoTwoDimensionalGroupResult result = animate
        ? await _group.animateToCell(
            SeekoCellTarget.cell(20, 10),
            placement: const SeekoTwoDimensionalPlacement.center(),
          )
        : await _group.jumpToCell(
            SeekoCellTarget.cell(20, 10),
            placement: const SeekoTwoDimensionalPlacement.center(),
          );
    if (mounted) setState(() => _status = result.outcome.name);
  }

  @override
  void dispose() {
    _group.dispose();
    for (final SeekoTwoDimensionalController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('two-dimensional-sync-page'),
      child: Column(
        children: <Widget>[
          ScenarioPageHeader(
            title: 'Two-dimensional Synchronization',
            description:
                'Two native row/column surfaces share a pixels or progress domain. '
                'The follower can detach and catch up on rejoin.',
            actions: <Widget>[
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<SeekoTwoDimensionalSyncMode>(
                  // Flutter 3.32 compatibility; renamed to initialValue later.
                  // ignore: deprecated_member_use
                  value: _mode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Mapping'),
                  items: <DropdownMenuItem<SeekoTwoDimensionalSyncMode>>[
                    for (final SeekoTwoDimensionalSyncMode value
                        in SeekoTwoDimensionalSyncMode.values)
                      DropdownMenuItem<SeekoTwoDimensionalSyncMode>(
                        value: value,
                        child: Text(
                          value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (SeekoTwoDimensionalSyncMode? value) {
                    if (value != null) _setMode(value);
                  },
                ),
              ),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<int>(
                  // Flutter 3.32 compatibility; renamed to initialValue later.
                  // ignore: deprecated_member_use
                  value: _leaderIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Leader'),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem<int>(value: 0, child: Text('View 1')),
                    DropdownMenuItem<int>(value: 1, child: Text('View 2')),
                  ],
                  onChanged: (int? value) {
                    if (value != null) _setLeader(value);
                  },
                ),
              ),
              IconButton.filledTonal(
                key: const Key('two-dimensional-sync-toggle'),
                tooltip: 'Detach or rejoin view 2',
                onPressed: _toggleMember,
                icon: Icon(
                  _joined ? Icons.link_off_rounded : Icons.link_rounded,
                ),
              ),
              IconButton.filledTonal(
                key: const Key('two-dimensional-sync-jump'),
                tooltip: 'Jump both views to row 20 column 10',
                onPressed: () => unawaited(_seek(animate: false)),
                icon: const Icon(Icons.flash_on_outlined),
              ),
              IconButton.filledTonal(
                key: const Key('two-dimensional-sync-animate'),
                tooltip: 'Animate both views to row 20 column 10',
                onPressed: () => unawaited(_seek(animate: true)),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
            status: ScenarioStatusBadge(
              label: '${_group.length} joined · $_status',
              widgetKey: const Key('two-dimensional-sync-status'),
              tone: ScenarioStatusTone.active,
              icon: Icons.grid_view_rounded,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool narrow = constraints.maxWidth < 900;
                final List<Widget> panels = <Widget>[
                  _buildPanel(0, const Color(0xFF4C7DFF)),
                  if (_joined) _buildPanel(1, const Color(0xFF16C79A)),
                ];
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: narrow
                      ? Column(
                          children: <Widget>[
                            for (var index = 0; index < panels.length; index++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index + 1 == panels.length ? 0 : 12,
                                  ),
                                  child: panels[index],
                                ),
                              ),
                          ],
                        )
                      : Row(
                          children: <Widget>[
                            for (var index = 0; index < panels.length; index++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: index + 1 == panels.length ? 0 : 12,
                                  ),
                                  child: panels[index],
                                ),
                              ),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(int index, Color accent) {
    final SeekoTwoDimensionalController controller = _controllers[index];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SeekoTwoDimensionalViewportObserver(
          controller: controller,
          child: Scrollbar(
            controller: controller.horizontalController,
            thumbVisibility: true,
            notificationPredicate: (ScrollNotification notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: controller.horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _layout.totalWidth,
                child: Scrollbar(
                  controller: controller.verticalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: controller.verticalController,
                    child: _GridSurface(
                      rowCount: _rowCount,
                      columnCount: _columnCount,
                      rowExtent: _rowExtent,
                      columnExtent: _columnExtent,
                      accent: accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridSurface extends StatelessWidget {
  const _GridSurface({
    required this.rowCount,
    required this.columnCount,
    required this.rowExtent,
    required this.columnExtent,
    required this.accent,
  });

  final int rowCount;
  final int columnCount;
  final double rowExtent;
  final double columnExtent;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Synchronized two-dimensional grid',
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
                        width: columnExtent,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: row == 0 || column == 0
                              ? accent.withValues(alpha: 0.18)
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
