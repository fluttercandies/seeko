import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';
import 'section_catalog.dart';

class HorizontalSectionTabsPage extends StatefulWidget {
  const HorizontalSectionTabsPage({super.key});

  @override
  State<HorizontalSectionTabsPage> createState() =>
      _HorizontalSectionTabsPageState();
}

class _HorizontalSectionTabsPageState extends State<HorizontalSectionTabsPage> {
  final SeekoController _tabController = SeekoController(
    debugLabel: 'horizontal-section-navigation',
  );
  final SeekoController _contentController = SeekoController(
    debugLabel: 'horizontal-section-content',
  );
  late final SeekoSectionCoordinator<String> _coordinator;
  ScrollResult? _lastResult;
  bool _rtl = false;

  @override
  void initState() {
    super.initState();
    _coordinator = SeekoSectionCoordinator<String>.tagged(
      contentController: _contentController,
      navigationController: _tabController,
      initialSection: catalogSections.first.id,
      viewportAnchor: 0.10,
    );
  }

  @override
  void dispose() {
    _coordinator.dispose();
    _tabController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _select(String section) async {
    final ScrollResult result = await _coordinator.select(section);
    if (mounted) setState(() => _lastResult = result);
  }

  Future<void> _reset() async {
    final ScrollResult result = await _coordinator.select(
      catalogSections.first.id,
      animated: false,
    );
    if (mounted) {
      setState(() {
        _rtl = false;
        _lastResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('horizontal-section-tabs-page'),
      child: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: <Widget>[
            _ScenarioHeader(
              rtl: _rtl,
              onRtlChanged: (bool value) => setState(() => _rtl = value),
              onReset: () => unawaited(_reset()),
            ),
            const Divider(height: 1),
            ValueListenableBuilder<String>(
              valueListenable: _coordinator.selectedSection,
              builder: (BuildContext context, String selected, _) {
                return _SectionTabs(
                  controller: _tabController,
                  selected: selected,
                  onSelected: (String id) => unawaited(_select(id)),
                );
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: Column(
                children: <Widget>[
                  ValueListenableBuilder<String>(
                    valueListenable: _coordinator.selectedSection,
                    builder: (BuildContext context, String selected, _) {
                      return _SelectionStatus(
                        selected: selected,
                        result: _lastResult,
                      );
                    },
                  ),
                  Expanded(
                    child: _SectionContent(controller: _contentController),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioHeader extends StatelessWidget {
  const _ScenarioHeader({
    required this.rtl,
    required this.onRtlChanged,
    required this.onReset,
  });

  final bool rtl;
  final ValueChanged<bool> onRtlChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ScenarioPageHeader(
      title: 'Horizontal Section Tabs',
      description:
          'The active content section drives a variable-width native tab '
          'strip and keeps the selected tab visible.',
      actions: <Widget>[
        SegmentedButton<bool>(
          key: const Key('horizontal-section-rtl'),
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text('LTR')),
            ButtonSegment<bool>(value: true, label: Text('RTL')),
          ],
          selected: <bool>{rtl},
          onSelectionChanged: (Set<bool> value) => onRtlChanged(value.first),
        ),
        IconButton.filledTonal(
          tooltip: 'Reset horizontal section scenario',
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt),
        ),
      ],
      status: const ScenarioStatusBadge(
        label: 'Bidirectional',
        icon: Icons.sync_alt,
        tone: ScenarioStatusTone.active,
      ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.controller,
    required this.selected,
    required this.onSelected,
  });

  final SeekoController controller;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: catalogSections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final CatalogSection section = catalogSections[index];
          final bool isSelected = section.id == selected;
          return SeekoTag(
            controller: controller,
            targetKey: section.id,
            child: TextButton.icon(
              key: Key('horizontal-section-${section.id}'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                backgroundColor: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => onSelected(section.id),
              icon: Icon(section.icon, size: 19),
              label: Text(section.label),
            ),
          );
        },
      ),
    );
  }
}

class _SelectionStatus extends StatelessWidget {
  const _SelectionStatus({required this.selected, required this.result});

  final String selected;
  final ScrollResult? result;

  @override
  Widget build(BuildContext context) {
    final CatalogSection section = sectionById(catalogSections, selected);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Selected: ${section.label}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ScenarioStatusBadge(
              label: result == null ? 'Ready' : result!.outcome.name,
              tone: scenarioToneForOutcome(result?.outcome.name),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionContent extends StatelessWidget {
  const _SectionContent({required this.controller});

  final SeekoController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final CatalogSection trailingSection = catalogSections.last;
        final double trailingSectionExtent =
            56 +
            trailingSection.items.fold<double>(
              0,
              (double extent, CatalogItem item) => extent + item.height + 14,
            );
        final double requiredTrailingSpace =
            constraints.maxHeight - trailingSectionExtent;
        final double trailingSpace = requiredTrailingSpace > 32
            ? requiredTrailingSpace
            : 32;
        return CustomScrollView(
          key: const Key('horizontal-section-content'),
          controller: controller,
          slivers: <Widget>[
            for (final CatalogSection section in catalogSections)
              SliverMainAxisGroup(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: SeekoTag(
                      key: ValueKey<String>(
                        'horizontal-content-anchor-${section.id}',
                      ),
                      controller: controller,
                      targetKey: SeekoSectionKey<String>.header(section.id),
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SectionHeaderDelegate(section: section),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final CatalogItem item = section.items[index];
                      return SeekoTag(
                        controller: controller,
                        targetKey: SeekoSectionKey<String>.item(
                          section.id,
                          index,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: item.height + 14,
                          ),
                          child: _CatalogItemCard(item: item),
                        ),
                      );
                    }, childCount: section.items.length),
                  ),
                ],
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: trailingSpace)),
          ],
        );
      },
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({required this.section});

  final CatalogSection section;

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Icon(section.icon, size: 20),
              const SizedBox(width: 10),
              Text(
                section.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate oldDelegate) =>
      oldDelegate.section != section;
}

class _CatalogItemCard extends StatelessWidget {
  const _CatalogItemCard({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 7),
              Text(item.description),
            ],
          ),
        ),
      ),
    );
  }
}
