import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class OpenTimelinePage extends StatefulWidget {
  const OpenTimelinePage({super.key});

  @override
  State<OpenTimelinePage> createState() => _OpenTimelinePageState();
}

class _OpenTimelinePageState extends State<OpenTimelinePage> {
  static const int _minimumIndex = -360;
  static const int _maximumIndex = 360;

  final SeekoController _scrollController = SeekoController(
    debugLabel: 'open-timeline',
  );
  late final SeekoOpenDataController<String> _data;
  late final SeekoOpenScrollAdapter<String> _adapter;
  ScrollResult? _lastResult;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _data = SeekoOpenDataController<String>(
      suggestedPageSize: 24,
      source: CallbackSeekoOpenDataSource<String>(_loadPage),
    )..addListener(_handleDataChanged);
    _adapter = SeekoOpenScrollAdapter<String>(
      controller: _scrollController,
      data: _data,
      maxPageLoads: 8,
    );
    unawaited(_loadInitialPage());
  }

  Future<SeekoOpenPage<String>> _loadPage(SeekoOpenLoadRequest request) async {
    final int count = request.suggestedCount;
    final int start;
    final int end;
    if (request.boundaryIndex == null) {
      start = -(count ~/ 2);
      end = start + count - 1;
    } else if (request.direction == SeekoOpenDirection.before) {
      end = request.boundaryIndex! - 1;
      start = (end - count + 1).clamp(_minimumIndex, _maximumIndex);
    } else {
      start = request.boundaryIndex! + 1;
      end = (start + count - 1).clamp(_minimumIndex, _maximumIndex);
    }
    if (start > end) {
      return SeekoOpenPage<String>(
        items: const <SeekoOpenItem<String>>[],
        hasMoreBefore: start > _minimumIndex,
        hasMoreAfter: end < _maximumIndex,
        revision: request.revision + 1,
      );
    }
    return SeekoOpenPage<String>(
      items: <SeekoOpenItem<String>>[
        for (var index = start; index <= end; index++)
          SeekoOpenItem<String>(
            logicalIndex: index,
            key: 'event-$index',
            extent: _extentFor(index),
          ),
      ],
      hasMoreBefore: start > _minimumIndex,
      hasMoreAfter: end < _maximumIndex,
      revision: request.revision + 1,
    );
  }

  static double _extentFor(int index) => 70 + (index.abs() % 4) * 10;

  Future<void> _loadInitialPage() async {
    await _data.load(SeekoOpenDirection.after);
    if (mounted) setState(() => _loading = false);
  }

  void _handleDataChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOlder() async {
    if (_loading || _data.loadedCount == 0) return;
    setState(() => _loading = true);
    final String anchorKey = _data.items.first.key;
    final SeekoOpenAnchor<String>? anchor = _data.captureAnchor(anchorKey);
    final SeekoOpenMutationResult<String> mutation = await _data.load(
      SeekoOpenDirection.before,
      preserve: anchor,
    );
    await SchedulerBinding.instance.endOfFrame;
    if (mutation.pixelCorrection != 0 && _scrollController.hasClients) {
      await _scrollController.jumpBy(mutation.pixelCorrection);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadNewerAndSeek() async {
    if (_loading || _data.loadedCount == 0) return;
    setState(() => _loading = true);
    await _data.load(SeekoOpenDirection.after);
    await SchedulerBinding.instance.endOfFrame;
    final int target = _data.lastLoadedIndex!;
    final ScrollResult result = await _adapter.animateToIndex(target);
    if (mounted) {
      setState(() {
        _lastResult = result;
        _loading = false;
      });
    }
  }

  Future<void> _jumpToOrigin() async {
    if (_loading ||
        _data.resolveIndex(0).status != SeekoOpenResolutionStatus.resolved) {
      return;
    }
    final ScrollResult result = await _adapter.jumpToKey('event-0');
    if (mounted) setState(() => _lastResult = result);
  }

  @override
  void dispose() {
    _data
      ..removeListener(_handleDataChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<SeekoOpenItem<String>> items = _data.items.toList(
      growable: false,
    );
    return KeyedSubtree(
      key: const Key('open-timeline-page'),
      child: Column(
        children: <Widget>[
          ScenarioPageHeader(
            title: 'Open Timeline',
            description:
                'Signed logical indices keep identity stable while history '
                'grows in either direction around the current origin.',
            actions: <Widget>[
              IconButton.filledTonal(
                key: const Key('open-timeline-load-before'),
                tooltip: 'Load older timeline entries',
                onPressed: _loading ? null : () => unawaited(_loadOlder()),
                icon: const Icon(Icons.history),
              ),
              IconButton.filledTonal(
                key: const Key('open-timeline-origin'),
                tooltip: 'Jump to timeline origin',
                onPressed: _loading ? null : () => unawaited(_jumpToOrigin()),
                icon: const Icon(Icons.today_outlined),
              ),
              IconButton.filledTonal(
                key: const Key('open-timeline-load-after'),
                tooltip: 'Load and animate to newer entries',
                onPressed: _loading
                    ? null
                    : () => unawaited(_loadNewerAndSeek()),
                icon: const Icon(Icons.update),
              ),
            ],
            status: ScenarioStatusBadge(
              label: _loading
                  ? 'loading'
                  : _lastResult?.outcome.name ?? 'Ready',
              widgetKey: const Key('open-timeline-result'),
              tone: _loading
                  ? ScenarioStatusTone.active
                  : scenarioToneForOutcome(_lastResult?.outcome.name),
              icon: _loading ? Icons.sync : Icons.timeline,
            ),
          ),
          const Divider(height: 1),
          ScenarioPaneHeader(
            title: items.isEmpty
                ? 'Preparing timeline'
                : 'Loaded ${_data.firstLoadedIndex}…${_data.lastLoadedIndex}',
            description:
                '${_data.loadedCount} stable entries · revision ${_data.revision} · '
                'finite progress intentionally unavailable',
            trailing: ScenarioStatusBadge(
              label: '${_data.loadedCount} rows',
              icon: Icons.data_array,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Scrollbar(
                    controller: _scrollController,
                    child: ListView.builder(
                      key: const Key('open-timeline-list'),
                      controller: _scrollController,
                      itemCount: items.length,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemBuilder: (BuildContext context, int position) {
                        return _TimelineEntry(item: items[position]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.item});

  final SeekoOpenItem<String> item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool origin = item.logicalIndex == 0;
    return Semantics(
      label: 'Timeline entry ${item.logicalIndex}',
      child: SizedBox(
        key: ValueKey<String>(item.key),
        height: item.extent,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 58,
              child: Text(
                item.logicalIndex == 0
                    ? 'NOW'
                    : item.logicalIndex.isNegative
                    ? '${item.logicalIndex}'
                    : '+${item.logicalIndex}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: origin ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ),
            Container(
              width: 2,
              color: origin ? colors.primary : colors.outlineVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: origin
                      ? colors.primaryContainer.withValues(alpha: 0.5)
                      : colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  origin
                      ? 'Stable origin · current event'
                      : 'Timeline event ${item.logicalIndex}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
