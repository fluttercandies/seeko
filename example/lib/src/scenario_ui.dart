import 'package:flutter/material.dart';

enum ScenarioStatusTone { neutral, active, success, warning, error }

class ScenarioPageHeader extends StatelessWidget {
  const ScenarioPageHeader({
    required this.title,
    required this.description,
    this.actions = const <Widget>[],
    this.status,
    super.key,
  });

  final String title;
  final String description;
  final List<Widget> actions;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('scenario-header'),
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 760;
          final Widget heading = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
          final List<Widget> controls = <Widget>[...actions, ?status];

          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              16,
              compact ? 16 : 20,
              16,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      heading,
                      if (controls.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: controls,
                        ),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(child: heading),
                      if (controls.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 24),
                        Flexible(
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: controls,
                          ),
                        ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class ScenarioStatusBadge extends StatelessWidget {
  const ScenarioStatusBadge({
    required this.label,
    this.icon,
    this.tone = ScenarioStatusTone.neutral,
    this.widgetKey,
    super.key,
  });

  final String label;
  final IconData? icon;
  final ScenarioStatusTone tone;
  final Key? widgetKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (Color foreground, Color background, Color border) = switch (tone) {
      ScenarioStatusTone.active => (
        colors.secondary,
        colors.secondaryContainer.withValues(alpha: 0.45),
        colors.secondary.withValues(alpha: 0.45),
      ),
      ScenarioStatusTone.success => (
        colors.primary,
        colors.primaryContainer.withValues(alpha: 0.38),
        colors.primary.withValues(alpha: 0.42),
      ),
      ScenarioStatusTone.warning => (
        colors.tertiary,
        colors.tertiaryContainer.withValues(alpha: 0.42),
        colors.tertiary.withValues(alpha: 0.42),
      ),
      ScenarioStatusTone.error => (
        colors.error,
        colors.errorContainer.withValues(alpha: 0.42),
        colors.error.withValues(alpha: 0.42),
      ),
      ScenarioStatusTone.neutral => (
        colors.onSurfaceVariant,
        colors.surfaceContainerHigh,
        colors.outlineVariant,
      ),
    };

    return Semantics(
      label: 'Status: $label',
      child: Container(
        constraints: const BoxConstraints(minHeight: 36, maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 17, color: foreground),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                key: widgetKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScenarioPaneHeader extends StatelessWidget {
  const ScenarioPaneHeader({
    required this.title,
    this.description,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 12, 12),
    super.key,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (description != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

ScenarioStatusTone scenarioToneForOutcome(String? outcome) {
  return switch (outcome) {
    null || 'Ready' => ScenarioStatusTone.neutral,
    'completed' || 'clamped' => ScenarioStatusTone.success,
    'moving' || 'running' => ScenarioStatusTone.active,
    'interruptedByUser' || 'superseded' => ScenarioStatusTone.warning,
    _ => ScenarioStatusTone.error,
  };
}
