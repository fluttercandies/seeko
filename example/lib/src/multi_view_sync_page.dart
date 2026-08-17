import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class MultiViewSyncPage extends StatefulWidget {
  const MultiViewSyncPage({super.key});

  @override
  State<MultiViewSyncPage> createState() => _MultiViewSyncPageState();
}

enum _SyncMappingChoice {
  pixels,
  progress,
  delta,
  viewportFraction,
  semantic,
  custom,
}

class _MultiViewSyncPageState extends State<MultiViewSyncPage> {
  static const int _capacity = 8;

  late final List<SeekoController> _controllers;
  late List<ScrollSyncMember> _members;
  late ScrollSyncGroup _group;
  int _visibleCount = 2;
  int _leaderIndex = 0;
  _SyncMappingChoice _mapping = _SyncMappingChoice.progress;
  ScrollSyncMode _mode = ScrollSyncMode.strict;
  ScrollSyncBoundaryPolicy _boundaryPolicy =
      ScrollSyncBoundaryPolicy.perMemberClamp;
  ScrollSyncMemberFailurePolicy _memberFailurePolicy =
      ScrollSyncMemberFailurePolicy.removeAndContinue;

  static const NaturalSyncPhysicsProfile _naturalProfile =
      NaturalSyncPhysicsProfile(
        settleDuration: Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        convergesToTarget: true,
        boundedDuration: true,
        supportsExternalInitialVelocity: false,
        snapBehavior: NaturalSyncSnapBehavior.none,
      );

  @override
  void initState() {
    super.initState();
    _controllers = List<SeekoController>.generate(
      _capacity,
      (int index) => SeekoController(debugLabel: 'multi-view-$index'),
    );
    _group = _createGroup(_mapping);
    _attachMembers();
  }

  ScrollSyncGroup _createGroup(_SyncMappingChoice choice) => switch (choice) {
    _SyncMappingChoice.pixels => ScrollSyncGroup.pixels(
      mode: _mode,
      boundaryPolicy: _boundaryPolicy,
      memberFailurePolicy: _memberFailurePolicy,
    ),
    _SyncMappingChoice.progress => ScrollSyncGroup.progress(
      mode: _mode,
      boundaryPolicy: _boundaryPolicy,
      memberFailurePolicy: _memberFailurePolicy,
    ),
    _SyncMappingChoice.delta => ScrollSyncGroup.delta(
      mode: _mode,
      boundaryPolicy: _boundaryPolicy,
      memberFailurePolicy: _memberFailurePolicy,
    ),
    _SyncMappingChoice.viewportFraction => ScrollSyncGroup.viewportFraction(
      mode: _mode,
      boundaryPolicy: _boundaryPolicy,
      memberFailurePolicy: _memberFailurePolicy,
    ),
    _SyncMappingChoice.semantic => ScrollSyncGroup.semantic(
      missingAnchorPolicy: ScrollSyncMissingAnchorPolicy.fallbackProgress,
      mode: _mode,
      memberFailurePolicy: _memberFailurePolicy,
    ),
    _SyncMappingChoice.custom => ScrollSyncGroup(
      mapping: ScrollSyncMapping.custom(
        memberToGroup: (SyncMetrics member, _) => math.sqrt(member.progress),
        groupToMember: (double coordinate, SyncMetrics member, _) =>
            member.minScrollExtent +
            coordinate * coordinate * member.scrollRange,
      ),
      mode: _mode,
      boundaryPolicy: _boundaryPolicy,
      memberFailurePolicy: _memberFailurePolicy,
    ),
  };

  void _attachMembers() {
    _members = <ScrollSyncMember>[
      for (var index = 0; index < _capacity; index++)
        _group.add(
          _controllers[index],
          id: 'view-$index',
          role: index == _leaderIndex
              ? ScrollSyncRole.leaderOnly
              : ScrollSyncRole.followerOnly,
          naturalPhysicsProfile: _mode == ScrollSyncMode.natural
              ? _naturalProfile
              : null,
        ),
    ];
    for (var index = _visibleCount; index < _capacity; index++) {
      _members[index].participation = ScrollSyncParticipation.offstage;
    }
  }

  void _setMapping(_SyncMappingChoice choice) {
    if (choice == _mapping) return;
    _group.dispose();
    _mapping = choice;
    _group = _createGroup(choice);
    _attachMembers();
    setState(() {});
  }

  void _setMode(ScrollSyncMode mode) {
    if (mode == _mode) return;
    _group.dispose();
    _mode = mode;
    _group = _createGroup(_mapping);
    _attachMembers();
    setState(() {});
  }

  void _setBoundaryPolicy(ScrollSyncBoundaryPolicy policy) {
    if (policy == _boundaryPolicy) return;
    _group.dispose();
    _boundaryPolicy = policy;
    _group = _createGroup(_mapping);
    _attachMembers();
    setState(() {});
  }

  void _setMemberFailurePolicy(ScrollSyncMemberFailurePolicy policy) {
    if (policy == _memberFailurePolicy) return;
    _group.dispose();
    _memberFailurePolicy = policy;
    _group = _createGroup(_mapping);
    _attachMembers();
    setState(() {});
  }

  void _setLeaderIndex(int index) {
    if (index == _leaderIndex) return;
    _group.dispose();
    _leaderIndex = index;
    _group = _createGroup(_mapping);
    _attachMembers();
    setState(() {});
  }

  @override
  void dispose() {
    _group.dispose();
    for (final SeekoController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setVisibleCount(int count) {
    if (count == _visibleCount) return;
    for (var index = 0; index < _capacity; index++) {
      _members[index].participation = index < count
          ? ScrollSyncParticipation.active
          : ScrollSyncParticipation.offstage;
    }
    setState(() => _visibleCount = count);
  }

  void _reset() {
    if (_controllers.first.isAttached) _controllers.first.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('multi-view-sync-page'),
      child: Column(
        children: <Widget>[
          _Header(
            group: _group,
            mapping: _mapping,
            mode: _mode,
            boundaryPolicy: _boundaryPolicy,
            memberFailurePolicy: _memberFailurePolicy,
            leaderIndex: _leaderIndex,
            visibleCount: _visibleCount,
            onMappingChanged: _setMapping,
            onModeChanged: _setMode,
            onBoundaryChanged: _setBoundaryPolicy,
            onMemberFailureChanged: _setMemberFailurePolicy,
            onLeaderChanged: _setLeaderIndex,
            onCountChanged: _setVisibleCount,
            onReset: _reset,
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = _columnsFor(constraints.maxWidth);
                final int rows = (_visibleCount / columns).ceil();
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: <Widget>[
                      for (var row = 0; row < rows; row++) ...<Widget>[
                        if (row > 0) const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              for (
                                var column = 0;
                                column < columns;
                                column++
                              ) ...<Widget>[
                                if (column > 0) const SizedBox(width: 12),
                                Expanded(
                                  child: _buildCell(row * columns + column),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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

  int _columnsFor(double width) {
    if (width < 620) return 1;
    if (_visibleCount >= 8 && width >= 720) return 4;
    if (_visibleCount >= 4) return 2;
    return _visibleCount;
  }

  Widget _buildCell(int index) {
    if (index >= _visibleCount) return const SizedBox.shrink();
    return _SynchronizedList(controller: _controllers[index], index: index);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.group,
    required this.mapping,
    required this.mode,
    required this.boundaryPolicy,
    required this.memberFailurePolicy,
    required this.leaderIndex,
    required this.visibleCount,
    required this.onMappingChanged,
    required this.onModeChanged,
    required this.onBoundaryChanged,
    required this.onMemberFailureChanged,
    required this.onLeaderChanged,
    required this.onCountChanged,
    required this.onReset,
  });

  final ScrollSyncGroup group;
  final _SyncMappingChoice mapping;
  final ScrollSyncMode mode;
  final ScrollSyncBoundaryPolicy boundaryPolicy;
  final ScrollSyncMemberFailurePolicy memberFailurePolicy;
  final int leaderIndex;
  final int visibleCount;
  final ValueChanged<_SyncMappingChoice> onMappingChanged;
  final ValueChanged<ScrollSyncMode> onModeChanged;
  final ValueChanged<ScrollSyncBoundaryPolicy> onBoundaryChanged;
  final ValueChanged<ScrollSyncMemberFailurePolicy> onMemberFailureChanged;
  final ValueChanged<int> onLeaderChanged;
  final ValueChanged<int> onCountChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ScenarioPageHeader(
      title: '2 / 4 / 8 Synchronized Views',
      description:
          'Switch pixels, progress, delta, viewport-fraction, semantic, or '
          'custom canonical domains across native lists.',
      actions: <Widget>[
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<_SyncMappingChoice>(
            // Flutter 3.32 compatibility; renamed to initialValue later.
            // ignore: deprecated_member_use
            value: mapping,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Mapping'),
            items: <DropdownMenuItem<_SyncMappingChoice>>[
              for (final _SyncMappingChoice value in _SyncMappingChoice.values)
                DropdownMenuItem<_SyncMappingChoice>(
                  value: value,
                  child: Text(value.name),
                ),
            ],
            onChanged: (_SyncMappingChoice? value) {
              if (value != null) onMappingChanged(value);
            },
          ),
        ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<ScrollSyncMode>(
            // Flutter 3.32 compatibility; renamed to initialValue later.
            // ignore: deprecated_member_use
            value: mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Physics'),
            items: <DropdownMenuItem<ScrollSyncMode>>[
              for (final ScrollSyncMode value in ScrollSyncMode.values)
                DropdownMenuItem<ScrollSyncMode>(
                  value: value,
                  child: Text(value.name),
                ),
            ],
            onChanged: (ScrollSyncMode? value) {
              if (value != null) onModeChanged(value);
            },
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<ScrollSyncBoundaryPolicy>(
            // Flutter 3.32 compatibility; renamed to initialValue later.
            // ignore: deprecated_member_use
            value: boundaryPolicy,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Boundary'),
            items: <DropdownMenuItem<ScrollSyncBoundaryPolicy>>[
              for (final ScrollSyncBoundaryPolicy value
                  in ScrollSyncBoundaryPolicy.values)
                DropdownMenuItem<ScrollSyncBoundaryPolicy>(
                  value: value,
                  child: Text(value.name),
                ),
            ],
            onChanged: mapping == _SyncMappingChoice.semantic
                ? null
                : (ScrollSyncBoundaryPolicy? value) {
                    if (value != null) onBoundaryChanged(value);
                  },
          ),
        ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<int>(
            // Flutter 3.32 compatibility; renamed to initialValue later.
            // ignore: deprecated_member_use
            value: leaderIndex,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Leader'),
            items: <DropdownMenuItem<int>>[
              for (var index = 0; index < 8; index++)
                DropdownMenuItem<int>(
                  value: index,
                  child: Text('View ${index + 1}'),
                ),
            ],
            onChanged: (int? value) {
              if (value != null) onLeaderChanged(value);
            },
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<ScrollSyncMemberFailurePolicy>(
            // Flutter 3.32 compatibility; renamed to initialValue later.
            // ignore: deprecated_member_use
            value: memberFailurePolicy,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Member failure'),
            items: <DropdownMenuItem<ScrollSyncMemberFailurePolicy>>[
              for (final ScrollSyncMemberFailurePolicy value
                  in ScrollSyncMemberFailurePolicy.values)
                DropdownMenuItem<ScrollSyncMemberFailurePolicy>(
                  value: value,
                  child: Text(value.name),
                ),
            ],
            onChanged: (ScrollSyncMemberFailurePolicy? value) {
              if (value != null) onMemberFailureChanged(value);
            },
          ),
        ),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(
              value: 2,
              label: Text('2', key: Key('multi-view-count-2')),
              tooltip: 'Show 2 synchronized views',
            ),
            ButtonSegment<int>(
              value: 4,
              label: Text('4', key: Key('multi-view-count-4')),
              tooltip: 'Show 4 synchronized views',
            ),
            ButtonSegment<int>(
              value: 8,
              label: Text('8', key: Key('multi-view-count-8')),
              tooltip: 'Show 8 synchronized views',
            ),
          ],
          selected: <int>{visibleCount},
          onSelectionChanged: (Set<int> value) => onCountChanged(value.first),
        ),
        IconButton.filledTonal(
          tooltip: 'Reset all synchronized views',
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt),
        ),
      ],
      status: AnimatedBuilder(
        animation: group,
        builder: (BuildContext context, _) => ScenarioStatusBadge(
          label:
              '${group.activeMemberCount} active · leader ${group.activeLeaderId ?? 'pending'}',
          icon: Icons.hub_outlined,
          tone: ScenarioStatusTone.active,
        ),
      ),
    );
  }
}

class _SynchronizedList extends StatelessWidget {
  const _SynchronizedList({required this.controller, required this.index});

  final SeekoController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          children: <Widget>[
            ColoredBox(
              color: color.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text('View ${index + 1}')),
                    ValueListenableBuilder<ScrollSnapshot>(
                      valueListenable: controller.state,
                      builder: (_, ScrollSnapshot value, _) => Text(
                        '${((value.progress ?? 0) * 100).toStringAsFixed(1)}%',
                        key: Key('multi-view-progress-$index'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: Key('multi-view-list-$index'),
                controller: controller,
                padding: const EdgeInsets.all(8),
                itemCount: 36 + index * 5,
                itemBuilder: (BuildContext context, int itemIndex) => SeekoTag(
                  controller: controller,
                  targetKey: 'sync-item-$itemIndex',
                  index: itemIndex,
                  child: SizedBox(
                    height: 42.0 + ((itemIndex + index) % 3) * 12,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text('${index + 1}.${itemIndex + 1}'),
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
    );
  }
}
