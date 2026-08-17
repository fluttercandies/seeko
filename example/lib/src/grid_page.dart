import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';
import 'seeko_theme.dart';

class GridPage extends StatefulWidget {
  const GridPage({super.key});

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage> {
  static const int _itemCount = 240;
  late final SeekoController _controller;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  late final ListSeekoIndexDelegate<Object> _indexDelegate;
  final TextEditingController _targetController = TextEditingController(
    text: '137',
  );
  String _lastOutcome = 'Ready';

  @override
  void initState() {
    super.initState();
    _indexDelegate = ListSeekoIndexDelegate<Object>(
      itemCount: _itemCount,
      revision: _revision,
      keyAt: (int index) => 'cell-$index',
      indexOfKey: (Object key) {
        if (key is! String || !key.startsWith('cell-')) {
          return null;
        }
        return int.tryParse(key.substring(5));
      },
    );
    _controller = SeekoController(
      initialTarget: ScrollTarget.index(137),
      initialPlacement: const ScrollPlacement.center(),
    );
    final Future<SeekoInitialTargetResult>? initial =
        _controller.initialTargetResult;
    if (initial != null) {
      unawaited(
        initial.then((SeekoInitialTargetResult result) {
          if (mounted) {
            setState(() => _lastOutcome = 'initial:${result.outcome.name}');
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _revision.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _move({required bool animate}) async {
    final int? index = int.tryParse(_targetController.text.trim());
    if (index == null || index < 0 || index >= _itemCount) {
      setState(
        () => _lastOutcome = 'Enter an index from 0 to ${_itemCount - 1}',
      );
      return;
    }
    final ScrollResult result = animate
        ? await _controller.animateToTarget(
            ScrollTarget.index(index),
            placement: const ScrollPlacement.center(),
            motion: const ScrollMotion.adaptive(),
          )
        : await _controller.jumpToTarget(
            ScrollTarget.index(index),
            placement: const ScrollPlacement.center(),
          );
    if (mounted) {
      setState(() => _lastOutcome = result.outcome.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        children: <Widget>[
          ScenarioPageHeader(
            title: 'Grid driver',
            description:
                'Native CustomScrollView + SeekoIndexedGridSliver. Cells stay virtualized while key/index targets resolve off-screen.',
            actions: <Widget>[
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cell',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _move(animate: true),
                ),
              ),
              FilledButton.tonalIcon(
                key: const Key('grid-jump'),
                onPressed: () => _move(animate: false),
                icon: const Icon(Icons.flash_on_outlined),
                label: const Text('Jump'),
              ),
              FilledButton.icon(
                key: const Key('grid-animate'),
                onPressed: () => _move(animate: true),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Animate'),
              ),
            ],
            status: ScenarioStatusBadge(
              label: _lastOutcome,
              icon: Icons.grid_view_rounded,
              tone: scenarioToneForOutcome(_lastOutcome),
              widgetKey: const Key('grid-outcome'),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<ScrollSnapshot>(
              valueListenable: _controller.state,
              builder: (BuildContext context, ScrollSnapshot snapshot, _) {
                return Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Row(
                        children: <Widget>[
                          Text(
                            'logical ${snapshot.pixels.toStringAsFixed(0)}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: snapshot.progress,
                              minHeight: 5,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${snapshot.visibleTargets.length} visible',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: CustomScrollView(
                        key: const Key('grid-scroll-view'),
                        controller: _controller,
                        slivers: <Widget>[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            sliver: SeekoIndexedGridSliver(
                              controller: _controller,
                              indexDelegate: _indexDelegate,
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 220,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 1.22,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                BuildContext context,
                                int index,
                              ) {
                                final int hue = (index * 37) % 360;
                                return DecoratedBox(
                                  key: ValueKey<String>('cell-$index'),
                                  decoration: BoxDecoration(
                                    color: HSLColor.fromAHSL(
                                      1,
                                      hue.toDouble(),
                                      0.48,
                                      0.93,
                                    ).toColor(),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Icon(
                                        Icons.blur_on_rounded,
                                        size: 28,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(height: 9),
                                      Text(
                                        'Cell $index',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: SeekoColors.deepInk,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'key: cell-$index',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF526071),
                                            ),
                                      ),
                                    ],
                                  ),
                                );
                              }, childCount: _itemCount),
                            ),
                          ),
                        ],
                      ),
                    ),
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
