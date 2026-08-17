import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class ProgressSyncPage extends StatefulWidget {
  const ProgressSyncPage({super.key});

  @override
  State<ProgressSyncPage> createState() => _ProgressSyncPageState();
}

class _ProgressSyncPageState extends State<ProgressSyncPage> {
  final SeekoController _leftController = SeekoController(
    debugLabel: 'progress-sync-left',
  );
  final SeekoController _rightController = SeekoController(
    debugLabel: 'progress-sync-right',
  );
  late final ScrollSyncGroup _group;

  @override
  void initState() {
    super.initState();
    _group = ScrollSyncGroup.progress()
      ..add(_leftController, id: 'compact-catalog')
      ..add(_rightController, id: 'detail-catalog');
  }

  @override
  void dispose() {
    _group.dispose();
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  void _reset() {
    if (_leftController.isAttached) _leftController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('progress-sync-page'),
      child: Column(
        children: <Widget>[
          _Header(group: _group, onReset: _reset),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool compact = constraints.maxWidth < 720;
                final Widget left = _SyncList(
                  key: const Key('progress-sync-left'),
                  controller: _leftController,
                  title: 'Compact catalog',
                  itemCount: 72,
                  heightFor: (int index) => 58.0 + (index % 4) * 11,
                  color: Theme.of(context).colorScheme.primary,
                  progressKey: const Key('progress-left-value'),
                );
                final Widget right = _SyncList(
                  key: const Key('progress-sync-right'),
                  controller: _rightController,
                  title: 'Detailed catalog',
                  itemCount: 41,
                  heightFor: (int index) => 96.0 + (index % 5) * 17,
                  color: Theme.of(context).colorScheme.secondary,
                  progressKey: const Key('progress-right-value'),
                );
                if (compact) {
                  return Column(
                    children: <Widget>[
                      Expanded(child: left),
                      const Divider(height: 1),
                      Expanded(child: right),
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: left),
                    const VerticalDivider(width: 1),
                    Expanded(child: right),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group, required this.onReset});

  final ScrollSyncGroup group;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ScenarioPageHeader(
      title: 'Progress Synchronization',
      description:
          'Two native lists with different lengths and row heights share one '
          'normalized scroll coordinate.',
      actions: <Widget>[
        IconButton.filledTonal(
          tooltip: 'Reset synchronized views',
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt),
        ),
      ],
      status: AnimatedBuilder(
        animation: group,
        builder: (BuildContext context, _) => ScenarioStatusBadge(
          label: '${group.memberCount} views',
          icon: Icons.sync,
          tone: ScenarioStatusTone.active,
        ),
      ),
    );
  }
}

class _SyncList extends StatelessWidget {
  const _SyncList({
    required super.key,
    required this.controller,
    required this.title,
    required this.itemCount,
    required this.heightFor,
    required this.color,
    required this.progressKey,
  });

  final SeekoController controller;
  final String title;
  final int itemCount;
  final double Function(int index) heightFor;
  final Color color;
  final Key progressKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ScenarioPaneHeader(
          title: title,
          description: '$itemCount rows · variable extent',
          trailing: ValueListenableBuilder<ScrollSnapshot>(
            valueListenable: controller.state,
            builder: (BuildContext context, ScrollSnapshot value, _) {
              final double progress = (value.progress ?? 0) * 100;
              return Text(
                '${progress.toStringAsFixed(1)}%',
                key: progressKey,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: color),
              );
            },
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: controller,
            child: ListView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: itemCount,
              itemBuilder: (BuildContext context, int index) {
                final double height = heightFor(index);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: index.isEven ? 0.07 : 0.11,
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: color.withValues(alpha: 0.18),
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          child: Text('${index + 1}'),
                        ),
                        title: Text('Catalog entry ${index + 1}'),
                        subtitle: Text(
                          '${height.toStringAsFixed(0)} px minimum extent',
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
