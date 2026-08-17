import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

enum _PlacementChoice { nearest, start, center, end, visible, exact }

enum _DeadlineChoice { oneSecond, threeSeconds, tenSeconds }

class TargetNavigationPage extends StatefulWidget {
  const TargetNavigationPage({super.key});

  @override
  State<TargetNavigationPage> createState() => _TargetNavigationPageState();
}

class _TargetNavigationPageState extends State<TargetNavigationPage> {
  static const int _itemCount = 48;
  static const double _itemExtent = 88;
  static const int _featuredIndex = 31;

  late final SeekoController _controller;
  final TextEditingController _pixelTarget = TextEditingController(text: '640');
  final TextEditingController _itemTarget = TextEditingController(text: '3');
  final GlobalKey _mountedTargetKey = GlobalKey();
  ScrollResult? _lastResult;
  String? _inputError;
  _PlacementChoice _placement = _PlacementChoice.center;
  bool _reverse = false;
  bool _rtl = false;
  bool _commandActive = false;
  int? _selectedItem;
  ScrollConflictPolicy _conflictPolicy = ScrollConflictPolicy.replace;
  ScrollBoundaryPolicy _boundaryPolicy = ScrollBoundaryPolicy.clampNumeric;
  _DeadlineChoice _deadline = _DeadlineChoice.threeSeconds;
  bool _requireExact = false;
  bool _lockUserInteraction = false;
  bool _controlsOpen = false;
  ScrollCancellationSource? _activeCancellation;

  @override
  void initState() {
    super.initState();
    _controller = SeekoController(customTargetResolver: _resolveCustomTarget);
  }

  ScrollCustomTargetResolution _resolveCustomTarget(CustomScrollTarget target) {
    if (target.value != 'featured-target') {
      return const ScrollCustomTargetResolution.unsupported();
    }
    return const ScrollCustomTargetResolution.resolved(
      targetInterval: LogicalInterval(
        _featuredIndex * _itemExtent,
        (_featuredIndex + 1) * _itemExtent,
      ),
      dataRevision: 0,
    );
  }

  @override
  void dispose() {
    _activeCancellation?.cancel(ScrollStopReason.disposed);
    _pixelTarget.dispose();
    _itemTarget.dispose();
    _controller.dispose();
    super.dispose();
  }

  ScrollPlacement get _selectedPlacement => switch (_placement) {
    _PlacementChoice.nearest => const ScrollPlacement.nearest(),
    _PlacementChoice.start => const ScrollPlacement.start(),
    _PlacementChoice.center => const ScrollPlacement.center(),
    _PlacementChoice.end => const ScrollPlacement.end(),
    _PlacementChoice.visible => const ScrollPlacement.visible(),
    _PlacementChoice.exact => ScrollPlacement.exact(
      targetAnchor: 0.5,
      viewportAnchor: 0.25,
      offset: 12,
    ),
  };

  Duration get _selectedDeadline => switch (_deadline) {
    _DeadlineChoice.oneSecond => const Duration(seconds: 1),
    _DeadlineChoice.threeSeconds => const Duration(seconds: 3),
    _DeadlineChoice.tenSeconds => const Duration(seconds: 10),
  };

  ScrollCommandOptions get _selectedOptions => ScrollCommandOptions(
    conflictPolicy: _conflictPolicy,
    boundaryPolicy: _boundaryPolicy,
    resolutionPolicy: ScrollResolutionPolicy(requireExact: _requireExact),
    executionPolicy: ScrollExecutionPolicy(deadline: _selectedDeadline),
    cancellationToken: _activeCancellation?.token,
    lockUserInteraction: _lockUserInteraction,
  );

  Future<void> _runPixel({required bool animated}) async {
    final double? pixels = double.tryParse(_pixelTarget.text.trim());
    if (pixels == null || !pixels.isFinite) {
      setState(() => _inputError = 'Enter a finite pixel offset.');
      return;
    }
    await _runCommand(
      () => animated
          ? _controller.animateToTarget(
              ScrollTarget.offset(pixels),
              options: _selectedOptions,
            )
          : _controller.jumpToTarget(
              ScrollTarget.offset(pixels),
              options: _selectedOptions,
            ),
    );
  }

  Future<void> _runItem({required bool animated}) async {
    final int? index = int.tryParse(_itemTarget.text.trim());
    if (index == null || index < 0 || index >= _itemCount) {
      setState(
        () => _inputError = 'Enter an item index from 0 to ${_itemCount - 1}.',
      );
      return;
    }
    setState(() => _selectedItem = index);
    final ScrollTarget target = ScrollTarget.key('item-$index');
    await _runCommand(
      () => animated
          ? _controller.animateToTarget(
              target,
              placement: _selectedPlacement,
              options: _selectedOptions,
            )
          : _controller.jumpToTarget(
              target,
              placement: _selectedPlacement,
              options: _selectedOptions,
            ),
    );
  }

  Future<void> _runCustomTarget() async {
    setState(() => _selectedItem = _featuredIndex);
    await _runCommand(
      () => _controller.animateToTarget(
        const ScrollTarget.custom('featured-target'),
        placement: const ScrollPlacement.visible(),
        options: _selectedOptions,
      ),
    );
  }

  Future<void> _runMountedContext() async {
    final BuildContext? targetContext = _mountedTargetKey.currentContext;
    if (targetContext == null) {
      setState(() {
        _inputError = 'Mounted target 3 is outside the current widget tree.';
      });
      return;
    }
    setState(() => _selectedItem = 3);
    await _runCommand(
      () => _controller.animateToTarget(
        ScrollTarget.mounted(targetContext),
        placement: _selectedPlacement,
        options: _selectedOptions,
      ),
    );
  }

  Future<void> _runProgressTarget() async {
    await _runCommand(
      () => _controller.animateToTarget(
        ScrollTarget.progress(0.5),
        options: _selectedOptions,
      ),
    );
  }

  Future<void> _runCommand(Future<ScrollResult> Function() command) async {
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    _activeCancellation = cancellation;
    setState(() {
      _commandActive = true;
      _inputError = null;
    });
    try {
      final ScrollResult result = await command();
      if (!mounted) {
        return;
      }
      setState(() => _lastResult = result);
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _inputError = error.message?.toString() ?? '$error');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _inputError = error.toString());
      }
    } finally {
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      cancellation.dispose();
      if (mounted) {
        setState(() => _commandActive = false);
      }
    }
  }

  Future<void> _reset() async {
    _activeCancellation?.cancel(ScrollStopReason.superseded);
    _controller.stop();
    if (_controller.isAttached) {
      await _controller.jumpToTarget(
        const ScrollTarget.edge(ScrollEdge.leading),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _lastResult = null;
      _inputError = null;
      _selectedItem = null;
      _placement = _PlacementChoice.center;
      _reverse = false;
      _rtl = false;
      _conflictPolicy = ScrollConflictPolicy.replace;
      _boundaryPolicy = ScrollBoundaryPolicy.clampNumeric;
      _deadline = _DeadlineChoice.threeSeconds;
      _requireExact = false;
      _lockUserInteraction = false;
      _pixelTarget.text = '640';
      _itemTarget.text = '3';
    });
  }

  void _toggleControls() {
    setState(() => _controlsOpen = !_controlsOpen);
  }

  Widget _buildCommandRail({
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    VoidCallback refreshAfter(Future<void> Function() command) {
      return () async {
        await command();
      };
    }

    return _CommandRail(
      padding: padding,
      pixelTarget: _pixelTarget,
      itemTarget: _itemTarget,
      placement: _placement,
      inputError: _inputError,
      reverse: _reverse,
      rtl: _rtl,
      commandActive: _commandActive,
      conflictPolicy: _conflictPolicy,
      boundaryPolicy: _boundaryPolicy,
      deadline: _deadline,
      requireExact: _requireExact,
      lockUserInteraction: _lockUserInteraction,
      onPlacementChanged: (_PlacementChoice value) {
        setState(() => _placement = value);
      },
      onReverseChanged: (bool value) {
        setState(() => _reverse = value);
      },
      onRtlChanged: (bool value) {
        setState(() => _rtl = value);
      },
      onConflictPolicyChanged: (ScrollConflictPolicy value) {
        setState(() => _conflictPolicy = value);
      },
      onBoundaryPolicyChanged: (ScrollBoundaryPolicy value) {
        setState(() => _boundaryPolicy = value);
      },
      onDeadlineChanged: (_DeadlineChoice value) {
        setState(() => _deadline = value);
      },
      onRequireExactChanged: (bool value) {
        setState(() => _requireExact = value);
      },
      onLockUserInteractionChanged: (bool value) {
        setState(() => _lockUserInteraction = value);
      },
      onJumpPixels: refreshAfter(() => _runPixel(animated: false)),
      onAnimatePixels: refreshAfter(() => _runPixel(animated: true)),
      onJumpItem: refreshAfter(() => _runItem(animated: false)),
      onAnimateItem: refreshAfter(() => _runItem(animated: true)),
      onCustomTarget: refreshAfter(_runCustomTarget),
      onMountedTarget: refreshAfter(_runMountedContext),
      onProgressTarget: refreshAfter(_runProgressTarget),
      onCancelToken: () {
        _activeCancellation?.cancel();
      },
      onStop: () {
        _controller.stop();
      },
      onReset: refreshAfter(_reset),
    );
  }

  Widget _buildCompactControls() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: <Widget>[
          ScenarioPaneHeader(
            title: 'Target controls',
            description: 'Pixel, semantic target, and command policy inputs.',
            trailing: IconButton(
              key: const Key('close-scenario-controls'),
              tooltip: 'Hide controls',
              onPressed: _toggleControls,
              icon: const Icon(Icons.close),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildCommandRail(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 1120;
        final bool narrow = constraints.maxWidth < 720;
        return Column(
          children: <Widget>[
            _ScenarioHeader(
              compact: compact,
              controlsOpen: _controlsOpen,
              onToggleControls: _toggleControls,
            ),
            const Divider(height: 1),
            Expanded(
              child: compact
                  ? Column(
                      children: <Widget>[
                        Expanded(
                          child: narrow
                              ? IndexedStack(
                                  index: _controlsOpen ? 1 : 0,
                                  children: <Widget>[
                                    _buildWorkspace(compact: true),
                                    _buildCompactControls(),
                                  ],
                                )
                              : Row(
                                  children: <Widget>[
                                    SizedBox(
                                      width: _controlsOpen
                                          ? constraints.maxWidth < 860
                                                ? 320
                                                : 360
                                          : 0,
                                      child: _controlsOpen
                                          ? _buildCompactControls()
                                          : null,
                                    ),
                                    VerticalDivider(
                                      width: _controlsOpen ? 1 : 0,
                                    ),
                                    Expanded(
                                      child: _buildWorkspace(compact: true),
                                    ),
                                  ],
                                ),
                        ),
                        const Divider(height: 1),
                        SizedBox(
                          height: 112,
                          child: _buildStatusRail(compact: true),
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        SizedBox(width: 304, child: _buildCommandRail()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildWorkspace(compact: false)),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 304,
                          child: _buildStatusRail(compact: false),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWorkspace({required bool compact}) {
    return _ScrollWorkspace(
      controller: _controller,
      reverse: _reverse,
      rtl: _rtl,
      selectedItem: _selectedItem,
      itemCount: _itemCount,
      mountedTargetKey: _mountedTargetKey,
      compact: compact,
    );
  }

  Widget _buildStatusRail({required bool compact}) {
    return ValueListenableBuilder<ScrollSnapshot>(
      valueListenable: _controller.state,
      builder: (_, ScrollSnapshot snapshot, _) => _StatusRail(
        snapshot: snapshot,
        result: _lastResult,
        compact: compact,
      ),
    );
  }
}

class _ScenarioHeader extends StatelessWidget {
  const _ScenarioHeader({
    required this.compact,
    required this.controlsOpen,
    required this.onToggleControls,
  });

  final bool compact;
  final bool controlsOpen;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context) {
    return ScenarioPageHeader(
      title: 'Target Navigation',
      description:
          'Drive a native ListView by logical pixels or mounted semantic keys.',
      actions: <Widget>[
        if (compact)
          FilledButton.tonalIcon(
            key: const Key('open-scenario-controls'),
            onPressed: onToggleControls,
            icon: Icon(controlsOpen ? Icons.close : Icons.tune),
            label: Text(controlsOpen ? 'Hide controls' : 'Controls'),
          ),
      ],
      status: const ScenarioStatusBadge(
        label: 'L1 + L2',
        icon: Icons.layers_outlined,
        tone: ScenarioStatusTone.neutral,
      ),
    );
  }
}

class _CommandRail extends StatelessWidget {
  const _CommandRail({
    required this.padding,
    required this.pixelTarget,
    required this.itemTarget,
    required this.placement,
    required this.inputError,
    required this.reverse,
    required this.rtl,
    required this.commandActive,
    required this.conflictPolicy,
    required this.boundaryPolicy,
    required this.deadline,
    required this.requireExact,
    required this.lockUserInteraction,
    required this.onPlacementChanged,
    required this.onReverseChanged,
    required this.onRtlChanged,
    required this.onConflictPolicyChanged,
    required this.onBoundaryPolicyChanged,
    required this.onDeadlineChanged,
    required this.onRequireExactChanged,
    required this.onLockUserInteractionChanged,
    required this.onJumpPixels,
    required this.onAnimatePixels,
    required this.onJumpItem,
    required this.onAnimateItem,
    required this.onCustomTarget,
    required this.onMountedTarget,
    required this.onProgressTarget,
    required this.onCancelToken,
    required this.onStop,
    required this.onReset,
  });

  final EdgeInsetsGeometry padding;
  final TextEditingController pixelTarget;
  final TextEditingController itemTarget;
  final _PlacementChoice placement;
  final String? inputError;
  final bool reverse;
  final bool rtl;
  final bool commandActive;
  final ScrollConflictPolicy conflictPolicy;
  final ScrollBoundaryPolicy boundaryPolicy;
  final _DeadlineChoice deadline;
  final bool requireExact;
  final bool lockUserInteraction;
  final ValueChanged<_PlacementChoice> onPlacementChanged;
  final ValueChanged<bool> onReverseChanged;
  final ValueChanged<bool> onRtlChanged;
  final ValueChanged<ScrollConflictPolicy> onConflictPolicyChanged;
  final ValueChanged<ScrollBoundaryPolicy> onBoundaryPolicyChanged;
  final ValueChanged<_DeadlineChoice> onDeadlineChanged;
  final ValueChanged<bool> onRequireExactChanged;
  final ValueChanged<bool> onLockUserInteractionChanged;
  final VoidCallback onJumpPixels;
  final VoidCallback onAnimatePixels;
  final VoidCallback onJumpItem;
  final VoidCallback onAnimateItem;
  final VoidCallback onCustomTarget;
  final VoidCallback onMountedTarget;
  final VoidCallback onProgressTarget;
  final VoidCallback onCancelToken;
  final VoidCallback onStop;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('command-rail'),
      padding: padding,
      children: <Widget>[
        const _RailHeading(
          title: 'L1 pixel target',
          description:
              'Only the controller changes. The ListView stays native.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('pixel-target-field'),
          controller: pixelTarget,
          decoration: const InputDecoration(
            labelText: 'Logical pixel offset',
            suffixText: 'px',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
          ],
        ),
        const SizedBox(height: 10),
        _CommandButtons(
          jumpKey: const Key('jump-pixels-button'),
          animateKey: const Key('animate-pixels-button'),
          jumpTooltip: 'Jump to pixel offset',
          animateTooltip: 'Animate to pixel offset',
          onJump: onJumpPixels,
          onAnimate: onAnimatePixels,
        ),
        const Divider(height: 36),
        const _RailHeading(
          title: 'L2 mounted target',
          description:
              'A SeekoTag adds an exact key while the item is mounted.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('item-target-field'),
          controller: itemTarget,
          decoration: const InputDecoration(labelText: 'Item index (0–47)'),
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<_PlacementChoice>(
          // Flutter 3.32 compatibility; renamed to initialValue later.
          // ignore: deprecated_member_use
          value: placement,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Placement'),
          items: <DropdownMenuItem<_PlacementChoice>>[
            for (final _PlacementChoice value in _PlacementChoice.values)
              DropdownMenuItem<_PlacementChoice>(
                value: value,
                child: Text(value.name),
              ),
          ],
          onChanged: (_PlacementChoice? value) {
            if (value != null) onPlacementChanged(value);
          },
        ),
        const SizedBox(height: 10),
        _CommandButtons(
          jumpKey: const Key('jump-item-button'),
          animateKey: const Key('animate-item-button'),
          jumpTooltip: 'Jump to mounted item',
          animateTooltip: 'Animate to mounted item',
          onJump: onJumpItem,
          onAnimate: onAnimateItem,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('animate-custom-target-button'),
          onPressed: onCustomTarget,
          icon: const Icon(Icons.extension_outlined),
          label: const Text('Animate custom “featured” target'),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('animate-mounted-context-button'),
                onPressed: onMountedTarget,
                child: const Text('Mounted context'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('animate-progress-target-button'),
                onPressed: onProgressTarget,
                child: const Text('50% progress'),
              ),
            ),
          ],
        ),
        if (inputError != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            inputError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const Divider(height: 36),
        const _RailHeading(
          title: 'Command policies',
          description:
              'The same typed pipeline controls conflicts, boundaries, exactness, deadlines, cancellation, and gesture ownership.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ScrollConflictPolicy>(
          // Flutter 3.32 compatibility; renamed to initialValue later.
          // ignore: deprecated_member_use
          value: conflictPolicy,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Conflict policy'),
          items: <DropdownMenuItem<ScrollConflictPolicy>>[
            for (final ScrollConflictPolicy value
                in ScrollConflictPolicy.values)
              DropdownMenuItem<ScrollConflictPolicy>(
                value: value,
                child: Text(value.name),
              ),
          ],
          onChanged: (ScrollConflictPolicy? value) {
            if (value != null) onConflictPolicyChanged(value);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<ScrollBoundaryPolicy>(
          // Flutter 3.32 compatibility; renamed to initialValue later.
          // ignore: deprecated_member_use
          value: boundaryPolicy,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Boundary policy'),
          items: <DropdownMenuItem<ScrollBoundaryPolicy>>[
            for (final ScrollBoundaryPolicy value
                in ScrollBoundaryPolicy.values)
              DropdownMenuItem<ScrollBoundaryPolicy>(
                value: value,
                child: Text(value.name),
              ),
          ],
          onChanged: (ScrollBoundaryPolicy? value) {
            if (value != null) onBoundaryPolicyChanged(value);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<_DeadlineChoice>(
          // Flutter 3.32 compatibility; renamed to initialValue later.
          // ignore: deprecated_member_use
          value: deadline,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Deadline'),
          items: <DropdownMenuItem<_DeadlineChoice>>[
            for (final _DeadlineChoice value in _DeadlineChoice.values)
              DropdownMenuItem<_DeadlineChoice>(
                value: value,
                child: Text(value.name),
              ),
          ],
          onChanged: (_DeadlineChoice? value) {
            if (value != null) onDeadlineChanged(value);
          },
        ),
        SwitchListTile.adaptive(
          key: const Key('require-exact-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Require exact resolution'),
          value: requireExact,
          onChanged: onRequireExactChanged,
        ),
        SwitchListTile.adaptive(
          key: const Key('lock-user-interaction-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Lock user interaction'),
          subtitle: const Text('Off by default; user gestures normally win'),
          value: lockUserInteraction,
          onChanged: onLockUserInteractionChanged,
        ),
        const Divider(height: 36),
        SwitchListTile.adaptive(
          key: const Key('reverse-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Reverse'),
          subtitle: const Text('Keep logical leading/trailing semantics'),
          value: reverse,
          onChanged: onReverseChanged,
        ),
        SwitchListTile.adaptive(
          key: const Key('rtl-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('RTL'),
          subtitle: const Text('Exercise direction-aware geometry'),
          value: rtl,
          onChanged: onRtlChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onStop,
                icon: commandActive
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop command'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('reset-scenario-button'),
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            key: const Key('cancel-command-token-button'),
            onPressed: commandActive ? onCancelToken : null,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel through token'),
          ),
        ),
      ],
    );
  }
}

class _CommandButtons extends StatelessWidget {
  const _CommandButtons({
    required this.jumpKey,
    required this.animateKey,
    required this.jumpTooltip,
    required this.animateTooltip,
    required this.onJump,
    required this.onAnimate,
  });

  final Key jumpKey;
  final Key animateKey;
  final String jumpTooltip;
  final String animateTooltip;
  final VoidCallback onJump;
  final VoidCallback onAnimate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Tooltip(
            message: jumpTooltip,
            child: Semantics(
              label: jumpTooltip,
              button: true,
              excludeSemantics: true,
              child: FilledButton(
                key: jumpKey,
                onPressed: onJump,
                child: const Text('Jump'),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: animateTooltip,
            child: Semantics(
              label: animateTooltip,
              button: true,
              excludeSemantics: true,
              child: OutlinedButton(
                key: animateKey,
                onPressed: onAnimate,
                child: const Text('Animate'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailHeading extends StatelessWidget {
  const _RailHeading({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(description),
      ],
    );
  }
}

class _ScrollWorkspace extends StatelessWidget {
  const _ScrollWorkspace({
    required this.controller,
    required this.reverse,
    required this.rtl,
    required this.selectedItem,
    required this.itemCount,
    required this.mountedTargetKey,
    required this.compact,
  });

  final SeekoController controller;
  final bool reverse;
  final bool rtl;
  final int? selectedItem;
  final int itemCount;
  final GlobalKey mountedTargetKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Native scroll workspace',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                if (compact)
                  const Text('L1 + L2')
                else ...<Widget>[
                  _CapabilityLabel(
                    icon: Icons.bolt,
                    label: 'L1 pixels',
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  _CapabilityLabel(
                    icon: Icons.sell_outlined,
                    label: 'L2 mounted',
                    color: colors.secondary,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: Scrollbar(
                controller: controller,
                thumbVisibility: true,
                child: ListView.builder(
                  key: const Key('target-navigation-list'),
                  controller: controller,
                  reverse: reverse,
                  itemCount: itemCount,
                  itemExtent: _TargetNavigationPageState._itemExtent,
                  itemBuilder: (BuildContext context, int index) {
                    final String targetKey = 'item-$index';
                    final bool selected = selectedItem == index;
                    return SeekoTag(
                      key: index == 3
                          ? mountedTargetKey
                          : ValueKey<String>(targetKey),
                      controller: controller,
                      targetKey: targetKey,
                      index: index,
                      child: Semantics(
                        label: 'Scroll target item $index, key $targetKey',
                        child: ColoredBox(
                          color: selected
                              ? colors.primaryContainer
                              : Colors.transparent,
                          child: ListTile(
                            minTileHeight: 88,
                            leading: Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.primary
                                    : colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '$index',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: selected
                                          ? colors.onPrimary
                                          : colors.onSurface,
                                    ),
                              ),
                            ),
                            title: Text('Target $index'),
                            subtitle: Text(
                              '$targetKey · native ListView.builder',
                            ),
                            trailing: selected
                                ? const Icon(Icons.my_location)
                                : const Icon(Icons.drag_handle),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityLabel extends StatelessWidget {
  const _CapabilityLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusRail extends StatelessWidget {
  const _StatusRail({
    required this.snapshot,
    required this.result,
    required this.compact,
  });

  final ScrollSnapshot snapshot;
  final ScrollResult? result;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final List<ScrollVisibleTarget> visible = snapshot.visibleTargets;
    final String visibleLabel = visible.isEmpty
        ? 'No tagged targets sampled'
        : visible
              .map((ScrollVisibleTarget target) => target.key ?? target.index)
              .join(', ');
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            _CompactStatus(
              label: 'Outcome',
              value: result?.outcome.name ?? 'No command yet',
              valueKey: const Key('command-result'),
            ),
            _CompactStatus(
              label: 'Position',
              value: '${snapshot.pixels.toStringAsFixed(1)} px',
            ),
            _CompactStatus(label: 'Phase', value: snapshot.phase.name),
            _CompactStatus(
              label: 'Resolution',
              value: result?.resolutionMode.name ?? '—',
            ),
          ],
        ),
      );
    }
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Command result', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (result == null)
          const Text('No command yet')
        else ...<Widget>[
          _StatusValue(
            label: 'Outcome',
            value: result!.outcome.name,
            valueKey: const Key('command-result'),
          ),
          _StatusValue(
            label: 'Requested',
            value: result!.requestedTarget.toString(),
          ),
          _StatusValue(label: 'Resolution', value: result!.resolutionMode.name),
          _StatusValue(
            label: 'Final position',
            value:
                '${result!.finalLogicalPixels?.toStringAsFixed(1) ?? '—'} px',
          ),
        ],
        const Divider(height: 28),
        _StatusValue(
          label: 'Current position',
          value: '${snapshot.pixels.toStringAsFixed(1)} px',
        ),
        _StatusValue(label: 'Phase', value: snapshot.phase.name),
        _StatusValue(label: 'Origin', value: snapshot.origin.name),
        const SizedBox(height: 12),
        Text('Visible targets', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(visibleLabel),
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[content],
    );
  }
}

class _CompactStatus extends StatelessWidget {
  const _CompactStatus({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: _StatusValue(label: label, value: value, valueKey: valueKey),
    );
  }
}

class _StatusValue extends StatelessWidget {
  const _StatusValue({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          SelectableText(value, key: valueKey),
        ],
      ),
    );
  }
}
