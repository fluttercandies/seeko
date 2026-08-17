import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class PageSyncPage extends StatefulWidget {
  const PageSyncPage({super.key});

  @override
  State<PageSyncPage> createState() => _PageSyncPageState();
}

class _PageSyncPageState extends State<PageSyncPage> {
  static const int _pageCount = 6;

  late final List<PageController> _pageControllers;
  late final List<SeekoPageControllerAdapter> _adapters;
  late SeekoPageSyncGroup _group;
  SeekoPageSyncMode _mode = SeekoPageSyncMode.progress;
  int _leaderIndex = 0;
  bool _joined = true;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _pageControllers = <PageController>[
      PageController(viewportFraction: 0.82),
      PageController(viewportFraction: 0.68),
    ];
    _adapters = <SeekoPageControllerAdapter>[
      for (var index = 0; index < 2; index++)
        SeekoPageControllerAdapter(
          pageController: _pageControllers[index],
          itemControllerForPage: (_) => null,
          pageCount: _pageCount,
        ),
    ];
    _group = SeekoPageSyncGroup(mode: _mode);
    _rebuildGroup();
  }

  void _rebuildGroup() {
    _group.dispose();
    _group = SeekoPageSyncGroup(mode: _mode);
    _group.add(
      _adapters[0],
      member: SeekoPageSyncMember(
        role: _leaderIndex == 0
            ? SeekoPageSyncRole.leader
            : SeekoPageSyncRole.follower,
        priority: _leaderIndex == 0 ? 10 : 0,
      ),
    );
    if (_joined) {
      _group.add(
        _adapters[1],
        member: SeekoPageSyncMember(
          role: _leaderIndex == 1
              ? SeekoPageSyncRole.leader
              : SeekoPageSyncRole.follower,
          priority: _leaderIndex == 1 ? 10 : 0,
        ),
      );
    }
  }

  void _setMode(SeekoPageSyncMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _rebuildGroup();
    setState(() => _status = 'Mode: ${mode.name}');
  }

  void _setLeader(int index) {
    if (_leaderIndex == index) return;
    if (index == 1 && !_joined) {
      _joined = true;
    }
    _leaderIndex = index;
    _rebuildGroup();
    setState(() => _status = 'Leader: view ${index + 1}');
  }

  void _toggleMember() {
    _joined = !_joined;
    _rebuildGroup();
    setState(() => _status = _joined ? 'View 2 rejoined' : 'View 2 detached');
  }

  Future<void> _seek(int index, {required bool animate}) async {
    final SeekoPageItemTarget target = SeekoPageItemTarget.page(index);
    final SeekoPageItemResult result = animate
        ? await _adapters[_leaderIndex].animateToTarget(target)
        : await _adapters[_leaderIndex].jumpToTarget(target);
    if (mounted) setState(() => _status = result.outcome.name);
  }

  @override
  void dispose() {
    _group.dispose();
    for (final SeekoPageControllerAdapter adapter in _adapters) {
      adapter.dispose();
    }
    for (final PageController controller in _pageControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('page-sync-page'),
      child: Column(
        children: <Widget>[
          ScenarioPageHeader(
            title: 'PageView Synchronization',
            description:
                'Two native PageViews share a page or normalized progress domain. '
                'The follower can leave and rejoin without disposing its controller.',
            actions: <Widget>[
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<SeekoPageSyncMode>(
                  // Flutter 3.32 compatibility; renamed to initialValue later.
                  // ignore: deprecated_member_use
                  value: _mode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Mapping'),
                  items: <DropdownMenuItem<SeekoPageSyncMode>>[
                    for (final SeekoPageSyncMode value
                        in SeekoPageSyncMode.values)
                      DropdownMenuItem<SeekoPageSyncMode>(
                        value: value,
                        child: Text(
                          value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (SeekoPageSyncMode? value) {
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
                key: const Key('page-sync-toggle-member'),
                tooltip: 'Detach or rejoin the second PageView',
                onPressed: _toggleMember,
                icon: Icon(
                  _joined ? Icons.link_off_rounded : Icons.link_rounded,
                ),
              ),
              IconButton.filledTonal(
                key: const Key('page-sync-jump'),
                tooltip: 'Jump leader to page 3',
                onPressed: () => unawaited(_seek(2, animate: false)),
                icon: const Icon(Icons.flash_on_outlined),
              ),
              IconButton.filledTonal(
                key: const Key('page-sync-animate'),
                tooltip: 'Animate leader to page 6',
                onPressed: () => unawaited(_seek(5, animate: true)),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
            status: ScenarioStatusBadge(
              label: '${_group.length} joined · $_status',
              widgetKey: const Key('page-sync-status'),
              tone: ScenarioStatusTone.active,
              icon: Icons.sync_alt,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool narrow = constraints.maxWidth < 900;
                final List<Widget> views = <Widget>[
                  _buildView(0, 'View 1', const Color(0xFF4C7DFF)),
                  if (_joined) _buildView(1, 'View 2', const Color(0xFF16C79A)),
                ];
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: narrow
                      ? Column(
                          children: <Widget>[
                            for (var index = 0; index < views.length; index++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index + 1 == views.length ? 0 : 12,
                                  ),
                                  child: views[index],
                                ),
                              ),
                          ],
                        )
                      : Row(
                          children: <Widget>[
                            for (var index = 0; index < views.length; index++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: index + 1 == views.length ? 0 : 12,
                                  ),
                                  child: views[index],
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

  Widget _buildView(int index, String title, Color accent) {
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
            ValueListenableBuilder<int?>(
              valueListenable: _adapters[index].currentPage,
              builder: (BuildContext context, int? page, _) {
                return ColoredBox(
                  color: accent.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(title)),
                        Text('Page ${(page ?? 0) + 1}'),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: PageView.builder(
                key: Key('page-sync-view-$index'),
                controller: _pageControllers[index],
                itemCount: _pageCount,
                itemBuilder: (BuildContext context, int page) {
                  return Center(
                    child: Semantics(
                      label: '$title page ${page + 1}',
                      child: Text(
                        '${page + 1}',
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
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
