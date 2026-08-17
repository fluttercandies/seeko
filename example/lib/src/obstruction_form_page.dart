import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class ObstructionFormPage extends StatefulWidget {
  const ObstructionFormPage({super.key});

  @override
  State<ObstructionFormPage> createState() => _ObstructionFormPageState();
}

class _ObstructionFormPageState extends State<ObstructionFormPage> {
  late final SeekoController _controller;
  ScrollResult? _result;
  double _keyboardInset = 0;

  @override
  void initState() {
    super.initState();
    _controller = SeekoController(
      debugLabel: 'obstruction-form',
      obstructionResolver: (ScrollViewportGeometry viewport) {
        final double start = viewport.viewportExtent < 80 ? 0 : 80;
        final double end = (viewport.viewportExtent - _keyboardInset).clamp(
          start,
          viewport.viewportExtent,
        );
        return VisibleRegion.fromIntervals(<LogicalInterval>[
          if (end > start) LogicalInterval(start, end),
        ]);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reveal(String target) async {
    final ScrollResult result = await _controller.animateToTarget(
      ScrollTarget.key(target),
      placement: const ScrollPlacement.start(),
    );
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    _keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return KeyedSubtree(
      key: const Key('obstruction-form-page'),
      child: Column(
        children: <Widget>[
          const _Header(),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: <Widget>[
                ListView(
                  key: const Key('obstruction-form-list'),
                  controller: _controller,
                  // Flutter 3.32 compatibility; renamed in Flutter 3.41.
                  // ignore: deprecated_member_use
                  cacheExtent: 10000,
                  padding: const EdgeInsets.fromLTRB(20, 96, 20, 48),
                  children: <Widget>[
                    _FormSection(
                      controller: _controller,
                      targetKey: 'form-profile',
                      title: 'Profile',
                      fields: const <_FieldSpec>[
                        _FieldSpec('Full name', 'Morgan Lee'),
                        _FieldSpec('Email', 'morgan@example.com'),
                        _FieldSpec('Phone', '+86 138 0000 0000'),
                      ],
                    ),
                    _FormSection(
                      key: const Key('form-address-target'),
                      controller: _controller,
                      targetKey: 'form-address',
                      title: 'Delivery address',
                      fields: const <_FieldSpec>[
                        _FieldSpec('Street', '128 Motion Avenue'),
                        _FieldSpec('City', 'Shanghai'),
                        _FieldSpec('Postal code', '200000'),
                      ],
                    ),
                    _FormSection(
                      controller: _controller,
                      targetKey: 'form-preferences',
                      title: 'Preferences',
                      fields: const <_FieldSpec>[
                        _FieldSpec('Delivery notes', 'Call on arrival'),
                        _FieldSpec('Dietary notes', 'No peanuts'),
                        _FieldSpec('Receipt name', 'Seeko Studio'),
                      ],
                    ),
                    _FormSection(
                      controller: _controller,
                      targetKey: 'form-confirmation',
                      title: 'Confirmation',
                      fields: const <_FieldSpec>[
                        _FieldSpec('Reference', 'SEEKO-2026'),
                        _FieldSpec('Contact window', '18:00–20:00'),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    key: const Key('form-obstruction-overlay'),
                    elevation: 3,
                    color: Theme.of(context).colorScheme.surface,
                    child: SizedBox(
                      height: 80,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: <Widget>[
                            Text(
                              'Reveal section',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  unawaited(_reveal('form-profile')),
                              child: const Text('Profile'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              key: const Key('form-reveal-address'),
                              onPressed: () =>
                                  unawaited(_reveal('form-address')),
                              icon: const Icon(Icons.location_on_outlined),
                              label: const Text('Address'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () =>
                                  unawaited(_reveal('form-confirmation')),
                              child: const Text('Confirmation'),
                            ),
                            const SizedBox(width: 12),
                            ScenarioStatusBadge(
                              label: _result?.outcome.name ?? 'Ready',
                              widgetKey: const Key('form-reveal-result'),
                              tone: scenarioToneForOutcome(
                                _result?.outcome.name,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const ScenarioPageHeader(
      title: 'Obstructions & Forms',
      description:
          'Reveal fields inside the actual visible interval below a pinned '
          'action bar and above the software keyboard.',
      status: ScenarioStatusBadge(
        label: '80 px obstruction',
        icon: Icons.vertical_align_top,
        tone: ScenarioStatusTone.neutral,
      ),
    );
  }
}

class _FieldSpec {
  const _FieldSpec(this.label, this.value);

  final String label;
  final String value;
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.controller,
    required this.targetKey,
    required this.title,
    required this.fields,
    super.key,
  });

  final SeekoController controller;
  final String targetKey;
  final String title;
  final List<_FieldSpec> fields;

  @override
  Widget build(BuildContext context) {
    return SeekoTag(
      controller: controller,
      targetKey: targetKey,
      child: Card(
        margin: const EdgeInsets.only(bottom: 18),
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (final _FieldSpec field in fields) ...<Widget>[
                TextFormField(
                  initialValue: field.value,
                  decoration: InputDecoration(
                    labelText: field.label,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
