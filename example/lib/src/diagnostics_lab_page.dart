import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class DiagnosticsLabPage extends StatefulWidget {
  const DiagnosticsLabPage({super.key});

  @override
  State<DiagnosticsLabPage> createState() => _DiagnosticsLabPageState();
}

class _DiagnosticsLabPageState extends State<DiagnosticsLabPage> {
  static const int _itemCount = 10000;
  final SeekoController _primary = SeekoController(
    debugLabel: 'diagnostics-primary',
  );
  final SeekoController _follower = SeekoController(
    debugLabel: 'diagnostics-follower',
  );
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  final ScrollDiagnostics _diagnostics = ScrollDiagnostics(capacity: 180);
  late final ListSeekoIndexDelegate<Object> _indexDelegate;
  late final ScrollSyncGroup _group;
  final List<FrameTiming> _frameTimings = <FrameTiming>[];
  Timer? _timingRefresh;
  bool _overlayEnabled = false;
  bool _rawEventsEnabled = false;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _indexDelegate = ListSeekoIndexDelegate<Object>(
      itemCount: _itemCount,
      revision: _revision,
      keyAt: (int index) => 'diagnostic-item-$index',
      indexOfKey: (Object key) {
        if (key is! String || !key.startsWith('diagnostic-item-')) {
          return null;
        }
        return int.tryParse(key.substring('diagnostic-item-'.length));
      },
    );
    _group = ScrollSyncGroup.progress()
      ..add(_primary, id: 'long-indexed-list')
      ..add(_follower, id: 'compact-follower');
    _attachDiagnostics();
    _diagnostics.attachSyncGroup(_group, label: 'progress-sync');
    SchedulerBinding.instance.addTimingsCallback(_handleTimings);
  }

  void _attachDiagnostics() {
    _diagnostics
      ..attachController(
        _primary,
        label: 'long-indexed-list',
        includeRawEvents: _rawEventsEnabled,
      )
      ..attachController(
        _follower,
        label: 'compact-follower',
        includeRawEvents: _rawEventsEnabled,
      );
  }

  void _setRawEvents(bool enabled) {
    if (_rawEventsEnabled == enabled) {
      return;
    }
    _diagnostics
      ..detachController(_primary)
      ..detachController(_follower);
    setState(() => _rawEventsEnabled = enabled);
    _attachDiagnostics();
  }

  void _handleTimings(List<FrameTiming> timings) {
    _frameTimings.addAll(timings);
    if (_frameTimings.length > 240) {
      _frameTimings.removeRange(0, _frameTimings.length - 240);
    }
    _timingRefresh ??= Timer(const Duration(milliseconds: 500), () {
      _timingRefresh = null;
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _move({required bool animate}) async {
    final ScrollResult result = animate
        ? await _primary.animateToIndex(
            9000,
            placement: const ScrollPlacement.center(),
          )
        : await _primary.jumpToIndex(
            9000,
            placement: const ScrollPlacement.center(),
          );
    if (mounted) {
      setState(() => _status = result.outcome.name);
    }
  }

  void _runCommandBurst() {
    const List<int> targets = <int>[120, 4600, 720, 8800, 2400, 9990, 80, 6400];
    for (final int target in targets) {
      unawaited(
        _primary.animateToIndex(
          target,
          placement: const ScrollPlacement.center(),
          options: const ScrollCommandOptions(
            conflictPolicy: ScrollConflictPolicy.coalesce,
          ),
        ),
      );
    }
    setState(() => _status = 'Coalescing ${targets.length} commands');
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
    _timingRefresh?.cancel();
    _diagnostics.dispose();
    _group.dispose();
    _primary.dispose();
    _follower.dispose();
    _revision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ScenarioPageHeader(
          title: 'Diagnostics & Performance Lab',
          description:
              'Inspect bounded command, snapshot, raw position, and sync evidence without enabling production hot-path work by default.',
          actions: <Widget>[
            FilledButton.tonalIcon(
              key: const Key('diagnostics-jump-far'),
              onPressed: () => _move(animate: false),
              icon: const Icon(Icons.flash_on_outlined),
              label: const Text('Jump far'),
            ),
            FilledButton.icon(
              key: const Key('diagnostics-animate-far'),
              onPressed: () => _move(animate: true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Animate far'),
            ),
            OutlinedButton.icon(
              key: const Key('diagnostics-command-burst'),
              onPressed: _runCommandBurst,
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Command burst'),
            ),
          ],
          status: ScenarioStatusBadge(
            label: _status,
            widgetKey: const Key('diagnostics-status'),
            icon: Icons.monitor_heart_outlined,
            tone: scenarioToneForOutcome(_status),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget workspace = SeekoDiagnosticsOverlay(
                diagnostics: _diagnostics,
                enabled: _overlayEnabled,
                alignment: Alignment.bottomRight,
                child: _ScrollEvidenceWorkspace(
                  primary: _primary,
                  follower: _follower,
                  indexDelegate: _indexDelegate,
                ),
              );
              final Widget evidence = _EvidencePanel(
                diagnostics: _diagnostics,
                timings: _frameTimings,
                overlayEnabled: _overlayEnabled,
                rawEventsEnabled: _rawEventsEnabled,
                onOverlayChanged: (bool value) {
                  setState(() => _overlayEnabled = value);
                },
                onRawEventsChanged: _setRawEvents,
                onClear: _diagnostics.clear,
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  children: <Widget>[
                    Expanded(flex: 2, child: workspace),
                    const Divider(height: 1),
                    Expanded(flex: 3, child: evidence),
                  ],
                );
              }
              if (constraints.maxWidth < 980 && constraints.maxHeight >= 420) {
                return Column(
                  children: <Widget>[
                    Expanded(child: workspace),
                    const Divider(height: 1),
                    SizedBox(height: 270, child: evidence),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: workspace),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 360, child: evidence),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ScrollEvidenceWorkspace extends StatelessWidget {
  const _ScrollEvidenceWorkspace({
    required this.primary,
    required this.follower,
    required this.indexDelegate,
  });

  final SeekoController primary;
  final SeekoController follower;
  final ListSeekoIndexDelegate<Object> indexDelegate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: _LabPane(
            title: '10,000 indexed targets',
            controller: primary,
            child: CustomScrollView(
              key: const Key('diagnostics-primary-list'),
              controller: primary,
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  sliver: SeekoIndexedSliver(
                    controller: primary,
                    indexDelegate: indexDelegate,
                    estimatedExtent: 66,
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final double minimumHeight = 54 + (index % 4) * 9;
                      return SeekoTag(
                        controller: primary,
                        targetKey: 'diagnostic-item-$index',
                        index: index,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: minimumHeight),
                          child: _DiagnosticRow(
                            index: index,
                            label: 'Indexed target',
                          ),
                        ),
                      );
                    }, childCount: _DiagnosticsLabPageState._itemCount),
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _LabPane(
            title: 'Progress follower',
            controller: follower,
            child: ListView.builder(
              key: const Key('diagnostics-follower-list'),
              controller: follower,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: 180,
              itemBuilder: (BuildContext context, int index) {
                return ConstrainedBox(
                  constraints: BoxConstraints(minHeight: 72 + (index % 3) * 8),
                  child: _DiagnosticRow(index: index, label: 'Follower row'),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _LabPane extends StatelessWidget {
  const _LabPane({
    required this.title,
    required this.controller,
    required this.child,
  });

  final String title;
  final SeekoController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ValueListenableBuilder<ScrollSnapshot>(
          valueListenable: controller.state,
          builder: (BuildContext context, ScrollSnapshot snapshot, _) {
            return ScenarioPaneHeader(
              title: title,
              description:
                  '${snapshot.pixels.toStringAsFixed(0)} px · ${snapshot.phase.name} · ${snapshot.visibleTargets.length} visible',
            );
          },
        ),
        const Divider(height: 1),
        Expanded(child: child),
      ],
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Container(
                constraints: const BoxConstraints(minWidth: 42),
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('$label $index'),
                    Text(
                      'stable coordinate ${index.toString().padLeft(5, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.diagnostics,
    required this.timings,
    required this.overlayEnabled,
    required this.rawEventsEnabled,
    required this.onOverlayChanged,
    required this.onRawEventsChanged,
    required this.onClear,
  });

  final ScrollDiagnostics diagnostics;
  final List<FrameTiming> timings;
  final bool overlayEnabled;
  final bool rawEventsEnabled;
  final ValueChanged<bool> onOverlayChanged;
  final ValueChanged<bool> onRawEventsChanged;
  final VoidCallback onClear;

  double _percentile(
    Duration Function(FrameTiming timing) selector,
    double percentile,
  ) {
    if (timings.isEmpty) {
      return 0;
    }
    final List<int> values = <int>[
      for (final FrameTiming timing in timings) selector(timing).inMicroseconds,
    ]..sort();
    final int index = ((values.length - 1) * percentile).round();
    return values[index] / 1000;
  }

  @override
  Widget build(BuildContext context) {
    final double buildP95 = _percentile(
      (FrameTiming timing) => timing.buildDuration,
      0.95,
    );
    final double rasterP95 = _percentile(
      (FrameTiming timing) => timing.rasterDuration,
      0.95,
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Evidence window',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('diagnostics-clear'),
                  tooltip: 'Clear diagnostics events',
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilterChip(
                  key: const Key('diagnostics-overlay-toggle'),
                  selected: overlayEnabled,
                  onSelected: onOverlayChanged,
                  avatar: const Icon(Icons.layers_outlined, size: 18),
                  label: const Text('Debug overlay'),
                ),
                FilterChip(
                  key: const Key('diagnostics-raw-toggle'),
                  selected: rawEventsEnabled,
                  onSelected: onRawEventsChanged,
                  avatar: const Icon(Icons.waves_outlined, size: 18),
                  label: const Text('Raw events'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Debug sample only · not release qualification',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              timings.isEmpty
                  ? 'FrameTiming: waiting for samples'
                  : '${timings.length} frames · build P95 ${buildP95.toStringAsFixed(2)} ms · raster P95 ${rasterP95.toStringAsFixed(2)} ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedBuilder(
                animation: diagnostics,
                builder: (BuildContext context, _) {
                  final List<ScrollDiagnosticEvent> events = diagnostics.events;
                  if (events.isEmpty) {
                    return const Center(
                      child: Text('Run a command or scroll either view.'),
                    );
                  }
                  return ListView.separated(
                    key: const Key('diagnostics-event-list'),
                    itemCount: events.length.clamp(0, 24),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final ScrollDiagnosticEvent event =
                          events[events.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '#${event.sequence} · ${event.source} · ${event.kind.name}',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              event.details.entries
                                  .take(3)
                                  .map(
                                    (MapEntry<String, Object?> entry) =>
                                        '${entry.key}: ${entry.value}',
                                  )
                                  .join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
