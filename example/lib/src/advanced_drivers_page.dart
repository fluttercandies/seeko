import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class AdvancedDriversPage extends StatelessWidget {
  const AdvancedDriversPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Column(
          children: <Widget>[
            const ScenarioPageHeader(
              title: 'Advanced drivers',
              description:
                  'Nested scroll, snap, focus-safe forms, prefetch hints, target loading, and semantic restoration in native Flutter surfaces.',
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: const TabBar(
                tabs: <Widget>[
                  Tab(icon: Icon(Icons.layers_outlined), text: 'Nested'),
                  Tab(icon: Icon(Icons.adjust_outlined), text: 'Snap + Focus'),
                  Tab(
                    icon: Icon(Icons.cloud_download_outlined),
                    text: 'Load + Restore',
                  ),
                  Tab(icon: Icon(Icons.swap_horiz_rounded), text: 'Adapter'),
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (BuildContext context) {
                  final TabController tabs = DefaultTabController.of(context);
                  return AnimatedBuilder(
                    animation: tabs,
                    builder: (BuildContext context, Widget? child) {
                      return switch (tabs.index) {
                        0 => const _NestedDriverDemo(),
                        1 => const _SnapFocusDemo(),
                        2 => const _LoaderRestoreDemo(),
                        _ => const _AdapterDemo(),
                      };
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

class _NestedDriverDemo extends StatefulWidget {
  const _NestedDriverDemo();

  @override
  State<_NestedDriverDemo> createState() => _NestedDriverDemoState();
}

class _NestedDriverDemoState extends State<_NestedDriverDemo> {
  final GlobalKey<NestedScrollViewState> _nestedKey =
      GlobalKey<NestedScrollViewState>();
  final PageStorageBucket _nestedPageStorage = PageStorageBucket();
  final SeekoController _controller = SeekoController(
    keepScrollOffset: false,
    debugLabel: 'advanced-nested-outer',
  );
  String _status = 'Ready';
  bool _nestedReady = false;
  bool _selectorFailure = false;
  int _nestedSetupAttempts = 0;

  @override
  void initState() {
    super.initState();
    _stabilizeNestedViewport();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _move(ScrollTarget target) async {
    if (!_nestedReady) {
      setState(() => _status = 'Preparing nested positions');
      return;
    }
    final ScrollResult result = await _controller.animateToTarget(
      target,
      placement: const ScrollPlacement.nearest(),
      motion: const ScrollMotion.adaptive(),
    );
    if (mounted) setState(() => _status = result.outcome.name);
  }

  void _stabilizeNestedViewport() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final NestedScrollViewState? nested = _nestedKey.currentState;
        if (nested == null ||
            !nested.outerController.hasClients ||
            nested.innerController.positions.isEmpty) {
          _nestedSetupAttempts += 1;
          if (_nestedSetupAttempts < 8) {
            _stabilizeNestedViewport();
          } else {
            setState(() => _status = 'Nested positions unavailable');
          }
          return;
        }
        final ScrollPosition outer = nested.outerController.position;
        for (final ScrollPosition inner in nested.innerController.positions) {
          if (inner.pixels != inner.minScrollExtent) {
            inner.jumpTo(inner.minScrollExtent);
          }
        }
        if (outer.pixels != outer.minScrollExtent) {
          outer.jumpTo(outer.minScrollExtent);
        }
        if (mounted) {
          setState(() {
            _nestedReady = true;
            _status = 'Ready';
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'One logical axis across a pinned header and the active inner list.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('nested-top'),
                onPressed: () => _move(ScrollTarget.edge(ScrollEdge.leading)),
                icon: const Icon(Icons.vertical_align_top),
                label: const Text('Top'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const Key('nested-bottom'),
                onPressed: () => _move(ScrollTarget.edge(ScrollEdge.trailing)),
                icon: const Icon(Icons.vertical_align_bottom),
                label: const Text('Bottom'),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Force nested inner selector failure',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Selector failure'),
                    Switch.adaptive(
                      key: const Key('nested-selector-failure'),
                      value: _selectorFailure,
                      onChanged: (bool value) {
                        setState(() {
                          _selectorFailure = value;
                          _status = value ? 'Selector rejected' : 'Ready';
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ScenarioStatusBadge(label: _status),
            ],
          ),
        ),
        Expanded(
          child: PageStorage(
            bucket: _nestedPageStorage,
            child: SeekoNestedScrollBinding(
              controller: _controller,
              nestedScrollViewKey: _nestedKey,
              innerPositionSelector: _selectorFailure
                  ? (List<ScrollPosition> _) => null
                  : (List<ScrollPosition> positions) {
                      return positions.length == 1 ? positions.single : null;
                    },
              child: NestedScrollView(
                key: _nestedKey,
                controller: _controller,
                headerSliverBuilder:
                    (BuildContext context, bool innerBoxIsScrolled) {
                      return <Widget>[
                        SliverAppBar(
                          pinned: true,
                          expandedHeight: 156,
                          automaticallyImplyLeading: false,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          flexibleSpace: const FlexibleSpaceBar(
                            title: Text('Nested workspace'),
                            background: _NestedHeaderArt(),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: const SizedBox(
                              height: 46,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.filter_list_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Filter header'),
                                    Spacer(),
                                    Text('outer → inner'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ];
                    },
                body: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                  itemCount: 36,
                  itemBuilder: (BuildContext context, int index) {
                    return SeekoTag(
                      controller: _controller,
                      targetKey: 'nested-$index',
                      index: index,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text('Inner section ${index + 1}'),
                          subtitle: const Text(
                            'The binding observes the selected inner ScrollPosition.',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NestedHeaderArt extends StatelessWidget {
  const _NestedHeaderArt();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        gradient: LinearGradient(
          colors: <Color>[
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.tertiary,
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.account_tree_rounded,
          size: 64,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _SnapFocusDemo extends StatefulWidget {
  const _SnapFocusDemo();

  @override
  State<_SnapFocusDemo> createState() => _SnapFocusDemoState();
}

class _SnapFocusDemoState extends State<_SnapFocusDemo> {
  late final SeekoController _snapController;
  late final SeekoController _formController;
  late final ScrollPrefetchObserver _prefetch;
  late final List<FocusNode> _focusNodes;
  String _snapStatus = 'Ready';
  String _formStatus = 'No reveal yet';

  @override
  void initState() {
    super.initState();
    _snapController = SeekoController(
      snapConfiguration: SeekoSnapConfiguration(
        resolver: const SeekoSnapResolver.nearestVisible(viewportAnchor: 0.12),
        placement: const ScrollPlacement.start(),
        motion: const ScrollMotion.spring(),
      ),
    );
    _formController = SeekoController();
    _prefetch = ScrollPrefetchObserver(
      _formController,
      configuration: ScrollPrefetchConfiguration(
        horizon: const Duration(milliseconds: 400),
        maxLookaheadViewports: 3,
      ),
    );
    _focusNodes = List<FocusNode>.generate(12, (_) => FocusNode());
  }

  @override
  void dispose() {
    _prefetch.dispose();
    for (final FocusNode node in _focusNodes) {
      node.dispose();
    }
    _snapController.dispose();
    _formController.dispose();
    super.dispose();
  }

  Future<void> _snap() async {
    try {
      final ScrollResult? result = await _snapController.snap();
      if (mounted) {
        setState(() => _snapStatus = result?.outcome.name ?? 'No target');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _snapStatus = error.toString());
    }
  }

  Future<void> _animateSnapFar() async {
    try {
      final ScrollResult result = await _snapController.animateToTarget(
        ScrollTarget.key('snap-13'),
        placement: const ScrollPlacement.center(),
        motion: const ScrollMotion.duration(
          duration: Duration(seconds: 3),
          curve: Curves.easeInOutCubic,
        ),
      );
      if (mounted) setState(() => _snapStatus = result.outcome.name);
    } on Object catch (error) {
      if (mounted) setState(() => _snapStatus = error.toString());
    }
  }

  void _stopSnap() {
    _snapController.stop(reason: ScrollStopReason.requested);
    if (mounted) setState(() => _snapStatus = 'stopped');
  }

  Future<void> _revealError() async {
    try {
      final ScrollResult? result = await _formController
          .ensureFirstFormErrorVisible(<SeekoFormFocusTarget>[
            for (var index = 0; index < _focusNodes.length; index += 1)
              SeekoFormFocusTarget(
                focusNode: _focusNodes[index],
                hasError: () => index == 8,
                fallbackTarget: index == 8
                    ? ScrollTarget.offset(index * 88.0)
                    : null,
              ),
          ], placement: const ScrollPlacement.nearest());
      if (mounted) {
        setState(() => _formStatus = result?.outcome.name ?? 'No errors');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _formStatus = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 900;
        final Widget snapPane = _buildSnapPane(context);
        final Widget formPane = _buildFormPane(context);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: narrow
              ? Column(
                  children: <Widget>[
                    snapPane,
                    const SizedBox(height: 16),
                    formPane,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: snapPane),
                    const SizedBox(width: 16),
                    Expanded(child: formPane),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSnapPane(BuildContext context) {
    return _DemoPanel(
      title: 'User-only snap',
      subtitle:
          'Drag the rail, release, then let the resolver settle to the nearest visible target.',
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  key: const Key('snap-now'),
                  onPressed: _snap,
                  icon: const Icon(Icons.adjust_rounded),
                  label: const Text('Snap now'),
                ),
                OutlinedButton.icon(
                  key: const Key('snap-animate-far'),
                  onPressed: _animateSnapFar,
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Animate far'),
                ),
                IconButton.filledTonal(
                  key: const Key('snap-stop'),
                  tooltip: 'Stop the active snap or animation',
                  onPressed: _stopSnap,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
                ScenarioStatusBadge(label: _snapStatus),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 330,
            child: ListView.builder(
              controller: _snapController,
              itemCount: 14,
              padding: const EdgeInsets.only(bottom: 12),
              itemBuilder: (BuildContext context, int index) {
                return SeekoTag(
                  controller: _snapController,
                  targetKey: 'snap-$index',
                  index: index,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        Icons.radio_button_checked,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      title: Text('Snap target ${index + 1}'),
                      subtitle: const Text('Stable key + mounted visibility'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPane(BuildContext context) {
    return _DemoPanel(
      title: 'Focus, form, and prefetch',
      subtitle:
          'Reveal the first invalid field while exposing bounded look-ahead hints.',
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  key: const Key('reveal-first-error'),
                  onPressed: _revealError,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Reveal first error'),
                ),
                ScenarioStatusBadge(label: _formStatus),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<ScrollPrefetchHint?>(
            valueListenable: _prefetch,
            builder: (BuildContext context, ScrollPrefetchHint? hint, _) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  hint == null
                      ? 'Prefetch: waiting for motion'
                      : 'Prefetch: ${hint.direction.name} · ${hint.logicalVelocity.toStringAsFixed(0)} px/s · next ${hint.projectedLogicalPixels.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 330,
            child: ListView.builder(
              controller: _formController,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _focusNodes.length,
              itemBuilder: (BuildContext context, int index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: TextFormField(
                    focusNode: _focusNodes[index],
                    decoration: InputDecoration(
                      labelText: 'Field ${index + 1}',
                      helperText: index == 8
                          ? 'This field is invalid'
                          : 'Optional',
                      errorText: index == 8 ? 'Please review this value' : null,
                      prefixIcon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoPanel extends StatelessWidget {
  const _DemoPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdapterDemo extends StatefulWidget {
  const _AdapterDemo();

  @override
  State<_AdapterDemo> createState() => _AdapterDemoState();
}

class _AdapterDemoState extends State<_AdapterDemo> {
  final ScrollController _existingController = ScrollController(
    debugLabel: 'advanced-existing-controller',
  );
  final SeekoPositionBinding _binding = SeekoPositionBinding();
  late final SeekoController _adapter = SeekoController.adapt(
    _existingController,
    binding: _binding,
    exclusiveProgrammaticWrites: false,
  );
  String _status = 'Waiting for the existing position';

  @override
  void initState() {
    super.initState();
    _scheduleRebind();
  }

  @override
  void dispose() {
    _adapter.dispose();
    _binding.dispose();
    _existingController.dispose();
    super.dispose();
  }

  void _scheduleRebind() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_existingController.hasClients) {
        if (mounted) {
          setState(() => _status = 'Position is detached; rebind after attach');
        }
        return;
      }
      _binding.rebind(_existingController.position);
      if (mounted) setState(() => _status = 'Bound with degraded capability');
    });
  }

  void _unbindPosition() {
    _binding.unbind();
    if (mounted) setState(() => _status = 'Unbound; commands are degraded');
  }

  Future<void> _move(ScrollTarget target, {required bool animate}) async {
    try {
      final ScrollResult result = animate
          ? await _adapter.animateToTarget(
              target,
              placement: const ScrollPlacement.center(),
              motion: const ScrollMotion.adaptive(),
            )
          : await _adapter.jumpToTarget(
              target,
              placement: const ScrollPlacement.center(),
            );
      if (mounted) setState(() => _status = result.outcome.name);
    } on Object catch (error) {
      if (mounted) setState(() => _status = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScrollCapabilities capabilities = _adapter.capabilities;
    final List<String> capabilityLabels = <String>[
      if (capabilities.supports(ScrollCapability.pixel)) 'pixel',
      if (capabilities.supports(ScrollCapability.mountedTarget)) 'mounted',
      if (capabilities.supports(ScrollCapability.singleWriter)) 'single-writer',
      if (capabilities.supports(ScrollCapability.programmaticResult))
        'programmatic-result',
      if (!capabilities.supports(ScrollCapability.strictSync))
        'strict-sync: off',
    ];
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Keep an existing native ScrollController and explicitly rebind its active position.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('adapter-rebind'),
                onPressed: _scheduleRebind,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Rebind'),
              ),
              IconButton.filledTonal(
                key: const Key('adapter-unbind'),
                tooltip: 'Unbind the selected existing position',
                onPressed: _unbindPosition,
                icon: const Icon(Icons.link_off_rounded),
              ),
              const SizedBox(width: 10),
              ScenarioStatusBadge(label: _status),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Capabilities: ${capabilityLabels.join(' · ')}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                key: const Key('adapter-jump'),
                onPressed: () => _move(ScrollTarget.index(28), animate: false),
                icon: const Icon(Icons.flash_on_outlined),
                label: const Text('Jump to 28'),
              ),
              FilledButton.icon(
                key: const Key('adapter-animate'),
                onPressed: () => _move(ScrollTarget.index(46), animate: true),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Animate to 46'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('adapter-scroll-view'),
            controller: _existingController,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
            itemCount: 64,
            itemBuilder: (BuildContext context, int index) {
              return SeekoTag(
                controller: _adapter,
                targetKey: 'adapter-$index',
                index: index,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text('Existing item $index'),
                    subtitle: const Text('Native ListView owns the controller'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LoaderRestoreDemo extends StatefulWidget {
  const _LoaderRestoreDemo();

  @override
  State<_LoaderRestoreDemo> createState() => _LoaderRestoreDemoState();
}

class _LoaderRestoreDemoState extends State<_LoaderRestoreDemo> {
  static const int _itemCount = 300;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  late final _PagedIndexDelegate _delegate;
  late final SeekoController _controller;
  final TextEditingController _targetController = TextEditingController(
    text: '240',
  );
  String _status = 'Only the first page is loaded';
  String _restorationStatus = 'Codec idle';

  @override
  void initState() {
    super.initState();
    _delegate = _PagedIndexDelegate(itemCount: _itemCount, revision: _revision);
    _controller = SeekoController(
      indexDelegate: _delegate,
      targetLoader: CallbackScrollTargetLoader(_loadTarget),
      targetLoadPolicy: ScrollTargetLoadPolicy(
        maxAttempts: 2,
        initialRetryDelay: const Duration(milliseconds: 40),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _revision.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<ScrollTargetLoadResult> _loadTarget(
    ScrollTargetLoadRequest request,
  ) async {
    final int? index = switch (request.target) {
      IndexScrollTarget(:final int index) => index,
      KeyScrollTarget(:final Object key) when key is String => int.tryParse(
        key.toString().replaceFirst('item-', ''),
      ),
      _ => null,
    };
    if (index == null || index < 0 || index >= _itemCount) {
      return ScrollTargetLoadResult.notFound(
        outcome: ScrollOutcome.targetOutOfRange,
      );
    }
    if (!mounted) {
      return ScrollTargetLoadResult.rejected(diagnostic: 'disposed');
    }
    setState(() => _status = 'Loading page for item $index…');
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _delegate.loadAround(index);
    if (mounted) setState(() => _status = 'Loaded page around item $index');
    return ScrollTargetLoadResult.loaded(revision: _delegate.revision);
  }

  Future<void> _jumpToTarget({required bool animate}) async {
    final int? index = int.tryParse(_targetController.text.trim());
    if (index == null) {
      setState(() => _status = 'Enter a numeric item index');
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
    if (mounted) setState(() => _status = result.outcome.name);
  }

  Future<void> _saveAnchor(BuildContext context) async {
    final bool saved = _controller.saveRestorationToPageStorage(
      context,
      storageKey: 'seeko-advanced-loader',
      driverKind: 'indexed',
    );
    if (mounted) {
      setState(
        () => _status = saved ? 'Anchor saved' : 'No visible anchor to save',
      );
    }
  }

  Future<void> _restoreAnchor(BuildContext context) async {
    final ScrollResult? result = await _controller
        .restoreRestorationFromPageStorage(
          context,
          storageKey: 'seeko-advanced-loader',
        );
    if (mounted) {
      setState(() => _status = result?.outcome.name ?? 'No saved anchor');
    }
  }

  Future<void> _exerciseRestorationCodec() async {
    final _StringItemCodec codec = _StringItemCodec();
    final SeekoRestorationAnchor<String> anchor =
        SeekoRestorationAnchor<String>(
          driverKind: 'indexed',
          key: 'item-20',
          lastKnownIndex: 20,
          itemAnchor: 0,
          viewportAnchor: 0.25,
          logicalOffset: 8,
          dataRevisionHint: _delegate.revision,
          fallbackProgress: 0.25,
        );
    final RestorableSeekoAnchor<String> restorable =
        RestorableSeekoAnchor<String>(codec: codec);
    final Map<String, Object?> payload = anchor.encode(codec);
    final SeekoRestorationAnchor<String>? decoded = restorable.fromPrimitives(
      payload,
    );
    if (decoded == null) {
      if (mounted) {
        setState(() => _restorationStatus = 'Codec rejected valid payload');
      }
      return;
    }
    final Object invalidPayload = <String, Object?>{
      ...payload,
      'codecNamespace': 'example.invalid',
    };
    final SeekoRestorationAnchor<String>? invalid = restorable.fromPrimitives(
      invalidPayload,
    );
    final String decodeLabel =
        invalid == null && restorable.decodeFailure != null
        ? 'decode fallback captured'
        : 'decode failure missing';
    final SeekoRestorationFallbackState fallback =
        SeekoRestorationFallbackState(
          driverKind: 'indexed',
          itemAnchor: 0,
          viewportAnchor: 0.25,
          logicalOffset: 0,
          fallbackProgress: 0.25,
          cause: const SeekoRestorationFormatException(
            'example schema mismatch',
          ),
        );
    final ScrollResult result = await _controller
        .restoreRestorationFallback<Object>(
          fallback,
          policy: SeekoRestorationPolicy<Object>(
            steps: const <SeekoRestorationFallbackStep>[
              SeekoRestorationFallbackStep.progress,
              SeekoRestorationFallbackStep.leadingEdge,
              SeekoRestorationFallbackStep.fail,
            ],
          ),
        );
    if (mounted) {
      setState(() {
        _restorationStatus = '$decodeLabel · ${result.outcome.name}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 106,
                child: TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Item',
                    isDense: true,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const Key('loader-jump'),
                onPressed: () => _jumpToTarget(animate: false),
                icon: const Icon(Icons.flash_on_outlined),
                label: const Text('Jump'),
              ),
              FilledButton.icon(
                key: const Key('loader-animate'),
                onPressed: () => _jumpToTarget(animate: true),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Animate'),
              ),
              OutlinedButton.icon(
                key: const Key('loader-save-anchor'),
                onPressed: () => _saveAnchor(context),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save anchor'),
              ),
              OutlinedButton.icon(
                key: const Key('loader-restore-anchor'),
                onPressed: () => _restoreAnchor(context),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Restore'),
              ),
              OutlinedButton.icon(
                key: const Key('loader-restoration-codec'),
                onPressed: _exerciseRestorationCodec,
                icon: const Icon(Icons.schema_outlined),
                label: const Text('Codec + fallback'),
              ),
              ScenarioStatusBadge(label: _status),
              Text(
                _restorationStatus,
                key: const Key('loader-restoration-status'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            key: const Key('loader-scroll-view'),
            controller: _controller,
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                sliver: SeekoIndexedSliver(
                  controller: _controller,
                  indexDelegate: _delegate,
                  estimatedExtent: 74,
                  delegate: SliverChildBuilderDelegate((
                    BuildContext context,
                    int index,
                  ) {
                    return SeekoTag(
                      controller: _controller,
                      targetKey: 'item-$index',
                      index: index,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text('Paged item $index'),
                          subtitle: Text(
                            _delegate.loadedRanges.contains(index)
                                ? 'Loaded · stable key item-$index'
                                : 'Virtual target · loader will fetch its page',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
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
  }
}

final class _StringItemCodec implements SeekoKeyCodec<String> {
  @override
  String get namespace => 'example.item';

  @override
  int get schemaVersion => 1;

  @override
  Object? encode(String key) => key;

  @override
  String decode(Object? value) {
    if (value is! String || !value.startsWith('item-')) {
      throw const FormatException('Expected an item-* string key.');
    }
    return value;
  }
}

final class _PagedIndexDelegate implements SeekoIndexDelegate<Object> {
  _PagedIndexDelegate({
    required this.itemCount,
    required ValueNotifier<int> revision,
  }) : _revisionNotifier = revision,
       _loadedRanges = LoadedRangeSet(<IndexRange>[const IndexRange(0, 30)]);

  @override
  final int itemCount;
  final ValueNotifier<int> _revisionNotifier;
  LoadedRangeSet _loadedRanges;

  @override
  LoadedRangeSet get loadedRanges => _loadedRanges;

  @override
  Listenable get changes => _revisionNotifier;

  @override
  int get revision => _revisionNotifier.value;

  @override
  Object keyAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', itemCount);
    return 'item-$index';
  }

  @override
  SeekoKeyLookup<Object> lookupKey(Object key) {
    if (key is! String || !key.startsWith('item-')) {
      return const SeekoKeyLookup<Object>.absent();
    }
    final int? index = int.tryParse(key.substring(5));
    if (index == null || index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<Object>.absent();
    }
    if (!_loadedRanges.contains(index)) {
      return const SeekoKeyLookup<Object>.notLoaded();
    }
    return SeekoKeyLookup<Object>.found(index, key: key);
  }

  @override
  SeekoKeyLookup<Object> captureIndex(int index) {
    if (index < 0 || index >= itemCount) {
      return const SeekoKeyLookup<Object>.absent();
    }
    return _loadedRanges.contains(index)
        ? SeekoKeyLookup<Object>.found(index, key: keyAt(index))
        : const SeekoKeyLookup<Object>.notLoaded();
  }

  void loadAround(int index) {
    final int start = (index - 15).clamp(0, itemCount).toInt();
    final int end = (index + 16).clamp(0, itemCount).toInt();
    _loadedRanges = LoadedRangeSet(<IndexRange>[
      ..._loadedRanges.ranges,
      IndexRange(start, end),
    ]);
    _revisionNotifier.value += 1;
  }
}
