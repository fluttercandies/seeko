import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class ComplexSliverPage extends StatefulWidget {
  const ComplexSliverPage({super.key});

  @override
  State<ComplexSliverPage> createState() => _ComplexSliverPageState();
}

class _ComplexSliverPageState extends State<ComplexSliverPage> {
  late final SeekoController _controller;
  ScrollResult? _result;

  @override
  void initState() {
    super.initState();
    _controller = SeekoController(
      debugLabel: 'complex-slivers',
      obstructionResolver: (ScrollViewportGeometry viewport) {
        final double start = viewport.viewportExtent < 112 ? 0 : 112;
        return VisibleRegion.fromIntervals(<LogicalInterval>[
          LogicalInterval(start, viewport.viewportExtent),
        ]);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _seek(Object key) async {
    final ScrollResult result = await _controller.animateToTarget(
      ScrollTarget.key(key),
      placement: const ScrollPlacement.center(),
    );
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('complex-sliver-page'),
      child: Column(
        children: <Widget>[
          _Header(
            result: _result,
            onOverview: () => unawaited(_seek('sliver-overview')),
            onActivity: () => unawaited(_seek('sliver-activity')),
            onFooter: () => unawaited(_seek('sliver-footer')),
          ),
          const Divider(height: 1),
          Expanded(
            child: CustomScrollView(
              key: const Key('complex-sliver-scroll-view'),
              controller: _controller,
              // Flutter 3.32 compatibility; renamed in Flutter 3.41.
              // ignore: deprecated_member_use
              cacheExtent: 10000,
              slivers: <Widget>[
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 176,
                  automaticallyImplyLeading: false,
                  flexibleSpace: FlexibleSpaceBar(
                    title: const Text('Native sliver composition'),
                    background: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 28),
                          child: Icon(
                            Icons.view_stream_outlined,
                            size: 72,
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SeekoTag(
                    controller: _controller,
                    targetKey: 'sliver-overview',
                    child: const _Overview(),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: const _PinnedFilterHeader(),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => SeekoTag(
                      controller: _controller,
                      targetKey: 'story-$index',
                      child: _StoryRow(index: index),
                    ),
                    childCount: 6,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 280,
                          mainAxisExtent: 156,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final bool isTarget = index == 5;
                      return SeekoTag(
                        controller: _controller,
                        targetKey: isTarget
                            ? 'sliver-activity'
                            : 'activity-$index',
                        child: _ActivityCard(
                          key: isTarget
                              ? const Key('complex-sliver-target-activity')
                              : null,
                          index: index,
                        ),
                      );
                    }, childCount: 12),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SeekoTag(
                    controller: _controller,
                    targetKey: 'sliver-footer',
                    child: const _Footer(),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.result,
    required this.onOverview,
    required this.onActivity,
    required this.onFooter,
  });

  final ScrollResult? result;
  final VoidCallback onOverview;
  final VoidCallback onActivity;
  final VoidCallback onFooter;

  @override
  Widget build(BuildContext context) {
    final String status = result?.outcome.name ?? 'Ready';
    return ScenarioPageHeader(
      title: 'Complex CustomScrollView',
      description:
          'Seek across app bars, box adapters, lists, a pinned header, a grid, '
          'and a footer without replacing Flutter slivers.',
      actions: <Widget>[
        OutlinedButton(onPressed: onOverview, child: const Text('Overview')),
        FilledButton.icon(
          key: const Key('complex-sliver-seek-activity'),
          onPressed: onActivity,
          icon: const Icon(Icons.grid_view),
          label: const Text('Activity grid'),
        ),
        OutlinedButton(onPressed: onFooter, child: const Text('Footer')),
      ],
      status: ScenarioStatusBadge(
        label: status,
        widgetKey: const Key('complex-sliver-result'),
        icon: Icons.route_outlined,
        tone: scenarioToneForOutcome(result?.outcome.name),
      ),
    );
  }
}

class _PinnedFilterHeader extends SliverPersistentHeaderDelegate {
  const _PinnedFilterHeader();

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: overlapsContent ? 2 : 0,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Icon(Icons.filter_list, size: 20),
              SizedBox(width: 10),
              Text('Pinned activity filters'),
              Spacer(),
              Chip(label: Text('All events')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedFilterHeader oldDelegate) => false;
}

class _Overview extends StatelessWidget {
  const _Overview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Every target is registered by SeekoTag, while layout, painting, '
            'physics, cache extent, and sliver composition stay native.',
          ),
        ),
      ),
    );
  }
}

class _StoryRow extends StatelessWidget {
  const _StoryRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92.0 + (index % 3) * 16,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text('Timeline story ${index + 1}'),
        subtitle: const Text('A variable-height row inside SliverList.'),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.insights_outlined,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const Spacer(),
            Text('Activity ${index + 1}'),
            Text('${(index + 1) * 137} events'),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Text('Footer target across the final SliverToBoxAdapter'),
    );
  }
}
