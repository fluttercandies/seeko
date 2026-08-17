import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

enum _MotionChoice { adaptive, duration, velocity, spring, instant }

class NaturalMotionPage extends StatefulWidget {
  const NaturalMotionPage({super.key});

  @override
  State<NaturalMotionPage> createState() => _NaturalMotionPageState();
}

class _NaturalMotionPageState extends State<NaturalMotionPage> {
  final SeekoController _controller = SeekoController(
    debugLabel: 'natural-motion',
  );
  _MotionChoice _choice = _MotionChoice.adaptive;
  ScrollResult? _result;
  bool _running = false;
  int? _target;

  ScrollMotion get _motion => switch (_choice) {
    _MotionChoice.adaptive => const ScrollMotion.adaptive(),
    _MotionChoice.duration => const ScrollMotion.duration(
      duration: Duration(milliseconds: 720),
      curve: Curves.easeInOutCubic,
    ),
    _MotionChoice.velocity => const ScrollMotion.velocity(
      pixelsPerSecond: 1600,
    ),
    _MotionChoice.spring => const ScrollMotion.spring(),
    _MotionChoice.instant => const ScrollMotion.instant(),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _seek(int index) async {
    setState(() {
      _running = true;
      _target = index;
    });
    final ScrollResult result = await _controller.animateToTarget(
      ScrollTarget.key('motion-item-$index'),
      placement: const ScrollPlacement.center(),
      motion: _motion,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  void _stop() {
    _controller.stop();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _reset() async {
    _controller.stop();
    final ScrollResult result = await _controller.jumpToTarget(
      const ScrollTarget.edge(ScrollEdge.leading),
    );
    if (!mounted) return;
    setState(() {
      _target = null;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('natural-motion-page'),
      child: Column(
        children: <Widget>[
          _Header(
            choice: _choice,
            running: _running,
            result: _result,
            onChoiceChanged: (_MotionChoice choice) {
              setState(() => _choice = choice);
            },
            onNear: () => unawaited(_seek(6)),
            onFar: () => unawaited(_seek(32)),
            onStop: _stop,
            onReset: () => unawaited(_reset()),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _controller,
              child: ListView.builder(
                key: const Key('natural-motion-list'),
                controller: _controller,
                // Flutter 3.32 compatibility; renamed in Flutter 3.41.
                // ignore: deprecated_member_use
                cacheExtent: 10000,
                padding: const EdgeInsets.all(16),
                itemCount: 40,
                itemBuilder: (BuildContext context, int index) {
                  final bool selected = index == _target;
                  return SeekoTag(
                    controller: _controller,
                    targetKey: 'motion-item-$index',
                    child: AnimatedContainer(
                      key: Key('natural-motion-target-$index'),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      height: 88.0 + (index % 5) * 12,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: selected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : null,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  'Motion target ${index + 1}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text('${88 + (index % 5) * 12} px extent'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.choice,
    required this.running,
    required this.result,
    required this.onChoiceChanged,
    required this.onNear,
    required this.onFar,
    required this.onStop,
    required this.onReset,
  });

  final _MotionChoice choice;
  final bool running;
  final ScrollResult? result;
  final ValueChanged<_MotionChoice> onChoiceChanged;
  final VoidCallback onNear;
  final VoidCallback onFar;
  final VoidCallback onStop;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final String status = running ? 'running' : result?.outcome.name ?? 'Ready';
    final Object? terminalPhase = result?.diagnostics?['terminalPhase'];
    return ScenarioPageHeader(
      title: 'Natural Motion',
      description:
          'Compare adaptive, fixed-duration, velocity, spring, and instant policies '
          'on the same native variable-height list.',
      actions: <Widget>[
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<_MotionChoice>(
            // Flutter 3.32 compatibility; renamed to initialValue later.
            // ignore: deprecated_member_use
            value: choice,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Motion',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: (_MotionChoice? value) {
              if (value != null) onChoiceChanged(value);
            },
            items: <DropdownMenuItem<_MotionChoice>>[
              for (final _MotionChoice value in _MotionChoice.values)
                DropdownMenuItem<_MotionChoice>(
                  value: value,
                  child: Text(value.name),
                ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          key: const Key('natural-motion-near'),
          onPressed: running ? null : onNear,
          icon: const Icon(Icons.near_me_outlined),
          label: const Text('Near'),
        ),
        FilledButton.icon(
          key: const Key('natural-motion-far'),
          onPressed: running ? null : onFar,
          icon: const Icon(Icons.flight_takeoff),
          label: const Text('Far'),
        ),
        IconButton.filledTonal(
          tooltip: 'Stop active motion',
          onPressed: running ? onStop : null,
          icon: const Icon(Icons.stop),
        ),
        IconButton.filledTonal(
          tooltip: 'Reset motion scenario',
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt),
        ),
        if (result != null)
          Text(
            '${result!.elapsed.inMilliseconds} ms · '
            'error ${(result!.finalError ?? 0).toStringAsFixed(2)} px · '
            '${result!.correctionCount} corrections'
            '${terminalPhase == null ? '' : ' · $terminalPhase'}',
            key: const Key('natural-motion-details'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
      status: ScenarioStatusBadge(
        label: status,
        widgetKey: const Key('natural-motion-result'),
        icon: running ? Icons.motion_photos_on : Icons.check_circle_outline,
        tone: running
            ? ScenarioStatusTone.active
            : scenarioToneForOutcome(status),
      ),
    );
  }
}
